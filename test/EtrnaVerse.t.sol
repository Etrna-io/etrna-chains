// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import {MockETR} from "./Mocks.sol";

import {MilestoneEscrow} from "../src/etrnaverse/MilestoneEscrow.sol";
import {ReceiptNFT} from "../src/etrnaverse/ReceiptNFT.sol";
import {BlueprintRegistry} from "../src/etrnaverse/BlueprintRegistry.sol";

contract EtrnaVerseTest is Test {
    address internal admin = address(0xA11CE);
    address internal creator = address(0xC0DE);
    address internal pledger = address(0xBEEF);
    address internal deployer = address(0xD00D);

    MockETR internal etr;
    MilestoneEscrow internal escrow;
    ReceiptNFT internal receipt;
    BlueprintRegistry internal registry;

    function setUp() public {
        etr = new MockETR();
        etr.mint(pledger, 100 ether);

        escrow = new MilestoneEscrow(admin);
        receipt = new ReceiptNFT(admin);
        registry = new BlueprintRegistry(admin);
    }

    // ═══════════════════════════════════════════════════════════════════
    // BlueprintRegistry
    // ═══════════════════════════════════════════════════════════════════

    function test_RegisterBlueprint() public {
        bytes32 bpId = keccak256("solar-panel-v1");
        bytes32 metaHash = keccak256("ipfs://QmSolar");
        bytes32 layer = keccak256("infra");

        vm.prank(admin);
        registry.register(bpId, creator, metaHash, layer);

        (address c, bytes32 mh, bytes32 l, , , bool active) = registry.getBlueprint(bpId);
        assertEq(c, creator);
        assertEq(mh, metaHash);
        assertEq(l, layer);
        assertTrue(active);
        assertEq(registry.getBlueprintCount(), 1);
    }

    function test_RevertDuplicateBlueprint() public {
        bytes32 bpId = keccak256("solar-panel-v1");
        vm.startPrank(admin);
        registry.register(bpId, creator, keccak256("meta"), keccak256("infra"));
        vm.expectRevert();
        registry.register(bpId, creator, keccak256("meta2"), keccak256("infra"));
        vm.stopPrank();
    }

    function test_DeactivateBlueprint() public {
        bytes32 bpId = keccak256("wind-turbine-v1");
        vm.startPrank(admin);
        registry.register(bpId, creator, keccak256("meta"), keccak256("infra"));
        assertTrue(registry.isActive(bpId));

        registry.deactivate(bpId);
        assertFalse(registry.isActive(bpId));

        registry.reactivate(bpId);
        assertTrue(registry.isActive(bpId));
        vm.stopPrank();
    }

    function test_UpdateSimScore() public {
        bytes32 bpId = keccak256("hydro-dam-v1");
        vm.startPrank(admin);
        registry.register(bpId, creator, keccak256("meta"), keccak256("infra"));

        registry.updateSimScore(bpId, 7500);
        (, , , , uint32 score, ) = registry.getBlueprint(bpId);
        assertEq(score, 7500);
        vm.stopPrank();
    }

    function test_RevertSimScoreOver10000() public {
        bytes32 bpId = keccak256("over-v1");
        vm.startPrank(admin);
        registry.register(bpId, creator, keccak256("meta"), keccak256("infra"));
        vm.expectRevert();
        registry.updateSimScore(bpId, 10001);
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════
    // MilestoneEscrow
    // ═══════════════════════════════════════════════════════════════════

    function test_CampaignLifecycle() public {
        bytes32 bpId = keccak256("bp-1");

        // Create campaign
        vm.prank(admin);
        uint256 cId = escrow.createCampaign(bpId, payable(creator), address(etr));
        assertEq(cId, 1);

        // Define milestones
        string[] memory labels = new string[](2);
        labels[0] = "Prototype";
        labels[1] = "Launch";
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 3 ether;
        amounts[1] = 7 ether;

        vm.prank(creator);
        escrow.defineMilestones(cId, labels, amounts);

        // Pledge
        vm.startPrank(pledger);
        etr.approve(address(escrow), 10 ether);
        escrow.pledge(cId, 10 ether);
        vm.stopPrank();

        (, , , uint256 pledged, , , ) = escrow.campaigns(cId);
        assertEq(pledged, 10 ether);

        // Approve milestone 0
        vm.prank(admin);
        escrow.approveMilestone(cId, 0);

        // Release milestone 0
        escrow.releaseMilestone(cId, 0);
        assertEq(etr.balanceOf(creator), 3 ether);

        // Approve + release milestone 1
        vm.prank(admin);
        escrow.approveMilestone(cId, 1);
        escrow.releaseMilestone(cId, 1);
        assertEq(etr.balanceOf(creator), 10 ether);

        // Verify campaign completed
        (, , , , , MilestoneEscrow.CampaignStatus status, ) = escrow.campaigns(cId);
        assertEq(uint8(status), uint8(MilestoneEscrow.CampaignStatus.COMPLETED));
    }

    function test_RefundFlow() public {
        bytes32 bpId = keccak256("bp-refund");
        vm.prank(admin);
        uint256 cId = escrow.createCampaign(bpId, payable(creator), address(etr));

        vm.startPrank(pledger);
        etr.approve(address(escrow), 5 ether);
        escrow.pledge(cId, 5 ether);
        vm.stopPrank();

        // Enable refunds
        vm.prank(admin);
        escrow.enableRefunds(cId);

        // Pledger refunds
        vm.prank(pledger);
        escrow.refund(cId, 0);
        assertEq(etr.balanceOf(pledger), 100 ether); // restored to original
    }

    // ═══════════════════════════════════════════════════════════════════
    // ReceiptNFT
    // ═══════════════════════════════════════════════════════════════════

    function test_MintReceipt() public {
        vm.prank(admin);
        uint256 tokenId = receipt.mintReceipt(
            deployer,
            keccak256("bp-solar"),
            uint64(block.chainid),
            address(0x1234),
            keccak256("0xTxHash"),
            "Solar Panel v1"
        );

        assertEq(tokenId, 1);
        assertEq(receipt.ownerOf(1), deployer);

        (
            bytes32 bpId,
            uint64 chainId,
            address deployed,
            bytes32 txHash,
            uint64 ts,
            string memory label
        ) = receipt.getReceipt(1);
        assertEq(bpId, keccak256("bp-solar"));
        assertEq(chainId, uint64(block.chainid));
        assertEq(deployed, address(0x1234));
        assertEq(txHash, keccak256("0xTxHash"));
        assertTrue(ts > 0);
        assertEq(label, "Solar Panel v1");
    }

    function test_ReceiptIsSoulbound() public {
        vm.prank(admin);
        receipt.mintReceipt(
            deployer,
            keccak256("bp-1"),
            1,
            address(0x5678),
            keccak256("tx"),
            "Test"
        );

        // Attempt transfer should revert
        vm.prank(deployer);
        vm.expectRevert();
        receipt.transferFrom(deployer, pledger, 1);
    }

    function test_RevertZeroAdmin() public {
        vm.expectRevert();
        new MilestoneEscrow(address(0));

        vm.expectRevert();
        new ReceiptNFT(address(0));

        vm.expectRevert();
        new BlueprintRegistry(address(0));
    }
}
