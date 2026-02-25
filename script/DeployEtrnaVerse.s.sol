// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {BlueprintRegistry} from "../src/etrnaverse/BlueprintRegistry.sol";
import {MilestoneEscrow} from "../src/etrnaverse/MilestoneEscrow.sol";
import {ReceiptNFT} from "../src/etrnaverse/ReceiptNFT.sol";

/**
 * @title DeployEtrnaVerse
 * @notice Deploys the EtrnaVerse contract suite:
 *   - BlueprintRegistry (on-chain blueprint catalog)
 *   - MilestoneEscrow   (pledge + milestone release)
 *   - ReceiptNFT         (soulbound deployment receipts)
 *
 * Usage:
 *   ADMIN=0x... forge script script/DeployEtrnaVerse.s.sol --broadcast
 */
contract DeployEtrnaVerse is Script {
    function run() external {
        address admin = vm.envAddress("ADMIN");

        vm.startBroadcast();

        BlueprintRegistry registry = new BlueprintRegistry(admin);
        MilestoneEscrow escrow = new MilestoneEscrow(admin);
        ReceiptNFT receipt = new ReceiptNFT(admin);

        vm.stopBroadcast();

        console2.log("BlueprintRegistry:", address(registry));
        console2.log("MilestoneEscrow:  ", address(escrow));
        console2.log("ReceiptNFT:       ", address(receipt));
    }
}
