// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/etrnanode/EtrnaNodeRegistry.sol";

contract DeployEtrnaNode is Script {
    function run() public {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerKey);

        EtrnaNodeRegistry registry = new EtrnaNodeRegistry();
        console.log("EtrnaNodeRegistry deployed at:", address(registry));

        vm.stopBroadcast();
    }
}
