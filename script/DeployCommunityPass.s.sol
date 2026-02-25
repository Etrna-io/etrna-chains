// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/CommunityPass.sol";
import "../src/CommunityTaskRegistry.sol";
import "../src/CommunityEconomyRouter.sol";

/**
 * @title DeployCommunityPass
 * @notice Deploys the full Community Pass suite to a chain.
 * @dev Usage:
 *   forge script script/DeployCommunityPass.s.sol:DeployCommunityPass \
 *     --rpc-url http://localhost:8545 \
 *     --broadcast \
 *     --private-key $DEPLOYER_KEY
 */
contract DeployCommunityPass is Script {
    function run() external {
        address deployer = msg.sender;

        vm.startBroadcast();

        // 1. Deploy CommunityPass (soulbound ERC-721)
        CommunityPass pass = new CommunityPass(
            "ETRNA Community Pass",
            "ECP",
            "https://api.etrna.io/pass/",
            deployer
        );
        console.log("CommunityPass deployed at:", address(pass));

        // 2. Deploy CommunityTaskRegistry (with pass address for residency gate)
        CommunityTaskRegistry tasks = new CommunityTaskRegistry(
            deployer,
            address(pass)
        );
        console.log("CommunityTaskRegistry deployed at:", address(tasks));

        // 3. Deploy CommunityEconomyRouter
        // NOTE: In production, replace address(0x1) with the actual RewardDistributor contract
        // For local dev, we use a placeholder.
        address rewardDistributor = vm.envOr("REWARD_DISTRIBUTOR", address(0x1));
        CommunityEconomyRouter router = new CommunityEconomyRouter(
            deployer,
            rewardDistributor
        );
        console.log("CommunityEconomyRouter deployed at:", address(router));

        vm.stopBroadcast();

        // Summary
        console.log("=== ETRNA Community Pass Suite Deployed ===");
        console.log("  Pass:    ", address(pass));
        console.log("  Tasks:   ", address(tasks));
        console.log("  Router:  ", address(router));
        console.log("  Admin:   ", deployer);
    }
}
