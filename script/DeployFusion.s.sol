// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";

import {FusionRegistry} from "../src/fusion/FusionRegistry.sol";

/// @title DeployFusion — FusionRegistry
/// @notice Deploys the Fusion Lab challenge/submission registry with role setup.
///
/// Environment variables required:
///   ADMIN — ecosystem admin address
///
/// Optional:
///   FUSION_RELAYER   — initial relayer address (defaults to ADMIN)
///   FUSION_VALIDATOR — initial validator address (defaults to ADMIN)
///
/// Usage:
///   forge script script/DeployFusion.s.sol --rpc-url $RPC --broadcast --verify
contract DeployFusion is Script {
    function run() external {
        address admin = vm.envAddress("ADMIN");
        address relayer = vm.envOr("FUSION_RELAYER", admin);
        address validator = vm.envOr("FUSION_VALIDATOR", admin);

        vm.startBroadcast();

        // Deploy FusionRegistry — admin gets DEFAULT_ADMIN_ROLE + ADMIN_ROLE
        FusionRegistry fusion = new FusionRegistry(admin);

        // Grant relayer and validator roles
        fusion.grantRelayer(relayer);
        fusion.grantValidator(validator);

        vm.stopBroadcast();

        console2.log("=== FUSION DEPLOYMENT ===");
        console2.log("FusionRegistry:", address(fusion));
        console2.log("Admin:", admin);
        console2.log("Relayer:", relayer);
        console2.log("Validator:", validator);
    }
}
