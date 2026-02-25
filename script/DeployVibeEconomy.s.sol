// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {VibeToken} from "../src/tokens/VibeToken.sol";
import {VibeSpendRouter} from "../src/vibecheck/VibeSpendRouter.sol";

/**
 * @title DeployVibeEconomy
 * @notice Deploys VibeToken + VibeSpendRouter and wires them together.
 *
 * Usage:
 *   forge script script/DeployVibeEconomy.s.sol --rpc-url $BASE_SEPOLIA_RPC --broadcast
 */
contract DeployVibeEconomy is Script {
    function run() external {
        uint256 deployerPk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address admin      = vm.envAddress("ADMIN_ADDRESS");
        address treasury   = vm.envOr("TREASURY_ADDRESS", admin);

        vm.startBroadcast(deployerPk);

        // 1. Deploy $VIBE token
        VibeToken vibe = new VibeToken("VIBE", "VIBE", admin);
        console.log("VibeToken deployed:", address(vibe));

        // 2. Deploy VibeSpendRouter
        VibeSpendRouter router = new VibeSpendRouter(
            address(vibe),
            treasury,
            admin
        );
        console.log("VibeSpendRouter deployed:", address(router));

        // 3. Grant MINTER_ROLE to admin for initial distribution
        vibe.setMinter(admin, true);
        console.log("MINTER_ROLE granted to admin");

        vm.stopBroadcast();

        // Summary
        console.log("---");
        console.log("VIBE Token:     ", address(vibe));
        console.log("SpendRouter:    ", address(router));
        console.log("Treasury:       ", treasury);
        console.log("Admin:          ", admin);
    }
}
