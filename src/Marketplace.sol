// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IEventTicket} from "./interfaces/IEventTicket.sol";
import {IEventFactory} from "./interfaces/IEventFactory.sol";
import {IMarketplace} from "./interfaces/IMarketplace.sol";

/// @title Marketplace
/// @notice Rule-bound resale: price caps + organizer royalties, atomic settlement.
/// @dev Hardened resale path: CEI + nonReentrant guard, royalty/seller payment
///      split, overpayment refund, approval check on listing, registry check that
///      the ticket belongs to a legitimate EventFactory event.
contract Marketplace is IMarketplace, ReentrancyGuard {
    /// @notice Resale price cap as basis points of face value (e.g. 11_000 = 110%).
    uint256 public constant MAX_RESALE_BPS = 11_000;

    /// @notice Organizer royalty on resale in basis points (e.g. 500 = 5%).
    uint256 public constant ROYALTY_BPS = 500;

    /// @notice The registry used to confirm a ticket contract is a legitimate event.
    IEventFactory public immutable factory;

    // eventContract => tokenId => Listing
    mapping(address => mapping(uint256 => Listing)) private _listings;

    constructor(address factory_) {
        factory = IEventFactory(factory_);
    }

    /// @inheritdoc IMarketplace
    /// @dev Proof of ownership: `ownerOf(tokenId) == msg.sender` (below) is the
    ///      seller proving, on-chain, that they currently hold the ticket they're
    ///      listing for sale. Proof of event legitimacy: `factory.isLegitimate` confirms
    ///      `eventContract` was actually deployed by the trusted EventFactory, so a
    ///      buyer calling `buy(eventContract, tokenId)` can only ever receive a
    ///      ticket for a real, registered event — never a counterfeit look-alike.
    function list(address eventContract, uint256 tokenId, uint256 price) external {
        require(factory.isLegitimate(eventContract), "Marketplace: unknown event");
        IERC721 nft = IERC721(eventContract);
        require(nft.ownerOf(tokenId) == msg.sender, "Marketplace: not owner");
        require(price > 0, "Marketplace: zero price");
        require(price <= maxResalePrice(eventContract, tokenId), "Marketplace: over cap");
        require(
            nft.getApproved(tokenId) == address(this) || nft.isApprovedForAll(msg.sender, address(this)),
            "Marketplace: not approved"
        );

        _listings[eventContract][tokenId] = Listing({seller: msg.sender, price: price, active: true});
        emit Listed(eventContract, tokenId, msg.sender, price);
    }

    /// @inheritdoc IMarketplace
    function cancelListing(address eventContract, uint256 tokenId) external {
        Listing storage l = _listings[eventContract][tokenId];
        require(l.active, "Marketplace: not listed");
        require(l.seller == msg.sender, "Marketplace: not seller");
        l.active = false;
        emit Cancelled(eventContract, tokenId);
    }

    /// @inheritdoc IMarketplace
    /// @dev Hardened resale settlement:
    ///   1. Checks-Effects-Interactions: validate, then mark the listing inactive
    ///      (effect) BEFORE any external calls (interactions) — a reentrant call
    ///      re-reading the listing sees it already closed.
    ///   2. `nonReentrant` blocks any reentrant call into this contract outright.
    ///   3. Payment is split: royalty -> organizer, remainder -> seller.
    ///   4. Any msg.value above price is refunded to the buyer.
    ///   5. Token transfer (transferFrom) happens last.
    /// Also re-verifies the seller still owns the token before moving any money:
    /// a listing goes stale if the seller transferred the ticket away directly
    /// (bypassing the marketplace) after listing, and that must fail fast with a
    /// clear reason instead of reverting deep inside the final transferFrom.
    function buy(address eventContract, uint256 tokenId)
        external
        payable
        nonReentrant
    {
        Listing memory l = _listings[eventContract][tokenId];
        require(l.active, "Marketplace: not listed");
        require(msg.value >= l.price, "Marketplace: underpaid");

        IERC721 nft = IERC721(eventContract);
        require(nft.ownerOf(tokenId) == l.seller, "Marketplace: stale listing");

        // EFFECT
        _listings[eventContract][tokenId].active = false;

        // INTERACTIONS
        uint256 royalty = (l.price * ROYALTY_BPS) / 10_000;
        address organizer = _organizerOf(eventContract);

        (bool rOk,) = organizer.call{value: royalty}("");
        require(rOk, "Marketplace: royalty xfer failed");
        (bool sOk,) = l.seller.call{value: l.price - royalty}("");
        require(sOk, "Marketplace: seller xfer failed");

        // Refund overpayment
        if (msg.value > l.price) {
            (bool refOk,) = msg.sender.call{value: msg.value - l.price}("");
            require(refOk, "Marketplace: refund failed");
        }

        nft.transferFrom(l.seller, msg.sender, tokenId);
        emit Sold(eventContract, tokenId, l.seller, msg.sender, l.price, royalty);
    }

    /// @inheritdoc IMarketplace
    function getListing(address eventContract, uint256 tokenId)
        external
        view
        returns (Listing memory)
    {
        return _listings[eventContract][tokenId];
    }

    /// @inheritdoc IMarketplace
    function maxResalePrice(address eventContract, uint256 /*tokenId*/)
        public
        view
        returns (uint256)
    {
        uint256 faceValue = IEventTicket(eventContract).eventInfo().faceValue;
        return (faceValue * MAX_RESALE_BPS) / 10_000;
    }

    /// @dev The organizer is the Ownable owner of the event contract.
    function _organizerOf(address eventContract) internal view returns (address) {
        // Ownable exposes owner(); cast via low-level staticcall to avoid extra import.
        (bool ok, bytes memory data) =
            eventContract.staticcall(abi.encodeWithSignature("owner()"));
        require(ok && data.length == 32, "Marketplace: no owner()");
        return abi.decode(data, (address));
    }
}
