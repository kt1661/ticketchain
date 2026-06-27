// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IEventTicket} from "./interfaces/IEventTicket.sol";
import {IMarketplace} from "./interfaces/IMarketplace.sol";

/// @title Marketplace
/// @notice Rule-bound resale: price caps + organizer royalties, atomic settlement.
/// @dev OWNER: Dev 2 (Marketplace). This is a STARTING POINT with the core resale
///      path sketched. The `TODO`s are the real assignment — implement and harden them.
contract Marketplace is IMarketplace, ReentrancyGuard {
    /// @notice Resale price cap as basis points of face value (e.g. 11_000 = 110%).
    uint256 public constant MAX_RESALE_BPS = 11_000;

    /// @notice Organizer royalty on resale in basis points (e.g. 500 = 5%).
    uint256 public constant ROYALTY_BPS = 500;

    // eventContract => tokenId => Listing
    mapping(address => mapping(uint256 => Listing)) private _listings;

    /// @inheritdoc IMarketplace
    function list(address eventContract, uint256 tokenId, uint256 price) external {
        IERC721 nft = IERC721(eventContract);
        require(nft.ownerOf(tokenId) == msg.sender, "Marketplace: not owner");
        require(price > 0, "Marketplace: zero price");
        require(price <= maxResalePrice(eventContract, tokenId), "Marketplace: over cap");

        // Seller must approve this contract to transfer the token before buy() works.
        // TODO (Dev 2): consider requiring approval here and reverting early with a
        //               clear message if the marketplace isn't approved.

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
    /// @dev TODO (Dev 2): This is the security-critical function. Requirements:
    ///   1. Follow Checks-Effects-Interactions: read+validate, then mark listing
    ///      inactive (effect), THEN move funds and the token (interactions).
    ///   2. Use nonReentrant.
    ///   3. Split payment: royalty -> organizer, remainder -> seller.
    ///   4. Refund any msg.value above price.
    ///   5. transferFrom(seller, buyer, tokenId).
    /// The skeleton below is intentionally INCOMPLETE / naive so you can write the
    /// hardened version and demonstrate the before/after in your security writeup.
    function buy(address eventContract, uint256 tokenId)
        external
        payable
        nonReentrant
    {
        Listing memory l = _listings[eventContract][tokenId];
        require(l.active, "Marketplace: not listed");
        require(msg.value >= l.price, "Marketplace: underpaid");

        // EFFECT
        _listings[eventContract][tokenId].active = false;

        // INTERACTIONS
        // TODO (Dev 2): compute royalty, pay organizer + seller, refund excess.
        //               For now, naive single payment to seller (HARDEN THIS):
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

        IERC721(eventContract).transferFrom(l.seller, msg.sender, tokenId);
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
