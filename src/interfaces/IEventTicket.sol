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

    /// @notice Emitted when the organizer grants/revokes a verifier's check-in rights.
    event VerifierUpdated(address indexed verifier, bool authorized);

    /// @notice Emitted whenever the organizer sets or updates the off-chain
    ///         metadata pointer/hash, giving a full on-chain audit trail of every
    ///         (authorized) change — not just the current value.
    event MetadataUpdated(string uri, bytes32 hash);

    /*//////////////////////////////////////////////////////////////
                               STRUCTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Immutable, on-chain event fields set at deployment. Distinct from the
    ///         off-chain metadata (art, long description, etc.) pointed to by
    ///         `metadataURI`/`metadataHash` below, which the organizer CAN update.
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

    /// @notice Mark a ticket as used at the gate on gate staff's attestation alone
    ///         (e.g. a manual photo-ID check). One-way; reverts if already used.
    /// @dev Callable only by the organizer (owner) or an address the organizer has
    ///      authorized via `setVerifier` — gate staff should be granted verifier
    ///      status rather than the check being open to anyone. This path does NOT
    ///      cryptographically confirm the presenter controls the owning wallet —
    ///      use `checkInWithSignature` when that proof is required.
    function checkIn(uint256 tokenId) external;

    /// @notice Mark a ticket as used at the gate, requiring a signature from the
    ///         ticket's *current owner* proving they control the owning wallet.
    /// @dev The holder signs an EIP-712 `CheckIn(uint256 tokenId,uint256 deadline)`
    ///      message (see `checkInDigest`) with their wallet at the gate; the
    ///      verifier submits it here. Reverts if the deadline has passed, the
    ///      signature doesn't recover to the current owner, or the ticket is
    ///      already checked in. Still restricted to the organizer/an authorized
    ///      verifier, same as `checkIn`.
    /// @param tokenId The ticket being checked in.
    /// @param deadline Unix timestamp after which the signature is no longer valid.
    /// @param signature The holder's EIP-712 signature over `checkInDigest(tokenId, deadline)`.
    function checkInWithSignature(uint256 tokenId, uint256 deadline, bytes calldata signature) external;

    /// @notice The EIP-712 digest a ticket holder must sign to authorize
    ///         `checkInWithSignature` for `tokenId` up until `deadline`.
    function checkInDigest(uint256 tokenId, uint256 deadline) external view returns (bytes32);

    /// @notice Whether a ticket has already been checked in.
    function isCheckedIn(uint256 tokenId) external view returns (bool);

    /// @notice Grant or revoke an address's ability to call `checkIn`. Organizer only.
    /// @param verifier The gate-staff wallet to authorize (or deauthorize).
    /// @param authorized True to grant check-in rights, false to revoke.
    function setVerifier(address verifier, bool authorized) external;

    /// @notice Whether `account` is authorized to call `checkIn` (besides the organizer).
    function isVerifier(address account) external view returns (bool);

    /*//////////////////////////////////////////////////////////////
                    OFF-CHAIN METADATA INTEGRITY
    //////////////////////////////////////////////////////////////*/

    /// @notice Point at (and commit to the integrity of) an off-chain metadata
    ///         file — event art, seat map, long-form description, etc. Organizer
    ///         only. Anyone can independently verify the file hasn't been swapped
    ///         by fetching `uri`, hashing it, and comparing to `hash`.
    /// @dev This is intentionally re-callable: a legitimate change (e.g. a venue
    ///      change) is just the organizer calling this again with a new uri/hash.
    ///      Every call emits `MetadataUpdated`, so the full history of changes —
    ///      not just the latest value — is auditable from event logs. This does
    ///      NOT affect ticket validity or ownership; it only proves the *content*
    ///      pointed to by `uri` matches `hash` as of the organizer's last update.
    /// @param uri Where to fetch the metadata file (e.g. an IPFS URI or path).
    /// @param hash keccak256 of the file's exact bytes at `uri`.
    function setMetadata(string calldata uri, bytes32 hash) external;

    /// @notice The current off-chain metadata location.
    function metadataURI() external view returns (string memory);

    /// @notice The current off-chain metadata content hash (keccak256 of the file).
    function metadataHash() external view returns (bytes32);

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
