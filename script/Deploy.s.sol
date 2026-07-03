// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {EventFactory} from "../src/EventFactory.sol";
import {Marketplace} from "../src/Marketplace.sol";

/// @notice Deploys the shared platform contracts: EventFactory and Marketplace.
///         Does not create an event or mint tickets — that's script 01, so each
///         script in the demo sequence demonstrates one feature at a time.
///
/// Writes the deployed addresses to deployments/sepolia.json so later scripts
/// (00-05) can pick them up without manual copy-pasting.
///
/// Usage (local):
///   anvil    # in another terminal
///   forge script script/Deploy.s.sol --rpc-url http://localhost:8545 --broadcast \
///       --private-key $PRIVATE_KEY
///
/// Usage (Sepolia):
///   forge script script/Deploy.s.sol --rpc-url sepolia --broadcast \
///       --private-key $PRIVATE_KEY --verify
contract Deploy is Script {
    string constant STATE_PATH = "deployments/sepolia.json";

    function run() external {
        vm.startBroadcast();

        EventFactory factory = new EventFactory();
        Marketplace market = new Marketplace(address(factory));

        vm.stopBroadcast();

        vm.writeJson(string.concat('"', vm.toString(address(factory)), '"'), STATE_PATH, ".factory");
        vm.writeJson(string.concat('"', vm.toString(address(market)), '"'), STATE_PATH, ".marketplace");

        console2.log("EventFactory:", address(factory));
        console2.log("Marketplace: ", address(market));
    }
}
