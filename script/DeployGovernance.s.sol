// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {GovernanceHybrid} from "../src/governance/GovernanceHybrid.sol";

contract DeployGovernance is Script {
    function run() external {
        address etrToken = vm.envAddress("ETR_TOKEN");
        // Optional: reputation oracle. Defaults to address(0) (disabled until deployed).
        address repOracle = vm.envOr("REP_ORACLE", address(0));

        vm.startBroadcast();

        GovernanceHybrid gov = new GovernanceHybrid(etrToken, repOracle);

        console2.log("GovernanceHybrid deployed:", address(gov));
        console2.log("  etr:", etrToken);
        console2.log("  repOracle:", repOracle);
        console2.log("  owner:", gov.owner());

        vm.stopBroadcast();
    }
}
