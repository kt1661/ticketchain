// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {EventTicket} from "../src/EventTicket.sol";

/// @notice Feature: manual gate check-in, restricted to the organizer/verifiers,
///         plus its guards. Three narrated entrypoints -- forge script batches
///         all broadcast transactions in one run and stops sending the rest of
///         the queue the moment one reverts, so a call we *expect* to revert
///         must always be the last (and only) broadcast transaction of its
///         invocation.
///
/// Run in this exact order (Sepolia):
///   forge script script/03_ManualCheckIn.s.sol --sig "runDeniedSelfCheckIn()" \
///       --rpc-url sepolia --broadcast --skip-simulation
///   forge script script/03_ManualCheckIn.s.sol --sig "runCheckIn()" \
///       --rpc-url sepolia --broadcast --private-key $PRIVATE_KEY
///   forge script script/03_ManualCheckIn.s.sol --sig "runDeniedReplay()" \
///       --rpc-url sepolia --broadcast --private-key $PRIVATE_KEY --skip-simulation
///
/// runDeniedReplay() must run after runCheckIn() -- it proves check-in is
/// one-way by attempting a second check-in on an already-used ticket.
///
/// --skip-simulation is required for the DENIED entrypoints: they
/// intentionally send a call that reverts, and we want that failure mined
/// on-chain and visible in the block explorer, not silently caught locally.
contract ManualCheckIn is Script {
    function _statePath() internal view returns (string memory) {
        return vm.envOr("STATE_FILE", string("deployments/sepolia.json"));
    }

    /// @dev Explicit gas ceiling for calls we expect to revert -- forge can't
    ///      use eth_estimateGas for these (it also reverts), so we supply the
    ///      limit ourselves. Comfortably more than a `require`/custom-error
    ///      revert ever consumes.
    uint256 constant DENIED_CALL_GAS = 200_000;

    /// @notice DENIED: Bob is neither the organizer nor a granted verifier.
    function runDeniedSelfCheckIn() external {
        (address eventContract, uint256 tokenId) = _load();
        uint256 bobPk = vm.envUint("BOB_PRIVATE_KEY");

        vm.startBroadcast(bobPk);
        (bool ok,) =
            eventContract.call{gas: DENIED_CALL_GAS}(abi.encodeWithSignature("checkIn(uint256)", tokenId));
        vm.stopBroadcast();

        console2.log("DENIED CASE: Bob checks himself in -- succeeded?", ok);
    }

    /// @notice Legitimate: organizer checks Bob's ticket in.
    function runCheckIn() external {
        (address eventContract, uint256 tokenId) = _load();
        EventTicket ticket = EventTicket(eventContract);

        vm.startBroadcast();
        ticket.checkIn(tokenId);
        vm.stopBroadcast();

        console2.log("Checked in tokenId", tokenId, "->", ticket.isCheckedIn(tokenId));
    }

    /// @notice DENIED: check-in is one-way -- a second attempt must fail too.
    function runDeniedReplay() external {
        (address eventContract, uint256 tokenId) = _load();

        vm.startBroadcast();
        (bool ok,) =
            eventContract.call{gas: DENIED_CALL_GAS}(abi.encodeWithSignature("checkIn(uint256)", tokenId));
        vm.stopBroadcast();

        console2.log("DENIED CASE: check-in replay on same ticket -- succeeded?", ok);
    }

    function _load() internal returns (address eventContract, uint256 tokenId) {
        string memory json = vm.readFile(_statePath());
        eventContract = vm.parseJsonAddress(json, ".eventTicket");
        tokenId = vm.parseJsonUint(json, ".bobTokenId");
    }
}
