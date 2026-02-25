// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";

import {NftBridgeRouter} from "../src/bridge/NftBridgeRouter.sol";

/// @title DeployBridge — NftBridgeRouter
/// @notice Deploys the NFT bridge router with optional initial adapter and allowlist config.
///
/// Environment variables required:
///   ADMIN — ecosystem admin address
///
/// Optional:
///   BRIDGE_ADAPTER       — initial bridge adapter address (defaults to address(0), skips setAdapter)
///   BRIDGE_DST_CHAIN_ID  — destination chain ID for the initial adapter (defaults to 0)
///   BRIDGE_ALLOWLIST_NFT — initial NFT address to allowlist (defaults to address(0), skips)
///   BRIDGE_ALLOWLIST_MODE — enable allowlist mode (defaults to false)
///
/// Usage:
///   forge script script/DeployBridge.s.sol --rpc-url $RPC --broadcast --verify
contract DeployBridge is Script {
    function run() external {
        address admin = vm.envAddress("ADMIN");
        address bridgeAdapter = vm.envOr("BRIDGE_ADAPTER", address(0));
        uint256 dstChainId = vm.envOr("BRIDGE_DST_CHAIN_ID", uint256(0));
        address allowlistNft = vm.envOr("BRIDGE_ALLOWLIST_NFT", address(0));
        bool allowlistMode = vm.envOr("BRIDGE_ALLOWLIST_MODE", false);

        vm.startBroadcast();

        // Deploy NftBridgeRouter (Ownable — deployer becomes owner)
        NftBridgeRouter router = new NftBridgeRouter();

        // Set initial adapter if provided
        if (bridgeAdapter != address(0) && dstChainId != 0) {
            router.setAdapter(dstChainId, bridgeAdapter);
        }

        // Set allowlist mode and initial allowed NFT
        if (allowlistMode) {
            router.setAllowlistMode(true);
        }
        if (allowlistNft != address(0)) {
            router.setNftAllowed(allowlistNft, true);
        }

        // Transfer ownership to admin
        router.transferOwnership(admin);

        vm.stopBroadcast();

        console2.log("=== BRIDGE DEPLOYMENT ===");
        console2.log("NftBridgeRouter:", address(router));
        console2.log("AllowlistMode:", allowlistMode);
        console2.log("Owner:", admin);
    }
}
