// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {EventTicket} from "../src/EventTicket.sol";

/// @notice Feature: off-chain metadata integrity hash + legitimate updates,
///         plus the access-control guard on setMetadata(). Two entrypoints --
///         forge script batches all broadcast transactions in one run and
///         stops sending the rest of the queue the moment one reverts, so the
///         call we *expect* to revert must always be the last (and only)
///         broadcast transaction of its invocation.
///
/// Run in this order (Sepolia):
///   forge script script/05_MetadataUpdate.s.sol --sig "runSetMetadata()" \
///       --rpc-url sepolia --broadcast --private-key $PRIVATE_KEY
///
///   forge script script/05_MetadataUpdate.s.sol --sig "runDeniedSetMetadata()" \
///       --rpc-url sepolia --broadcast --skip-simulation
///
/// --skip-simulation is required for runDeniedSetMetadata(): it intentionally
/// sends a call that reverts, and we want that failure mined on-chain and
/// visible in the block explorer, not silently caught locally.
contract MetadataUpdate is Script {
    string constant STATE_PATH = "deployments/sepolia.json";

    /// @dev Explicit gas ceiling for calls we expect to revert -- forge can't
    ///      use eth_estimateGas for these (it also reverts), so we supply the
    ///      limit ourselves. Comfortably more than a `require`/custom-error
    ///      revert ever consumes.
    uint256 constant DENIED_CALL_GAS = 200_000;

    /// @notice Legitimate: organizer commits to the artifact, then updates it
    ///         (simulating a venue change). Both calls emit MetadataUpdated,
    ///         so the full history is auditable, not just the latest value.
    function runSetMetadata() external {
        address eventContract = vm.parseJsonAddress(vm.readFile(STATE_PATH), ".eventTicket");
        EventTicket ticket = EventTicket(eventContract);

        string memory v1Uri = "metadata/demo-concert.json";
        bytes32 v1Hash = keccak256(bytes(vm.readFile(v1Uri)));
        string memory v2Uri = "metadata/demo-concert-v2.json";
        bytes32 v2Hash = keccak256(bytes(vm.readFile(v2Uri)));

        vm.startBroadcast();
        ticket.setMetadata(v1Uri, v1Hash);
        ticket.setMetadata(v2Uri, v2Hash);
        vm.stopBroadcast();

        console2.log("Final metadataURI: ", ticket.metadataURI());
        console2.log("Final metadataHash:");
        console2.logBytes32(ticket.metadataHash());
    }

    /// @notice DENIED: Bob is not the organizer.
    function runDeniedSetMetadata() external {
        address eventContract = vm.parseJsonAddress(vm.readFile(STATE_PATH), ".eventTicket");
        uint256 bobPk = vm.envUint("BOB_PRIVATE_KEY");
        string memory v1Uri = "metadata/demo-concert.json";
        bytes32 v1Hash = keccak256(bytes(vm.readFile(v1Uri)));

        vm.startBroadcast(bobPk);
        (bool ok,) = eventContract.call{gas: DENIED_CALL_GAS}(
            abi.encodeWithSignature("setMetadata(string,bytes32)", v1Uri, v1Hash)
        );
        vm.stopBroadcast();

        console2.log("DENIED CASE: Bob (non-organizer) sets metadata -- succeeded?", ok);
    }
}
