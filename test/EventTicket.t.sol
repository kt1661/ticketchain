// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {EventFactory} from "../src/EventFactory.sol";
import {EventTicket} from "../src/EventTicket.sol";
import {IEventTicket} from "../src/interfaces/IEventTicket.sol";

/// @notice OWNER: Dev 3 (Security & testing) + Dev 1.
/// Unit tests for core minting, check-in, and the factory registry.
contract EventTicketTest is Test {
    EventFactory factory;
    EventTicket ticket;

    address organizer = makeAddr("organizer");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    function setUp() public {
        factory = new EventFactory();

        IEventTicket.EventInfo memory info = IEventTicket.EventInfo({
            name: "Demo Concert",
            eventDate: block.timestamp + 30 days,
            venue: "NYU Arena",
            faceValue: 0.05 ether,
            maxSupply: 100
        });

        vm.prank(organizer);
        address addr = factory.createEvent(info);
        ticket = EventTicket(addr);
    }

    function test_FactoryRegistersEvent() public view {
        assertTrue(factory.isLegitimate(address(ticket)));
        assertEq(factory.allEvents().length, 1);
    }

    function test_FactoryRejectsUnknownContract() public {
        assertFalse(factory.isLegitimate(address(0xdead)));
    }

    function test_OrganizerIsOwner() public view {
        assertEq(ticket.owner(), organizer);
    }

    function test_MintAssignsOwnership() public {
        vm.prank(organizer);
        uint256 id = ticket.mint(alice, "A-12");

        assertEq(ticket.ownerOf(id), alice);
        assertEq(ticket.seatOf(id), "A-12");
        assertEq(ticket.totalMinted(), 1);
    }

    function test_NonOrganizerCannotMint() public {
        vm.prank(alice);
        vm.expectRevert(); // Ownable: caller is not the owner
        ticket.mint(alice, "A-12");
    }

    function test_CannotMintBeyondSupply() public {
        IEventTicket.EventInfo memory info = IEventTicket.EventInfo({
            name: "Tiny", eventDate: block.timestamp + 1 days, venue: "X",
            faceValue: 1 ether, maxSupply: 1
        });
        vm.prank(organizer);
        EventTicket tiny = EventTicket(factory.createEvent(info));

        vm.startPrank(organizer);
        tiny.mint(alice, "GA");
        vm.expectRevert("EventTicket: sold out");
        tiny.mint(bob, "GA");
        vm.stopPrank();
    }

    function test_CheckInIsOneWay() public {
        vm.prank(organizer);
        uint256 id = ticket.mint(alice, "A-12");

        ticket.checkIn(id);
        assertTrue(ticket.isCheckedIn(id));

        vm.expectRevert("EventTicket: already checked in");
        ticket.checkIn(id);
    }

    function test_CannotCheckInNonexistent() public {
        vm.expectRevert("EventTicket: nonexistent");
        ticket.checkIn(999);
    }
}
