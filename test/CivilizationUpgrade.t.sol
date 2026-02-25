// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import {RealityLedger} from "../src/civilization/RealityLedger.sol";
import {TemporalRightNFT} from "../src/civilization/TemporalRightNFT.sol";
import {TimeEscrow} from "../src/civilization/TimeEscrow.sol";
import {CognitionMesh} from "../src/civilization/CognitionMesh.sol";
import {HumanityUpgradeProtocol} from "../src/civilization/HumanityUpgradeProtocol.sol";
import {ValueSignalAggregator} from "../src/civilization/ValueSignalAggregator.sol";
import {MeaningEngine} from "../src/civilization/MeaningEngine.sol";
import {JurisdictionRouter} from "../src/civilization/JurisdictionRouter.sol";

import {MockETR} from "./Mocks.sol";

contract CivilizationUpgradeTest is Test {
    address admin = address(0xA11CE);
    address alice = address(0xB0B);

    function test_RealityLedger_SubmitAndChallenge() external {
        MockETR etr = new MockETR();
        etr.mint(alice, 10 ether);

        RealityLedger ledger = new RealityLedger(admin, address(etr), 1 ether);

        vm.startPrank(alice);
        etr.approve(address(ledger), 10 ether);
        uint256 id = ledger.submitAssertion(bytes32("TOPIC"), bytes32("SCHEMA"), keccak256("payload"), 2 ether);
        assertEq(id, 1);
        vm.stopPrank();

        // challenger
        address charlie = address(0xC0FFEE);
        etr.mint(charlie, 10 ether);
        vm.startPrank(charlie);
        etr.approve(address(ledger), 10 ether);
        uint256 cid = ledger.challengeAssertion(1, 2 ether);
        assertEq(cid, 1);
        vm.stopPrank();
    }

    function test_TimeEscrow_MintAndRedeem() external {
        MockETR etr = new MockETR();
        etr.mint(alice, 10 ether);

        TemporalRightNFT rights = new TemporalRightNFT(admin);
        // grant minter to escrow later by admin
        TimeEscrow escrow = new TimeEscrow(admin, address(etr), address(rights));

        // admin grants escrow minter role
        vm.startPrank(admin);
        rights.grantRole(rights.MINTER_ROLE(), address(escrow));
        vm.stopPrank();

        vm.startPrank(alice);
        etr.approve(address(escrow), 10 ether);
        uint64 start = uint64(block.timestamp + 1);
        uint64 end = uint64(block.timestamp + 10);
        uint256 tokenId = escrow.mintWithEscrow(start, end, bytes32("WORK"), 3 ether);
        assertEq(tokenId, 1);

        vm.warp(end + 1);
        escrow.redeem(tokenId);
        assertEq(etr.balanceOf(alice), 10 ether);
        vm.stopPrank();
    }

    function test_MeaningEngine_ComputesWeightedSum() external {
        ValueSignalAggregator agg = new ValueSignalAggregator(admin);
        MeaningEngine m = new MeaningEngine(admin, address(agg));

        bytes32 ENERGY = bytes32("ENERGY_BPS");
        bytes32 TRUTH = bytes32("TRUTH_BPS");

        vm.prank(admin);
        m.setWeight(ENERGY, 5000); // 0.5
        vm.prank(admin);
        m.setWeight(TRUTH, 10000); // 1.0

        vm.prank(admin);
        agg.setSignal(1, ENERGY, alice, 8000);
        vm.prank(admin);
        agg.setSignal(1, TRUTH, alice, 2000);

        bytes32[] memory codes = new bytes32[](2);
        codes[0] = ENERGY;
        codes[1] = TRUTH;

        int256 meaning = m.meaningBps(1, alice, codes);
        // (8000*5000/10000)=4000, + (2000*10000/10000)=2000 => 6000
        assertEq(meaning, 6000);
    }
}
