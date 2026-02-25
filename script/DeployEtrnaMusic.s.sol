// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";

import {TrackRightsRegistry} from "../src/etrnamusic/TrackRightsRegistry.sol";
import {VenueProgramRegistry} from "../src/etrnamusic/VenueProgramRegistry.sol";
import {DJSetLedger} from "../src/etrnamusic/DJSetLedger.sol";
import {CulturalSignalRegistry} from "../src/etrnamusic/CulturalSignalRegistry.sol";
import {PerformanceAttribution} from "../src/etrnamusic/PerformanceAttribution.sol";

/**
 * @notice Deterministic deployment script for EtrnaMusic v1 contracts.
 *
 * Env vars:
 * - ADMIN: protocol admin (multisig/timelock)
 * - ETR_TOKEN: deployed $ETR token address
 * - ETRNAPASS: deployed EtrnaPass address
 * - COMMUNITY_POOL: address that receives community share reward units (v1)
 * - ORACLE: signal oracle address (optional; defaults to ADMIN)
 * - SETTLEMENT: settlement orchestrator address (optional; defaults to ADMIN)
 */
contract DeployEtrnaMusic is Script {
    function run() external {
        address admin = vm.envAddress("ADMIN");
        address etr = vm.envAddress("ETR_TOKEN");
        address pass = vm.envAddress("ETRNAPASS");
        address communityPool = vm.envAddress("COMMUNITY_POOL");

        address oracle = vm.envOr("ORACLE", admin);
        address settlement = vm.envOr("SETTLEMENT", admin);

        vm.startBroadcast();

        TrackRightsRegistry trackRights = new TrackRightsRegistry(admin);
        VenueProgramRegistry venues = new VenueProgramRegistry(admin, etr);
        DJSetLedger sets = new DJSetLedger(admin, pass, address(venues));
        CulturalSignalRegistry signals = new CulturalSignalRegistry(admin);
        PerformanceAttribution attrib = new PerformanceAttribution(admin, address(sets), address(venues), address(signals), communityPool);

        // Optional role assignment for ops keys.
        signals.grantRole(signals.ORACLE_ROLE(), oracle);
        attrib.grantRole(attrib.SETTLEMENT_ROLE(), settlement);

        // Allow the attribution contract to mark sets as settled in the DJ set ledger.
        sets.grantRole(sets.SETTLEMENT_ROLE(), address(attrib));

        console2.log("TrackRightsRegistry", address(trackRights));
        console2.log("VenueProgramRegistry", address(venues));
        console2.log("DJSetLedger", address(sets));
        console2.log("CulturalSignalRegistry", address(signals));
        console2.log("PerformanceAttribution", address(attrib));

        vm.stopBroadcast();
    }
}
