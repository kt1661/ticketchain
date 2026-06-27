// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IEventTicket} from "./IEventTicket.sol";

/// @title IEventFactory
/// @notice Deploys EventTicket contracts and keeps a registry of legitimate events.
/// @dev The registry is the anti-counterfeit anchor: a verifier checks isLegitimate()
///      to confirm a ticket contract was actually created here.
interface IEventFactory {
    /// @notice Emitted when a new event ticket contract is deployed.
    event EventCreated(address indexed eventContract, address indexed organizer, string name);

    /// @notice Deploy a new EventTicket contract for an organizer.
    /// @param info The event metadata.
    /// @return eventContract The address of the newly deployed EventTicket.
    function createEvent(IEventTicket.EventInfo calldata info)
        external
        returns (address eventContract);

    /// @notice True if `eventContract` was deployed by this factory.
    function isLegitimate(address eventContract) external view returns (bool);

    /// @notice All event contracts deployed by this factory.
    function allEvents() external view returns (address[] memory);
}
