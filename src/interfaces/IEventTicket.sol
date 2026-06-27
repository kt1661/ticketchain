// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IEventTicket
/// @notice Frozen interface for the per-event ticket contract (ERC-721).
/// @dev FREEZE THIS on day 2. Frontend, marketplace, and verifier all build
///      against these signatures so the team can work in parallel.
interface IEventTicket {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a new ticket is minted to a buyer.
    event TicketMinted(uint256 indexed tokenId, address indexed to, string seat);

    /// @notice Emitted when a ticket is checked in at the gate (one-way).
    event CheckedIn(uint256 indexed tokenId, address indexed holder);

    /*//////////////////////////////////////////////////////////////
                               STRUCTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Immutable metadata describing the event this contract issues tickets for.
    struct EventInfo {
        string name;
        uint256 eventDate; // unix timestamp
        string venue;
        uint256 faceValue; // in wei
        uint256 maxSupply;
    }

    /*//////////////////////////////////////////////////////////////
                              MINTING
    //////////////////////////////////////////////////////////////*/

    /// @notice Mint a new ticket. Restricted to the organizer/owner.
    /// @param to The recipient wallet.
    /// @param seat A human-readable seat/tier label (e.g. "A-12", "GA").
    /// @return tokenId The newly minted token id.
    function mint(address to, string calldata seat) external returns (uint256 tokenId);

    /*//////////////////////////////////////////////////////////////
                            GATE / CHECK-IN
    //////////////////////////////////////////////////////////////*/

    /// @notice Mark a ticket as used at the gate. One-way; reverts if already used.
    /// @dev Verifier confirms the holder controls the owning wallet off-chain (signature),
    ///      then this flips the flag so the ticket cannot be reused.
    function checkIn(uint256 tokenId) external;

    /// @notice Whether a ticket has already been checked in.
    function isCheckedIn(uint256 tokenId) external view returns (bool);

    /*//////////////////////////////////////////////////////////////
                               VIEWS
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the event metadata.
    function eventInfo() external view returns (EventInfo memory);

    /// @notice The seat label for a given token.
    function seatOf(uint256 tokenId) external view returns (string memory);

    /// @notice Total tickets minted so far (never exceeds maxSupply).
    function totalMinted() external view returns (uint256);

    // Inherited from ERC-721 (declared here for reference; do not redeclare in impl):
    // function ownerOf(uint256 tokenId) external view returns (address);
    // function transferFrom(address from, address to, uint256 tokenId) external;
}
