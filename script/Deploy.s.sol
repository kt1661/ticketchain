// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {EventFactory} from "../src/EventFactory.sol";
import {Marketplace} from "../src/Marketplace.sol";

/// @notice Deploys the shared platform contracts: EventFactory and Marketplace.
///         Does not create an event or mint tickets — that's script 01, so each
///         script in the demo sequence demonstrates one feature at a time.
///
/// Writes the deployed addresses to the state file so later scripts (00-05)
/// can pick them up without manual copy-pasting. The state file is
/// deployments/sepolia.json by default, or whatever STATE_FILE is set to in
/// .env -- .env.sepolia and .env.anvil each point at their own file so the
/// two networks' deployment records never clobber each other.
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
    function _statePath() internal view returns (string memory) {
        return vm.envOr("STATE_FILE", string("deployments/sepolia.json"));
    }

    function run() external {
        vm.startBroadcast();

        EventFactory factory = new EventFactory();
        Marketplace market = new Marketplace(address(factory));

        vm.stopBroadcast();

        string memory statePath = _statePath();
        vm.writeJson(string.concat('"', vm.toString(address(factory)), '"'), statePath, ".factory");
        vm.writeJson(string.concat('"', vm.toString(address(market)), '"'), statePath, ".marketplace");

        console2.log("EventFactory:", address(factory));
        console2.log("Marketplace: ", address(market));
    }
}
