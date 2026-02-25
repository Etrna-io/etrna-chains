// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {EtrnaToken} from "../src/tokens/EtrnaToken.sol";
import {VibeToken} from "../src/tokens/VibeToken.sol";

contract DeployTokens is Script {
    function run() external {
        address admin = vm.envAddress("ADMIN");

        // Parse comma-separated env vars for initial token distribution.
        // Example: ETR_RECIPIENTS=0xAAA,0xBBB  ETR_AMOUNTS=500000000000000000000000000,500000000000000000000000000
        string memory recipientsCsv = vm.envString("ETR_RECIPIENTS");
        string memory amountsCsv = vm.envString("ETR_AMOUNTS");

        // Split CSV strings into arrays using Forge cheatcodes.
        string[] memory recipientStrs = vm.split(recipientsCsv, ",");
        string[] memory amountStrs = vm.split(amountsCsv, ",");
        require(recipientStrs.length == amountStrs.length, "recipients/amounts length mismatch");

        address[] memory recipients = new address[](recipientStrs.length);
        uint256[] memory amounts = new uint256[](amountStrs.length);
        for (uint256 i = 0; i < recipientStrs.length; i++) {
            recipients[i] = vm.parseAddress(recipientStrs[i]);
            amounts[i] = vm.parseUint(amountStrs[i]);
        }

        vm.startBroadcast();
        EtrnaToken etr = new EtrnaToken("Etrna", "ETR", admin, recipients, amounts);
        VibeToken vibe = new VibeToken("Vibe", "VIBE", admin);
        vm.stopBroadcast();

        console2.log("ETR deployed:", address(etr));
        console2.log("VIBE deployed:", address(vibe));
        console2.log("Next: admin grants VIBE MINTER_ROLE to RewardsEngine via setMinter().");
    }
}
