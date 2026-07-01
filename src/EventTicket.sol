// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IEventTicket} from "./interfaces/IEventTicket.sol";

/// @title EventTicket
/// @notice One contract per event. Each token is one ticket.
contract EventTicket is ERC721, Ownable, IEventTicket {
    EventInfo private _info;
    uint256 private _nextId = 1;
    uint256 private _minted;

    mapping(uint256 => string) private _seat;
    mapping(uint256 => bool) private _checkedIn;
    mapping(address => bool) private _verifiers;

    /// @param organizer The wallet that controls minting (the event organizer).
    /// @param info_ Immutable event metadata.
    constructor(address organizer, EventInfo memory info_)
        ERC721(info_.name, "TCKT")
        Ownable(organizer)
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
    function checkIn(uint256 tokenId) external {
        require(_ownerOf(tokenId) != address(0), "EventTicket: nonexistent");
        require(msg.sender == owner() || _verifiers[msg.sender], "EventTicket: not authorized");
        require(!_checkedIn[tokenId], "EventTicket: already checked in");
        _checkedIn[tokenId] = true;
        emit CheckedIn(tokenId, ownerOf(tokenId));
    }

    /// @inheritdoc IEventTicket
    function isCheckedIn(uint256 tokenId) external view returns (bool) {
        return _checkedIn[tokenId];
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
