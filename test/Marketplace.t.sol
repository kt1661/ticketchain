// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {EventFactory} from "../src/EventFactory.sol";
import {EventTicket} from "../src/EventTicket.sol";
import {Marketplace} from "../src/Marketplace.sol";
import {IEventTicket} from "../src/interfaces/IEventTicket.sol";
import {IMarketplace} from "../src/interfaces/IMarketplace.sol";

/// @notice Unit + fuzz tests for resale rules, plus a reentrancy attack harness.
contract MarketplaceTest is Test {
    EventFactory factory;
    EventTicket ticket;
    Marketplace market;

    address organizer = makeAddr("organizer");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    uint256 constant FACE = 0.05 ether;

    function setUp() public {
        factory = new EventFactory();
        market = new Marketplace(address(factory));

        IEventTicket.EventInfo memory info = IEventTicket.EventInfo({
            name: "Demo Concert",
            eventDate: block.timestamp + 30 days,
            venue: "NYU Arena",
            faceValue: FACE,
            maxSupply: 100
        });

        vm.prank(organizer);
        ticket = EventTicket(factory.createEvent(info));

        // Alice owns a ticket and approves the marketplace to move it.
        vm.prank(organizer);
        ticket.mint(alice, "A-12");
        vm.prank(alice);
        ticket.approve(address(market), 1);

        vm.deal(bob, 10 ether);
    }

    function test_ListAndBuyTransfersOwnership() public {
        vm.prank(alice);
        market.list(address(ticket), 1, FACE);

        vm.prank(bob);
        market.buy{value: FACE}(address(ticket), 1);

        assertEq(ticket.ownerOf(1), bob);
        assertFalse(market.getListing(address(ticket), 1).active);
    }

    function test_RoyaltyGoesToOrganizer() public {
        uint256 before = organizer.balance;

        vm.prank(alice);
        market.list(address(ticket), 1, FACE);
        vm.prank(bob);
        market.buy{value: FACE}(address(ticket), 1);

        uint256 expectedRoyalty = (FACE * market.ROYALTY_BPS()) / 10_000;
        assertEq(organizer.balance - before, expectedRoyalty);
    }

    function test_CannotListAboveCap() public {
        uint256 overCap = market.maxResalePrice(address(ticket), 1) + 1;
        vm.prank(alice);
        vm.expectRevert("Marketplace: over cap");
        market.list(address(ticket), 1, overCap);
    }

    function test_NonOwnerCannotList() public {
        vm.prank(bob);
        vm.expectRevert("Marketplace: not owner");
        market.list(address(ticket), 1, FACE);
    }

    function test_CannotListWithoutApproval() public {
        vm.prank(organizer);
        ticket.mint(bob, "B-1");
        // bob never approved the marketplace for token 2
        vm.prank(bob);
        vm.expectRevert("Marketplace: not approved");
        market.list(address(ticket), 2, FACE);
    }

    /// @notice A ticket contract that was never registered via EventFactory (e.g. a
    ///         counterfeit look-alike) must be rejected at list time, even though it
    ///         exposes the exact same interface as a real EventTicket.
    function test_CannotListUnknownEvent() public {
        IEventTicket.EventInfo memory info = IEventTicket.EventInfo({
            name: "Rogue Event",
            eventDate: block.timestamp + 30 days,
            venue: "Nowhere",
            faceValue: FACE,
            maxSupply: 10
        });
        vm.prank(organizer);
        EventTicket rogue = new EventTicket(organizer, info); // bypasses EventFactory

        vm.prank(organizer);
        rogue.mint(alice, "R-1");
        vm.prank(alice);
        rogue.approve(address(market), 1);

        assertFalse(factory.isLegitimate(address(rogue)));

        vm.prank(alice);
        vm.expectRevert("Marketplace: unknown event");
        market.list(address(rogue), 1, FACE);
    }

    /// @notice If the seller transfers the ticket away directly (bypassing the
    ///         marketplace) after listing, the listing goes stale and buy() must
    ///         reject it with a clear reason instead of failing deep in transferFrom.
    function test_CannotBuyStaleListing() public {
        vm.prank(alice);
        market.list(address(ticket), 1, FACE);

        vm.prank(alice);
        ticket.transferFrom(alice, bob, 1);

        vm.prank(bob);
        vm.expectRevert("Marketplace: stale listing");
        market.buy{value: FACE}(address(ticket), 1);
    }

    function test_SellerCanCancelListing() public {
        vm.prank(alice);
        market.list(address(ticket), 1, FACE);

        vm.prank(alice);
        market.cancelListing(address(ticket), 1);

        assertFalse(market.getListing(address(ticket), 1).active);

        vm.prank(bob);
        vm.expectRevert("Marketplace: not listed");
        market.buy{value: FACE}(address(ticket), 1);
    }

    function test_NonSellerCannotCancelListing() public {
        vm.prank(alice);
        market.list(address(ticket), 1, FACE);

        vm.prank(bob);
        vm.expectRevert("Marketplace: not seller");
        market.cancelListing(address(ticket), 1);
    }

    function test_CannotCancelInactiveListing() public {
        vm.prank(alice);
        vm.expectRevert("Marketplace: not listed");
        market.cancelListing(address(ticket), 1);
    }

    /// @notice Fuzz the resale price. Any price within the cap should list and sell;
    ///         the buyer must always end up owning the token and the seller paid.
    function testFuzz_ResaleWithinCap(uint256 price) public {
        uint256 cap = market.maxResalePrice(address(ticket), 1);
        price = bound(price, 1, cap);

        vm.prank(alice);
        market.list(address(ticket), 1, price);

        uint256 sellerBefore = alice.balance;
        vm.prank(bob);
        market.buy{value: price}(address(ticket), 1);

        assertEq(ticket.ownerOf(1), bob);
        uint256 royalty = (price * market.ROYALTY_BPS()) / 10_000;
        assertEq(alice.balance - sellerBefore, price - royalty);
    }

    /// @notice Overpayment must be refunded so the buyer only ever pays `price`.
    function testFuzz_OverpaymentRefunded(uint256 extra) public {
        extra = bound(extra, 0, 5 ether);
        vm.prank(alice);
        market.list(address(ticket), 1, FACE);

        uint256 buyerBefore = bob.balance;
        vm.prank(bob);
        market.buy{value: FACE + extra}(address(ticket), 1);

        assertEq(buyerBefore - bob.balance, FACE);
    }

    /// @notice Reentrancy harness. Demonstrates nonReentrant protection on buy().
    /// @dev Use this to show an attack attempt is blocked. The attacker
    ///      overpays so buy()'s overpayment refund sends it ETH mid-call — that's
    ///      the callback hook it uses to attempt a reentrant buy(). If you remove
    ///      the guard / break CEI in Marketplace, this test should start failing —
    ///      that contrast is gold for the security writeup.
    function test_ReentrancyOnBuyIsBlocked() public {
        ReentrantBuyer attacker = new ReentrantBuyer(market, address(ticket));
        vm.deal(address(attacker), 10 ether);

        vm.prank(alice);
        market.list(address(ticket), 1, FACE);

        // Overpay so the refund step calls back into the attacker, which then
        // tries to re-enter buy(); nonReentrant must block the nested call.
        vm.expectRevert();
        attacker.attack{value: FACE + 1 ether}();
    }
}

/// @notice Malicious contract that tries to re-enter buy() during its receive().
contract ReentrantBuyer {
    Marketplace market;
    address eventContract;
    bool entered;

    constructor(Marketplace _market, address _eventContract) {
        market = _market;
        eventContract = _eventContract;
    }

    function attack() external payable {
        market.buy{value: msg.value}(eventContract, 1);
    }

    receive() external payable {
        if (!entered) {
            entered = true;
            // Attempt to re-enter; nonReentrant should make this revert.
            market.buy{value: msg.value}(eventContract, 1);
        }
    }
}
