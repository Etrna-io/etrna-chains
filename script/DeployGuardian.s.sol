// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";

import {FeeVault} from "../src/guardian/FeeVault.sol";
import {InsurancePool} from "../src/guardian/InsurancePool.sol";

/// @title DeployGuardian — FeeVault + InsurancePool
/// @notice Deploys the guardian financial infrastructure.
///
/// Environment variables required:
///   ADMIN — ecosystem admin / vault owner address
///
/// Optional:
///   FEE_OPERATOR — initial fee vault operator (defaults to ADMIN)
///
/// Usage:
///   forge script script/DeployGuardian.s.sol --rpc-url $RPC --broadcast --verify
contract DeployGuardian is Script {
    function run() external {
        address admin = vm.envAddress("ADMIN");
        address feeOperator = vm.envOr("FEE_OPERATOR", admin);

        vm.startBroadcast();

        // Deploy FeeVault with admin as owner
        FeeVault feeVault = new FeeVault(admin);

        // Set initial operator
        if (feeOperator != admin) {
            feeVault.setOperator(feeOperator, true);
        }

        // Deploy InsurancePool with admin as owner
        InsurancePool insurancePool = new InsurancePool(admin);

        vm.stopBroadcast();

        console2.log("=== GUARDIAN DEPLOYMENT ===");
        console2.log("FeeVault:", address(feeVault));
        console2.log("InsurancePool:", address(insurancePool));
        console2.log("FeeOperator:", feeOperator);
        console2.log("Owner:", admin);
    }
}
