// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";

import {RandomnessRouter} from "../src/randomness/RandomnessRouter.sol";

/// @title DeployRandomness — RandomnessRouter
/// @notice Deploys the randomness router with fulfiller role wiring.
///
/// Environment variables required:
///   ADMIN — ecosystem admin address
///
/// Optional:
///   RANDOMNESS_FULFILLER — initial fulfiller address (defaults to ADMIN)
///
/// Usage:
///   forge script script/DeployRandomness.s.sol --rpc-url $RPC --broadcast --verify
contract DeployRandomness is Script {
    function run() external {
        address admin = vm.envAddress("ADMIN");
        address fulfiller = vm.envOr("RANDOMNESS_FULFILLER", admin);

        vm.startBroadcast();

        // Deploy RandomnessRouter (Ownable — deployer becomes owner)
        RandomnessRouter router = new RandomnessRouter();

        // Wire fulfiller role
        router.setFulfiller(fulfiller, true);

        // Transfer ownership to admin
        router.transferOwnership(admin);

        vm.stopBroadcast();

        console2.log("=== RANDOMNESS DEPLOYMENT ===");
        console2.log("RandomnessRouter:", address(router));
        console2.log("Fulfiller:", fulfiller);
        console2.log("Owner:", admin);
    }
}
