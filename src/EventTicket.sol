// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {IEventTicket} from "./interfaces/IEventTicket.sol";

/// @title EventTicket
/// @notice One contract per event. Each token is one ticket.
contract EventTicket is ERC721, Ownable, EIP712, IEventTicket {
    /// @dev EIP-712 typehash for the holder's "I am present, check me in" message.
    ///      Binding tokenId + deadline (plus the domain separator's chainId and
    ///      verifyingContract) stops a captured signature from being replayed
    ///      against a different ticket, a different event contract, or long after
    ///      the gate window has closed.
    bytes32 private constant CHECKIN_TYPEHASH = keccak256("CheckIn(uint256 tokenId,uint256 deadline)");

    EventInfo private _info;
    uint256 private _nextId = 1;
    uint256 private _minted;

    mapping(uint256 => string) private _seat;
    mapping(uint256 => bool) private _checkedIn;
    mapping(address => bool) private _verifiers;

    string private _metadataURI;
    bytes32 private _metadataHash;

    /// @param organizer The wallet that controls minting (the event organizer).
    /// @param info_ Immutable event metadata.
    constructor(address organizer, EventInfo memory info_)
        ERC721(info_.name, "TCKT")
        Ownable(organizer)
        EIP712(info_.name, "1")
    {
        _info = info_;
    }

    /// @inheritdoc IEventTicket
    function mint(address to, string calldata seat)
        external
        onlyOwner
        returns (uint256 tokenId)
    {
        require(_minted < _info.maxSupply, "EventTicket: sold out");
        tokenId = _nextId++;
        _minted++;
        _seat[tokenId] = seat;
        _safeMint(to, tokenId);
        emit TicketMinted(tokenId, to, seat);
    }

    /// @inheritdoc IEventTicket
    /// @dev Authorization model: only the organizer (owner) or an address the
    ///      organizer has explicitly granted verifier status may check tickets in.
    ///      This closes the "anyone can check in / grief" gap — gate staff get
    ///      verifier status via `setVerifier` instead of the function being open.
    ///      NOTE: this path takes gate staff's word that the presenter is the
    ///      holder (e.g. they checked a photo ID). It does not cryptographically
    ///      prove wallet control — use `checkInWithSignature` for that.
    function checkIn(uint256 tokenId) external {
        address holder = _requireExists(tokenId);
        require(msg.sender == owner() || _verifiers[msg.sender], "EventTicket: not authorized");
        require(!_checkedIn[tokenId], "EventTicket: already checked in");
        _markCheckedIn(tokenId, holder);
    }

    /// @inheritdoc IEventTicket
    /// @dev Cryptographic holder-presence check: the verifier submits a signature
    ///      produced by the *current owner's* wallet over an EIP-712 `CheckIn`
    ///      message (tokenId + deadline), signed at the gate (e.g. via
    ///      eth_signTypedData_v4 in the holder's own wallet). This proves the
    ///      person presenting the ticket controls the owning private key, not just
    ///      that gate staff eyeballed an ID. The deadline bounds how long a
    ///      captured signature stays valid; the domain separator (chainId +
    ///      this contract's address) stops it being replayed elsewhere; and
    ///      "already checked in" makes it single-use once it succeeds.
    function checkInWithSignature(uint256 tokenId, uint256 deadline, bytes calldata signature) external {
        address holder = _requireExists(tokenId);
        require(msg.sender == owner() || _verifiers[msg.sender], "EventTicket: not authorized");
        require(block.timestamp <= deadline, "EventTicket: signature expired");
        require(!_checkedIn[tokenId], "EventTicket: already checked in");

        address signer = ECDSA.recover(checkInDigest(tokenId, deadline), signature);
        require(signer == holder, "EventTicket: invalid holder signature");

        _markCheckedIn(tokenId, holder);
    }

    /// @inheritdoc IEventTicket
    function checkInDigest(uint256 tokenId, uint256 deadline) public view returns (bytes32) {
        return _hashTypedDataV4(keccak256(abi.encode(CHECKIN_TYPEHASH, tokenId, deadline)));
    }

    /// @inheritdoc IEventTicket
    function isCheckedIn(uint256 tokenId) external view returns (bool) {
        return _checkedIn[tokenId];
    }

    /// @dev Shared existence check for both check-in paths.
    function _requireExists(uint256 tokenId) internal view returns (address holder) {
        holder = _ownerOf(tokenId);
        require(holder != address(0), "EventTicket: nonexistent");
    }

    /// @dev Shared state update + event for both check-in paths.
    function _markCheckedIn(uint256 tokenId, address holder) internal {
        _checkedIn[tokenId] = true;
        emit CheckedIn(tokenId, holder);
    }

    /// @inheritdoc IEventTicket
    function setVerifier(address verifier, bool authorized) external onlyOwner {
        _verifiers[verifier] = authorized;
        emit VerifierUpdated(verifier, authorized);
    }

    /// @inheritdoc IEventTicket
    function isVerifier(address account) external view returns (bool) {
        return _verifiers[account];
    }

    /// @inheritdoc IEventTicket
    function setMetadata(string calldata uri, bytes32 hash) external onlyOwner {
        _metadataURI = uri;
        _metadataHash = hash;
        emit MetadataUpdated(uri, hash);
    }

    /// @inheritdoc IEventTicket
    function metadataURI() external view returns (string memory) {
        return _metadataURI;
    }

    /// @inheritdoc IEventTicket
    function metadataHash() external view returns (bytes32) {
        return _metadataHash;
    }

    /// @inheritdoc IEventTicket
    function eventInfo() external view returns (EventInfo memory) {
        return _info;
    }

    /// @inheritdoc IEventTicket
    function seatOf(uint256 tokenId) external view returns (string memory) {
        return _seat[tokenId];
    }

    /// @inheritdoc IEventTicket
    function totalMinted() external view returns (uint256) {
        return _minted;
    }
}
