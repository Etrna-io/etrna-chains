// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";

import {QuantumRandomness} from "../src/quantum/QuantumRandomness.sol";
import {QuantumKeyPolicyRegistry} from "../src/quantum/QuantumKeyPolicyRegistry.sol";

/// @title DeployQuantum — QuantumRandomness + QuantumKeyPolicyRegistry
/// @notice Deploys quantum randomness infrastructure and key policy registry.
///
/// Environment variables required:
///   ADMIN — ecosystem admin address
///
/// Optional:
///   QUANTUM_FULFILLER — initial authorized fulfiller (defaults to ADMIN)
///
/// Usage:
///   forge script script/DeployQuantum.s.sol --rpc-url $RPC --broadcast --verify
contract DeployQuantum is Script {
    function run() external {
        address admin = vm.envAddress("ADMIN");
        address fulfiller = vm.envOr("QUANTUM_FULFILLER", admin);

        vm.startBroadcast();

        // Deploy QuantumRandomness with initial fulfiller
        QuantumRandomness randomness = new QuantumRandomness(fulfiller);

        // Deploy QuantumKeyPolicyRegistry (Ownable — deployer becomes owner)
        QuantumKeyPolicyRegistry policyRegistry = new QuantumKeyPolicyRegistry();

        // Transfer ownership to admin
        randomness.transferOwnership(admin);
        policyRegistry.transferOwnership(admin);

        vm.stopBroadcast();

        console2.log("=== QUANTUM DEPLOYMENT ===");
        console2.log("QuantumRandomness:", address(randomness));
        console2.log("QuantumKeyPolicyRegistry:", address(policyRegistry));
        console2.log("InitialFulfiller:", fulfiller);
        console2.log("Owner:", admin);
    }
}
