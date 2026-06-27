// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IMarketplace
/// @notice Handles primary sales and rule-bound secondary resale.
/// @dev Enforces price caps and organizer royalties; settles payment atomically
///      with transfer. All resale MUST route through here so rules can't be bypassed.
interface IMarketplace {
    /// @notice Emitted when a ticket is listed for resale.
    event Listed(
        address indexed eventContract,
        uint256 indexed tokenId,
        address indexed seller,
        uint256 price
    );

    /// @notice Emitted when a listing is cancelled.
    event Cancelled(address indexed eventContract, uint256 indexed tokenId);

    /// @notice Emitted when a ticket is sold (primary or secondary).
    event Sold(
        address indexed eventContract,
        uint256 indexed tokenId,
        address seller,
        address indexed buyer,
        uint256 price,
        uint256 royaltyPaid
    );

    /// @notice A resale listing.
    struct Listing {
        address seller;
        uint256 price; // in wei
        bool active;
    }

    /// @notice List a ticket for resale. Reverts if price exceeds the cap
    ///         (faceValue * maxResaleBps / 10_000).
    function list(address eventContract, uint256 tokenId, uint256 price) external;

    /// @notice Cancel an active listing. Only the seller may call.
    function cancelListing(address eventContract, uint256 tokenId) external;

    /// @notice Buy a listed ticket. Pays seller minus royalty, routes royalty to
    ///         the organizer, and transfers the token to the buyer atomically.
    function buy(address eventContract, uint256 tokenId) external payable;

    /// @notice Read a listing.
    function getListing(address eventContract, uint256 tokenId)
        external
        view
        returns (Listing memory);

    /// @notice The max resale price allowed for a given ticket (in wei).
    function maxResalePrice(address eventContract, uint256 tokenId)
        external
        view
        returns (uint256);
}
