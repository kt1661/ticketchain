// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {EventTicket} from "./EventTicket.sol";
import {IEventTicket} from "./interfaces/IEventTicket.sol";
import {IEventFactory} from "./interfaces/IEventFactory.sol";

/// @title EventFactory
/// @notice Deploys EventTicket contracts and records them in a registry.
/// @dev OWNER: Dev 1 (Core contracts). The registry is the anti-counterfeit anchor.
contract EventFactory is IEventFactory {
    mapping(address => bool) private _legit;
    address[] private _events;

    /// @inheritdoc IEventFactory
    function createEvent(IEventTicket.EventInfo calldata info)
        external
        returns (address eventContract)
    {
        // msg.sender becomes the organizer/owner of the new event contract.
        EventTicket t = new EventTicket(msg.sender, info);
        eventContract = address(t);
        _legit[eventContract] = true;
        _events.push(eventContract);
        emit EventCreated(eventContract, msg.sender, info.name);
    }

    /// @inheritdoc IEventFactory
    function isLegitimate(address eventContract) external view returns (bool) {
        return _legit[eventContract];
    }

    /// @inheritdoc IEventFactory
    function allEvents() external view returns (address[] memory) {
        return _events;
    }
}
