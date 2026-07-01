// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {EventFactory} from "../src/EventFactory.sol";
import {EventTicket} from "../src/EventTicket.sol";
import {IEventTicket} from "../src/interfaces/IEventTicket.sol";

/// @notice Unit tests for core minting, check-in, and the factory registry.
contract EventTicketTest is Test {
    EventFactory factory;
    EventTicket ticket;

    address organizer = makeAddr("organizer");
    address alice;
    uint256 alicePk;
    address bob = makeAddr("bob");

    function setUp() public {
        (alice, alicePk) = makeAddrAndKey("alice");
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

        vm.prank(organizer);
        ticket.checkIn(id);
        assertTrue(ticket.isCheckedIn(id));

        vm.prank(organizer);
        vm.expectRevert("EventTicket: already checked in");
        ticket.checkIn(id);
    }

    function test_CannotCheckInNonexistent() public {
        vm.expectRevert("EventTicket: nonexistent");
        ticket.checkIn(999);
    }

    function test_UnauthorizedCannotCheckIn() public {
        vm.prank(organizer);
        uint256 id = ticket.mint(alice, "A-12");

        vm.prank(bob);
        vm.expectRevert("EventTicket: not authorized");
        ticket.checkIn(id);
    }

    function test_AuthorizedVerifierCanCheckIn() public {
        vm.prank(organizer);
        uint256 id = ticket.mint(alice, "A-12");

        vm.prank(organizer);
        ticket.setVerifier(bob, true);
        assertTrue(ticket.isVerifier(bob));

        vm.prank(bob);
        ticket.checkIn(id);
        assertTrue(ticket.isCheckedIn(id));
    }

    function test_OnlyOrganizerCanSetVerifier() public {
        vm.prank(alice);
        vm.expectRevert(); // Ownable: caller is not the owner
        ticket.setVerifier(bob, true);
    }

    function test_RevokedVerifierCannotCheckIn() public {
        vm.prank(organizer);
        uint256 id = ticket.mint(alice, "A-12");

        vm.startPrank(organizer);
        ticket.setVerifier(bob, true);
        ticket.setVerifier(bob, false);
        vm.stopPrank();

        vm.prank(bob);
        vm.expectRevert("EventTicket: not authorized");
        ticket.checkIn(id);
    }

    /// @notice The holder signs the EIP-712 CheckIn digest with their own wallet;
    ///         an authorized verifier submits it and the ticket gets checked in.
    function test_CheckInWithValidSignatureSucceeds() public {
        vm.prank(organizer);
        uint256 id = ticket.mint(alice, "A-12");

        uint256 deadline = block.timestamp + 15 minutes;
        bytes memory sig = _signCheckIn(alicePk, id, deadline);

        vm.prank(organizer);
        ticket.checkInWithSignature(id, deadline, sig);

        assertTrue(ticket.isCheckedIn(id));
    }

    /// @notice A signature from anyone other than the current owner must be rejected,
    ///         even if the caller is an authorized verifier.
    function test_CheckInWithWrongSignerReverts() public {
        vm.prank(organizer);
        uint256 id = ticket.mint(alice, "A-12");

        uint256 deadline = block.timestamp + 15 minutes;
        (, uint256 impostorPk) = makeAddrAndKey("impostor");
        bytes memory sig = _signCheckIn(impostorPk, id, deadline);

        vm.prank(organizer);
        vm.expectRevert("EventTicket: invalid holder signature");
        ticket.checkInWithSignature(id, deadline, sig);
    }

    /// @notice A signature past its deadline can't be used, even if it's otherwise valid.
    function test_CheckInSignatureExpiredReverts() public {
        vm.prank(organizer);
        uint256 id = ticket.mint(alice, "A-12");

        uint256 deadline = block.timestamp + 15 minutes;
        bytes memory sig = _signCheckIn(alicePk, id, deadline);

        vm.warp(deadline + 1);

        vm.prank(organizer);
        vm.expectRevert("EventTicket: signature expired");
        ticket.checkInWithSignature(id, deadline, sig);
    }

    /// @notice A valid holder signature alone isn't enough — the caller submitting
    ///         it must still be the organizer or an authorized verifier.
    function test_CheckInWithSignatureRequiresAuthorizedCaller() public {
        vm.prank(organizer);
        uint256 id = ticket.mint(alice, "A-12");

        uint256 deadline = block.timestamp + 15 minutes;
        bytes memory sig = _signCheckIn(alicePk, id, deadline);

        vm.prank(bob); // bob is neither organizer nor a granted verifier
        vm.expectRevert("EventTicket: not authorized");
        ticket.checkInWithSignature(id, deadline, sig);
    }

    /// @notice checkInWithSignature is one-way too — a second attempt, even with a
    ///         fresh valid signature, must fail because the ticket is already used.
    function test_CheckInWithSignatureAlreadyCheckedInReverts() public {
        vm.prank(organizer);
        uint256 id = ticket.mint(alice, "A-12");

        uint256 deadline = block.timestamp + 15 minutes;
        bytes memory sig = _signCheckIn(alicePk, id, deadline);

        vm.prank(organizer);
        ticket.checkInWithSignature(id, deadline, sig);

        bytes memory sig2 = _signCheckIn(alicePk, id, deadline);
        vm.prank(organizer);
        vm.expectRevert("EventTicket: already checked in");
        ticket.checkInWithSignature(id, deadline, sig2);
    }

    /// @notice A signature scoped to one tokenId cannot be replayed against another —
    ///         the EIP-712 digest binds tokenId, deadline, and this contract's address.
    function test_CheckInSignatureBoundToTokenId() public {
        vm.startPrank(organizer);
        uint256 id1 = ticket.mint(alice, "A-12");
        uint256 id2 = ticket.mint(alice, "A-13");
        vm.stopPrank();

        uint256 deadline = block.timestamp + 15 minutes;
        bytes memory sigForId1 = _signCheckIn(alicePk, id1, deadline);

        vm.prank(organizer);
        vm.expectRevert("EventTicket: invalid holder signature");
        ticket.checkInWithSignature(id2, deadline, sigForId1);
    }

    function _signCheckIn(uint256 signerPk, uint256 tokenId, uint256 deadline)
        internal
        view
        returns (bytes memory)
    {
        bytes32 digest = ticket.checkInDigest(tokenId, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
        return abi.encodePacked(r, s, v);
    }
}
