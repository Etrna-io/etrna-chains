// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";

import {EtrnaIntentRouter} from "../src/intents/EtrnaIntentRouter.sol";

/// @title DeployIntents — EtrnaIntentRouter
/// @notice Deploys the Intent Router wired to MeshHub and IdentityGuard.
///
/// Environment variables required:
///   ADMIN      — ecosystem admin address
///   MESH_HUB   — deployed MeshHub address
///
/// Optional:
///   IDENTITY_GUARD — deployed IdentityGuard address (defaults to address(0))
///
/// Usage:
///   forge script script/DeployIntents.s.sol --rpc-url $RPC --broadcast --verify
contract DeployIntents is Script {
    function run() external {
        address admin = vm.envAddress("ADMIN");
        address meshHub = vm.envAddress("MESH_HUB");
        address identityGuard = vm.envOr("IDENTITY_GUARD", address(0));

        vm.startBroadcast();

        // Deploy EtrnaIntentRouter (Ownable, deployer becomes owner)
        EtrnaIntentRouter router = new EtrnaIntentRouter(meshHub, identityGuard);

        // Transfer ownership to admin
        router.transferOwnership(admin);

        vm.stopBroadcast();

        console2.log("=== INTENTS DEPLOYMENT ===");
        console2.log("EtrnaIntentRouter:", address(router));
        console2.log("MeshHub:", meshHub);
        console2.log("IdentityGuard:", identityGuard);
        console2.log("Owner:", admin);
    }
}
