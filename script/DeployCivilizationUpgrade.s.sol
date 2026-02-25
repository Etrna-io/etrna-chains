// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";

import {RealityLedger} from "../src/civilization/RealityLedger.sol";
import {RealityState} from "../src/civilization/RealityState.sol";
import {TemporalRightNFT} from "../src/civilization/TemporalRightNFT.sol";
import {TimeEscrow} from "../src/civilization/TimeEscrow.sol";
import {CognitionMesh} from "../src/civilization/CognitionMesh.sol";
import {HumanityUpgradeProtocol} from "../src/civilization/HumanityUpgradeProtocol.sol";
import {ValueSignalAggregator} from "../src/civilization/ValueSignalAggregator.sol";
import {MeaningEngine} from "../src/civilization/MeaningEngine.sol";
import {JurisdictionRouter} from "../src/civilization/JurisdictionRouter.sol";

/**
 * @notice Deterministic deployment script for the v0 Civilization Upgrade stack.
 *
 * Env vars:
 * - ADMIN: protocol admin (multisig/timelock)
 * - ETR_TOKEN: deployed $ETR token address
 */
contract DeployCivilizationUpgrade is Script {
    function run() external {
        address admin = vm.envAddress("ADMIN");
        address etr = vm.envAddress("ETR_TOKEN");

        vm.startBroadcast();

        // Reality
        RealityLedger ledger = new RealityLedger(admin, etr, 1 ether);
        RealityState rState = new RealityState(admin);

        // TimeOS
        TemporalRightNFT rights = new TemporalRightNFT(admin);
        TimeEscrow escrow = new TimeEscrow(admin, etr, address(rights));

        // Cognition
        CognitionMesh cognition = new CognitionMesh(admin);

        // HUP
        HumanityUpgradeProtocol hup = new HumanityUpgradeProtocol(admin, etr);

        // PLE + Meaning
        ValueSignalAggregator agg = new ValueSignalAggregator(admin);
        MeaningEngine meaning = new MeaningEngine(admin, address(agg));

        // Post-nation
        JurisdictionRouter router = new JurisdictionRouter(admin);

        // Silence unused warnings by reading addresses
        console2.log("RealityLedger", address(ledger));
        console2.log("RealityState", address(rState));
        console2.log("TemporalRightNFT", address(rights));
        console2.log("TimeEscrow", address(escrow));
        console2.log("CognitionMesh", address(cognition));
        console2.log("HUP", address(hup));
        console2.log("ValueSignalAggregator", address(agg));
        console2.log("MeaningEngine", address(meaning));
        console2.log("JurisdictionRouter", address(router));

        vm.stopBroadcast();
    }
}
