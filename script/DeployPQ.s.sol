// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";

import {PQKeyRegistry} from "../src/pq/PQKeyRegistry.sol";

/// @title DeployPQ — PQKeyRegistry
/// @notice Deploys the post-quantum public key registry.
///
/// Environment variables required:
///   ADMIN — ecosystem admin address
///
/// Usage:
///   forge script script/DeployPQ.s.sol --rpc-url $RPC --broadcast --verify
contract DeployPQ is Script {
    function run() external {
        address admin = vm.envAddress("ADMIN");

        vm.startBroadcast();

        // Deploy PQKeyRegistry (Ownable — deployer becomes owner)
        PQKeyRegistry pqRegistry = new PQKeyRegistry();

        // Transfer ownership to admin
        pqRegistry.transferOwnership(admin);

        vm.stopBroadcast();

        console2.log("=== PQ DEPLOYMENT ===");
        console2.log("PQKeyRegistry:", address(pqRegistry));
        console2.log("Owner:", admin);
    }
}
