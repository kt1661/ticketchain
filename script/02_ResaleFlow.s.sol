// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {EventTicket} from "../src/EventTicket.sol";
import {Marketplace} from "../src/Marketplace.sol";

/// @notice Feature: rule-bound resale, plus its three on-chain guards, split
///         into five narrated entrypoints. forge script batches all broadcast
///         transactions in one run and stops sending the rest of the queue
///         the moment one reverts, so a call we *expect* to revert must
///         always be the last (and only) broadcast transaction of its
///         invocation -- hence five small steps instead of one script.
///
/// Run in this exact order (Sepolia):
///   forge script script/02_ResaleFlow.s.sol --sig "runDeniedOverCap()" \
///       --rpc-url sepolia --broadcast --skip-simulation
///   forge script script/02_ResaleFlow.s.sol --sig "runDeniedUnknownEvent()" \
///       --rpc-url sepolia --broadcast --skip-simulation
///   forge script script/02_ResaleFlow.s.sol --sig "runListing()" \
///       --rpc-url sepolia --broadcast
///   forge script script/02_ResaleFlow.s.sol --sig "runDeniedUnderpay()" \
///       --rpc-url sepolia --broadcast --skip-simulation
///   forge script script/02_ResaleFlow.s.sol --sig "runPurchase()" \
///       --rpc-url sepolia --broadcast
///
/// The two "over cap" / "unknown event" denials must run before runListing()
/// while Alice still owns the ticket outright (ownership transfers to Bob at
/// the end of runPurchase()). runDeniedUnderpay() must run after runListing()
/// (it needs an active listing to reach the underpaid check at all) and
/// before runPurchase() (which consumes/deactivates that listing).
///
/// --skip-simulation is required for the DENIED entrypoints: they
/// intentionally send a call that reverts, and we want that failure mined
/// on-chain and visible in the block explorer, not silently caught locally.
contract ResaleFlow is Script {
    function _statePath() internal view returns (string memory) {
        return vm.envOr("STATE_FILE", string("deployments/sepolia.json"));
    }

    address constant FAKE_EVENT_CONTRACT = address(0xBEEF);

    /// @dev Explicit gas ceiling for calls we expect to revert -- forge can't
    ///      use eth_estimateGas for these (it also reverts), so we supply the
    ///      limit ourselves. Comfortably more than a `require`/custom-error
    ///      revert ever consumes.
    uint256 constant DENIED_CALL_GAS = 200_000;

    /// @notice DENIED: listing above the 110% face-value cap.
    function runDeniedOverCap() external {
        (address eventContract, address marketplaceAddr, uint256 tokenId) = _load();
        uint256 alicePk = vm.envUint("ALICE_PRIVATE_KEY");
        uint256 resalePrice = Marketplace(marketplaceAddr).maxResalePrice(eventContract, tokenId);

        vm.startBroadcast(alicePk);
        (bool ok,) = marketplaceAddr.call{gas: DENIED_CALL_GAS}(
            abi.encodeWithSignature("list(address,uint256,uint256)", eventContract, tokenId, resalePrice * 2)
        );
        vm.stopBroadcast();

        console2.log("DENIED CASE: list() above price cap -- succeeded?", ok);
    }

    /// @notice DENIED: listing a ticket "from" a contract EventFactory never deployed.
    function runDeniedUnknownEvent() external {
        (, address marketplaceAddr, uint256 tokenId) = _load();
        uint256 alicePk = vm.envUint("ALICE_PRIVATE_KEY");

        // list() reverts on the very first check (factory.isLegitimate) for a
        // fake/unregistered event contract, before it ever looks at price --
        // so any nonzero placeholder works here. We deliberately do NOT call
        // maxResalePrice(FAKE_EVENT_CONTRACT, ...): that reads eventInfo() off
        // FAKE_EVENT_CONTRACT, which has no code at all, and would revert
        // locally before this even reaches the broadcast step.
        uint256 placeholderPrice = 0.001 ether;

        vm.startBroadcast(alicePk);
        (bool ok,) = marketplaceAddr.call{gas: DENIED_CALL_GAS}(
            abi.encodeWithSignature(
                "list(address,uint256,uint256)", FAKE_EVENT_CONTRACT, tokenId, placeholderPrice
            )
        );
        vm.stopBroadcast();

        console2.log("DENIED CASE: list() unregistered event contract -- succeeded?", ok);
    }

    /// @notice Legitimate: Alice approves the marketplace and lists her ticket.
    function runListing() external {
        (address eventContract, address marketplaceAddr, uint256 tokenId) = _load();
        uint256 alicePk = vm.envUint("ALICE_PRIVATE_KEY");
        uint256 resalePrice = Marketplace(marketplaceAddr).maxResalePrice(eventContract, tokenId);

        vm.startBroadcast(alicePk);
        EventTicket(eventContract).approve(marketplaceAddr, tokenId);
        Marketplace(marketplaceAddr).list(eventContract, tokenId, resalePrice);
        vm.stopBroadcast();

        console2.log("Alice listed tokenId", tokenId, "for", resalePrice);
    }

    /// @notice DENIED: buying while underpaying the listed price.
    function runDeniedUnderpay() external {
        (address eventContract, address marketplaceAddr, uint256 tokenId) = _load();
        uint256 bobPk = vm.envUint("BOB_PRIVATE_KEY");
        uint256 resalePrice = Marketplace(marketplaceAddr).maxResalePrice(eventContract, tokenId);

        vm.startBroadcast(bobPk);
        (bool ok,) = marketplaceAddr.call{value: resalePrice - 1, gas: DENIED_CALL_GAS}(
            abi.encodeWithSignature("buy(address,uint256)", eventContract, tokenId)
        );
        vm.stopBroadcast();

        console2.log("DENIED CASE: buy() while underpaying -- succeeded?", ok);
    }

    /// @notice Legitimate: Bob buys the listed ticket.
    function runPurchase() external {
        (address eventContract, address marketplaceAddr, uint256 tokenId) = _load();
        uint256 bobPk = vm.envUint("BOB_PRIVATE_KEY");
        uint256 resalePrice = Marketplace(marketplaceAddr).maxResalePrice(eventContract, tokenId);

        vm.startBroadcast(bobPk);
        Marketplace(marketplaceAddr).buy{value: resalePrice}(eventContract, tokenId);
        vm.stopBroadcast();

        console2.log("Bob now owns tokenId", tokenId, "->", EventTicket(eventContract).ownerOf(tokenId));
    }

    function _load() internal returns (address eventContract, address marketplaceAddr, uint256 tokenId) {
        string memory json = vm.readFile(_statePath());
        eventContract = vm.parseJsonAddress(json, ".eventTicket");
        marketplaceAddr = vm.parseJsonAddress(json, ".marketplace");
        tokenId = vm.parseJsonUint(json, ".aliceTokenId");
    }
}
