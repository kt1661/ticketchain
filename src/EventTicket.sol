// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IEventTicket} from "./interfaces/IEventTicket.sol";

/// @title EventTicket
/// @notice One contract per event. Each token is one ticket.
/// @dev OWNER: Dev 1 (Core contracts). This stub implements the happy path so the
///      rest of the team can build against it. Search for `TODO` for hardening work.
contract EventTicket is ERC721, Ownable, IEventTicket {
    EventInfo private _info;
    uint256 private _nextId = 1;
    uint256 private _minted;

    mapping(uint256 => string) private _seat;
    mapping(uint256 => bool) private _checkedIn;

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
    /// @dev TODO (Dev 1 + Dev 3): decide authorization model. Should checkIn be
    ///      callable only by an authorized verifier role rather than anyone?
    ///      Right now it's open — that's a deliberate gap to discuss in the writeup.
    function checkIn(uint256 tokenId) external {
        require(_ownerOf(tokenId) != address(0), "EventTicket: nonexistent");
        require(!_checkedIn[tokenId], "EventTicket: already checked in");
        _checkedIn[tokenId] = true;
        emit CheckedIn(tokenId, ownerOf(tokenId));
    }

    /// @inheritdoc IEventTicket
    function isCheckedIn(uint256 tokenId) external view returns (bool) {
        return _checkedIn[tokenId];
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
