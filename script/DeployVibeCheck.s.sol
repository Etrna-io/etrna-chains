// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {VibeCheckRegistry} from "../src/vibecheck/VibeCheckRegistry.sol";
import {VibeCheckMissions} from "../src/vibecheck/VibeCheckMissions.sol";

/**
 * @title  DeployVibeCheck
 * @notice Deploys VibeCheckRegistry + VibeCheckMissions behind UUPS proxies.
 *
 * Usage:
 *   forge script script/DeployVibeCheck.s.sol:DeployVibeCheck \
 *     --rpc-url $RPC_URL --broadcast --verify \
 *     -vvvv
 *
 * Required env vars:
 *   DEPLOYER_PRIVATE_KEY
 */
contract DeployVibeCheck is Script {
    function run()
        external
        returns (
            address registryProxy,
            address missionsProxy
        )
    {
        uint256 pk = vm.envUint("DEPLOYER_PRIVATE_KEY");

        vm.startBroadcast(pk);

        // ── Deploy implementation contracts ──────────────────────────
        VibeCheckRegistry registryImpl = new VibeCheckRegistry();
        VibeCheckMissions missionsImpl = new VibeCheckMissions();

        // ── Deploy proxies with initialize() ─────────────────────────
        bytes memory initRegistry = abi.encodeCall(VibeCheckRegistry.initialize, ());
        bytes memory initMissions = abi.encodeCall(VibeCheckMissions.initialize, ());

        ERC1967Proxy rProxy = new ERC1967Proxy(address(registryImpl), initRegistry);
        ERC1967Proxy mProxy = new ERC1967Proxy(address(missionsImpl), initMissions);

        registryProxy = address(rProxy);
        missionsProxy = address(mProxy);

        vm.stopBroadcast();

        // ── Log addresses ────────────────────────────────────────────
        console.log("=== VibeCheck Deployment Complete ===");
        console.log("VibeCheckRegistry impl :", address(registryImpl));
        console.log("VibeCheckRegistry proxy:", registryProxy);
        console.log("VibeCheckMissions impl :", address(missionsImpl));
        console.log("VibeCheckMissions proxy:", missionsProxy);
        console.log("=====================================");
    }
}
