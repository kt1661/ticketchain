// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {EventFactory} from "../src/EventFactory.sol";
import {Marketplace} from "../src/Marketplace.sol";
import {IEventTicket} from "../src/interfaces/IEventTicket.sol";

/// @notice Deploys the factory and marketplace, then creates one demo event.
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
    function run() external {
        vm.startBroadcast();

        EventFactory factory = new EventFactory();
        Marketplace market = new Marketplace(address(factory));

        IEventTicket.EventInfo memory info = IEventTicket.EventInfo({
            name: "TicketChain Demo Night",
            eventDate: block.timestamp + 14 days,
            venue: "NYU Tandon",
            faceValue: 0.01 ether,
            maxSupply: 200
        });
        address demoEvent = factory.createEvent(info);

        vm.stopBroadcast();

        console2.log("EventFactory:", address(factory));
        console2.log("Marketplace: ", address(market));
        console2.log("Demo Event:  ", demoEvent);
    }
}
