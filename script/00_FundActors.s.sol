// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";

/// @notice Setup/plumbing, not a feature demo: sends a small amount of Sepolia
///         ETH from the deployer wallet to the throwaway Alice/Bob demo wallets
///         so they can pay gas for their own transactions later (list, buy,
///         signing needs no gas, but submitting it as a verifier does).
///
/// Usage (Sepolia):
///   forge script script/00_FundActors.s.sol --rpc-url sepolia --broadcast \
///       --private-key $PRIVATE_KEY
contract FundActors is Script {
    uint256 constant FUNDING_AMOUNT = 0.005 ether;

    function run() external {
        address alice = vm.envAddress("ALICE_ADDRESS");
        address bob = vm.envAddress("BOB_ADDRESS");

        vm.startBroadcast();

        (bool okAlice,) = alice.call{value: FUNDING_AMOUNT}("");
        require(okAlice, "funding Alice failed");

        (bool okBob,) = bob.call{value: FUNDING_AMOUNT}("");
        require(okBob, "funding Bob failed");

        vm.stopBroadcast();

        console2.log("Funded Alice:", alice);
        console2.log("Funded Bob:  ", bob);
    }
}
