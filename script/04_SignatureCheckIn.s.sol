// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {EventTicket} from "../src/EventTicket.sol";

/// @notice Feature: cryptographic holder-presence check via EIP-712 signature,
///         plus its two guards. Three narrated entrypoints -- forge script
///         batches all broadcast transactions in one run and stops sending
///         the rest of the queue the moment one reverts, so a call we
///         *expect* to revert must always be the last (and only) broadcast
///         transaction of its invocation.
///
/// Run in this exact order (Sepolia):
///   forge script script/04_SignatureCheckIn.s.sol --sig "runDeniedWrongSigner()" \
///       --rpc-url sepolia --broadcast --private-key $PRIVATE_KEY --skip-simulation
///   forge script script/04_SignatureCheckIn.s.sol --sig "runCheckIn()" \
///       --rpc-url sepolia --broadcast --private-key $PRIVATE_KEY
///   forge script script/04_SignatureCheckIn.s.sol --sig "runDeniedExpiredSignature()" \
///       --rpc-url sepolia --broadcast --private-key $PRIVATE_KEY --skip-simulation
///
/// runDeniedWrongSigner() must run BEFORE runCheckIn(): inside
/// checkInWithSignature, the "already checked in" guard is checked before the
/// signature-recovery check, so once the ticket is legitimately checked in,
/// this call would revert with the wrong reason. runDeniedExpiredSignature()
/// is safe to run after runCheckIn() because its guard (deadline) is checked
/// before the "already checked in" guard.
///
/// --skip-simulation is required for the DENIED entrypoints: they
/// intentionally send a call that reverts, and we want that failure mined
/// on-chain and visible in the block explorer, not silently caught locally.
contract SignatureCheckIn is Script {
    function _statePath() internal view returns (string memory) {
        return vm.envOr("STATE_FILE", string("deployments/sepolia.json"));
    }

    /// @dev Explicit gas ceiling for calls we expect to revert -- forge can't
    ///      use eth_estimateGas for these (it also reverts), so we supply the
    ///      limit ourselves. Comfortably more than a `require`/custom-error
    ///      revert ever consumes.
    uint256 constant DENIED_CALL_GAS = 200_000;

    /// @notice DENIED: Alice signs, but she sold this ticket -- she's no longer ownerOf().
    function runDeniedWrongSigner() external {
        (address eventContract, uint256 tokenId) = _load();
        uint256 alicePk = vm.envUint("ALICE_PRIVATE_KEY");

        console2.log("Current owner of tokenId", tokenId, "->", EventTicket(eventContract).ownerOf(tokenId));

        uint256 deadline = block.timestamp + 15 minutes;
        bytes32 digest = EventTicket(eventContract).checkInDigest(tokenId, deadline);
        bool ok = _attemptCheckIn(eventContract, tokenId, deadline, _sign(alicePk, digest));

        console2.log("DENIED CASE: signature from former owner (Alice) -- succeeded?", ok);
    }

    /// @notice Legitimate: Bob (current owner) signs with a valid deadline.
    function runCheckIn() external {
        (address eventContract, uint256 tokenId) = _load();
        uint256 bobPk = vm.envUint("BOB_PRIVATE_KEY");

        uint256 deadline = block.timestamp + 15 minutes;
        bytes32 digest = EventTicket(eventContract).checkInDigest(tokenId, deadline);
        bytes memory signature = _sign(bobPk, digest);

        vm.startBroadcast();
        EventTicket(eventContract).checkInWithSignature(tokenId, deadline, signature);
        vm.stopBroadcast();

        console2.log("Checked in tokenId", tokenId, "->", EventTicket(eventContract).isCheckedIn(tokenId));
    }

    /// @notice DENIED: Bob signs correctly, but the deadline has already passed.
    function runDeniedExpiredSignature() external {
        (address eventContract, uint256 tokenId) = _load();
        uint256 bobPk = vm.envUint("BOB_PRIVATE_KEY");

        uint256 deadline = block.timestamp - 1;
        bytes32 digest = EventTicket(eventContract).checkInDigest(tokenId, deadline);
        bool ok = _attemptCheckIn(eventContract, tokenId, deadline, _sign(bobPk, digest));

        console2.log("DENIED CASE: expired signature -- succeeded?", ok);
    }

    function _load() internal returns (address eventContract, uint256 tokenId) {
        string memory json = vm.readFile(_statePath());
        eventContract = vm.parseJsonAddress(json, ".eventTicket");
        tokenId = vm.parseJsonUint(json, ".aliceTokenId"); // now owned by Bob
    }

    function _sign(uint256 pk, bytes32 digest) internal returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        return abi.encodePacked(r, s, v);
    }

    function _attemptCheckIn(address eventContract, uint256 tokenId, uint256 deadline, bytes memory signature)
        internal
        returns (bool ok)
    {
        vm.startBroadcast();
        (ok,) = eventContract.call{gas: DENIED_CALL_GAS}(
            abi.encodeWithSignature("checkInWithSignature(uint256,uint256,bytes)", tokenId, deadline, signature)
        );
        vm.stopBroadcast();
    }
}
