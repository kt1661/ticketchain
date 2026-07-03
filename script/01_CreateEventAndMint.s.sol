// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {EventFactory} from "../src/EventFactory.sol";
import {EventTicket} from "../src/EventTicket.sol";
import {IEventTicket} from "../src/interfaces/IEventTicket.sol";

/// @notice Feature: event creation + primary minting, plus the access-control
///         guard on mint(). Two separate entrypoints -- forge script batches
///         all broadcast transactions in one run and stops sending the rest
///         of the queue the moment one reverts, so a call we *expect* to
///         revert must always be the last (and only) broadcast transaction
///         of its invocation.
///
/// Run in this order (Sepolia):
///   forge script script/01_CreateEventAndMint.s.sol --sig "runCreateAndMint()" \
///       --rpc-url sepolia --broadcast --private-key $PRIVATE_KEY
///
///   forge script script/01_CreateEventAndMint.s.sol --sig "runDeniedMint()" \
///       --rpc-url sepolia --broadcast --skip-simulation
///
/// --skip-simulation is required for runDeniedMint(): it intentionally sends
/// a call that reverts, and we want that failure mined on-chain and visible
/// in the block explorer, not silently caught locally.
contract CreateEventAndMint is Script {
    string constant STATE_PATH = "deployments/sepolia.json";

    /// @dev Explicit gas ceiling for calls we expect to revert -- forge can't
    ///      use eth_estimateGas for these (it also reverts), so we supply the
    ///      limit ourselves. Comfortably more than a `require`/custom-error
    ///      revert ever consumes.
    uint256 constant DENIED_CALL_GAS = 200_000;

    /// @notice The organizer creates the event and mints ticket #1 to Alice, #2 to Bob.
    function runCreateAndMint() external {
        address factoryAddr = vm.parseJsonAddress(vm.readFile(STATE_PATH), ".factory");
        address alice = vm.envAddress("ALICE_ADDRESS");
        address bob = vm.envAddress("BOB_ADDRESS");

        // Kept deliberately small: the resale flow needs Bob to hold enough
        // ETH to cover the listed price (up to 110% of this), and testnet
        // faucet balances are limited.
        IEventTicket.EventInfo memory info = IEventTicket.EventInfo({
            name: "TicketChain Demo Night",
            eventDate: block.timestamp + 14 days,
            venue: "NYU Tandon",
            faceValue: 0.001 ether,
            maxSupply: 200
        });

        vm.startBroadcast();
        address eventContract = EventFactory(factoryAddr).createEvent(info);
        uint256 aliceTokenId = EventTicket(eventContract).mint(alice, "A-1");
        uint256 bobTokenId = EventTicket(eventContract).mint(bob, "A-2");
        vm.stopBroadcast();

        vm.writeJson(string.concat('"', vm.toString(eventContract), '"'), STATE_PATH, ".eventTicket");
        vm.writeJson(vm.toString(aliceTokenId), STATE_PATH, ".aliceTokenId");
        vm.writeJson(vm.toString(bobTokenId), STATE_PATH, ".bobTokenId");

        console2.log("EventTicket:  ", eventContract);
        console2.log("Alice tokenId:", aliceTokenId);
        console2.log("Bob tokenId:  ", bobTokenId);
    }

    /// @notice DENIED: Bob is not the organizer, so this mint must revert on-chain.
    function runDeniedMint() external {
        address eventContract = vm.parseJsonAddress(vm.readFile(STATE_PATH), ".eventTicket");
        address bob = vm.envAddress("BOB_ADDRESS");
        uint256 bobPk = vm.envUint("BOB_PRIVATE_KEY");

        // Low-level call (not the typed interface) so Bob's revert doesn't
        // unwind this script -- it's sent as a real transaction and left to
        // fail on the network.
        vm.startBroadcast(bobPk);
        (bool deniedOk, bytes memory deniedRet) = eventContract.call{gas: DENIED_CALL_GAS}(
            abi.encodeWithSignature("mint(address,string)", bob, "DENIED")
        );
        vm.stopBroadcast();

        console2.log("DENIED CASE: Bob (non-organizer) attempts to mint -- succeeded?", deniedOk);
        if (!deniedOk) {
            console2.log("  revert data:", vm.toString(deniedRet));
        }
    }
}
