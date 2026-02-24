// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";

import {ComputeCreditVault} from "../src/agents/ComputeCreditVault.sol";
import {EtrnaMindsHub}      from "../src/agents/EtrnaMindsHub.sol";
import {AgentCoordinator}   from "../src/agents/AgentCoordinator.sol";
import {RewardsDistributor} from "../src/agents/RewardsDistributor.sol";

/// @title DeployAgents — AI Agent Infrastructure
/// @notice Deploys ComputeCreditVault, EtrnaMindsHub, AgentCoordinator, RewardsDistributor
///         and wires roles between them.
///
/// Dependency:
///   - VIBE_TOKEN address required for RewardsDistributor
///   - SIGNER_KEY for off-chain rewards engine (defaults to ADMIN)
///
/// Environment variables:
///   ADMIN         — ecosystem admin address
///   VIBE_TOKEN    — VIBE ERC-20 address (required)
///   SIGNER_KEY    — rewards engine signer (default: ADMIN)
///   EPOCH_CAP     — max VIBE per epoch (default: 1_000_000 ether)
///
/// Usage:
///   forge script script/DeployAgents.s.sol --rpc-url $RPC --broadcast
contract DeployAgents is Script {
    function run() external {
        address admin     = vm.envAddress("ADMIN");
        address vibeToken = vm.envAddress("VIBE_TOKEN");
        address signerKey = vm.envOr("SIGNER_KEY", admin);
        uint256 epochCap  = vm.envOr("EPOCH_CAP", uint256(1_000_000 ether));

        vm.startBroadcast();

        // ═════════════════════════════════════════════════════════════════
        // 1. ComputeCreditVault — VIBE compute unit metering
        // ═════════════════════════════════════════════════════════════════
        ComputeCreditVault vault = new ComputeCreditVault(admin);
        console2.log("ComputeCreditVault:", address(vault));

        // ═════════════════════════════════════════════════════════════════
        // 2. EtrnaMindsHub — decentralised agent marketplace
        // ═════════════════════════════════════════════════════════════════
        EtrnaMindsHub hub = new EtrnaMindsHub(admin);
        console2.log("EtrnaMindsHub:     ", address(hub));

        // ═════════════════════════════════════════════════════════════════
        // 3. AgentCoordinator — multi-agent collaboration protocols
        // ═════════════════════════════════════════════════════════════════
        AgentCoordinator coordinator = new AgentCoordinator(admin);
        console2.log("AgentCoordinator:  ", address(coordinator));

        // ═════════════════════════════════════════════════════════════════
        // 4. RewardsDistributor — epoch-based VIBE minting
        // ═════════════════════════════════════════════════════════════════
        RewardsDistributor distributor = new RewardsDistributor(
            admin,
            vibeToken,
            signerKey,
            epochCap
        );
        console2.log("RewardsDistributor:", address(distributor));

        // ═════════════════════════════════════════════════════════════════
        // Cross-role wiring
        // ═════════════════════════════════════════════════════════════════
        // Grant hub ORCHESTRATOR on vault (so it can meter compute usage)
        vault.grantRole(vault.ORCHESTRATOR_ROLE(), address(hub));

        // Grant coordinator ORCHESTRATOR on hub (so it can manage tasks)
        hub.grantRole(hub.ORCHESTRATOR_ROLE(), address(coordinator));

        console2.log("");
        console2.log("=== AGENT INFRASTRUCTURE DEPLOYED ===");
        console2.log("Vault -> Hub -> Coordinator -> Distributor");
        console2.log("Roles wired. Admin:", admin);

        vm.stopBroadcast();
    }
}
