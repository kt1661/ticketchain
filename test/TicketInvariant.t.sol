// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {EventFactory} from "../src/EventFactory.sol";
import {EventTicket} from "../src/EventTicket.sol";
import {IEventTicket} from "../src/interfaces/IEventTicket.sol";

/// @notice OWNER: Dev 3 (Security & testing).
/// Invariant tests assert properties that must hold no matter what sequence of
/// calls the fuzzer throws at the contract.
///
/// Properties checked:
///   1. totalMinted never exceeds maxSupply.
///   2. A checked-in ticket is never un-checked-in.
contract TicketInvariantTest is StdInvariant, Test {
    EventFactory factory;
    EventTicket ticket;
    TicketHandler handler;

    function setUp() public {
        factory = new EventFactory();

        IEventTicket.EventInfo memory info = IEventTicket.EventInfo({
            name: "Invariant Event",
            eventDate: block.timestamp + 30 days,
            venue: "NYU Arena",
            faceValue: 0.05 ether,
            maxSupply: 50
        });

        address organizer = address(this); // this contract is the organizer/owner
        ticket = EventTicket(factory.createEvent(info));

        handler = new TicketHandler(ticket, organizer);
        // Only let the fuzzer drive the handler, not the raw contracts.
        targetContract(address(handler));
    }

    /// @notice Minting can never exceed the configured supply.
    function invariant_SupplyNeverExceeded() public view {
        assertLe(ticket.totalMinted(), ticket.eventInfo().maxSupply);
    }

    /// @notice Once the handler records a check-in, the contract must still report it.
    function invariant_CheckInsAreSticky() public view {
        uint256[] memory ids = handler.checkedInIds();
        for (uint256 i = 0; i < ids.length; i++) {
            assertTrue(ticket.isCheckedIn(ids[i]));
        }
    }
}

/// @notice Bounds the fuzzer to realistic actions so invariants are meaningful.
contract TicketHandler is Test {
    EventTicket ticket;
    address organizer;

    uint256[] private _checkedIn;

    constructor(EventTicket _ticket, address _organizer) {
        ticket = _ticket;
        organizer = _organizer;
    }

    function mint(address to) external {
        if (to == address(0)) to = address(0xBEEF);
        // Swallow sold-out reverts so the run continues exploring other actions.
        try this.doMint(to) {} catch {}
    }

    function doMint(address to) external {
        vm.prank(organizer);
        ticket.mint(to, "GA");
    }

    function checkIn(uint256 id) external {
        uint256 minted = ticket.totalMinted();
        if (minted == 0) return;
        id = (id % minted) + 1; // map into a valid token id range
        if (ticket.isCheckedIn(id)) return;
        ticket.checkIn(id);
        _checkedIn.push(id);
    }

    function checkedInIds() external view returns (uint256[] memory) {
        return _checkedIn;
    }
}
