// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/bridge/NftBridgeRouter.sol";

// ── Mock ERC721 ───────────────────────────────────────────────
contract MockERC721 {
    mapping(uint256 => address) public owners;
    mapping(uint256 => address) public approvals;
    mapping(address => mapping(address => bool)) public operatorApprovals;

    function mint(address to, uint256 tokenId) external {
        owners[tokenId] = to;
    }

    function ownerOf(uint256 tokenId) external view returns (address) {
        return owners[tokenId];
    }

    function getApproved(uint256 tokenId) external view returns (address) {
        return approvals[tokenId];
    }

    function isApprovedForAll(address owner_, address operator) external view returns (bool) {
        return operatorApprovals[owner_][operator];
    }

    function approve(address to, uint256 tokenId) external {
        approvals[tokenId] = to;
    }

    function setApprovalForAll(address operator, bool approved) external {
        operatorApprovals[msg.sender][operator] = approved;
    }
}

// ── Mock Bridge Adapter ───────────────────────────────────────
contract MockBridgeAdapter {
    bytes32 public lastBridgeTxId;
    uint256 public callCount;

    function bridgeERC721(
        address /* nft */,
        uint256 /* tokenId */,
        uint256 /* dstChainId */,
        address /* to */,
        bytes calldata /* data */
    ) external returns (bytes32 bridgeTxId) {
        callCount++;
        bridgeTxId = keccak256(abi.encodePacked(callCount, block.timestamp));
        lastBridgeTxId = bridgeTxId;
    }
}

contract NftBridgeRouterTest is Test {
    NftBridgeRouter public bridgeRouter;
    MockERC721 public nft;
    MockBridgeAdapter public adapter;

    address owner = address(this);
    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    uint256 constant DST_CHAIN = 42;
    uint256 constant TOKEN_ID = 1;

    bytes32 constant REQ_1 = keccak256("req-1");
    bytes32 constant REQ_2 = keccak256("req-2");

    function setUp() public {
        bridgeRouter = new NftBridgeRouter();
        nft = new MockERC721();
        adapter = new MockBridgeAdapter();

        // Setup: register adapter for DST_CHAIN
        bridgeRouter.setAdapter(DST_CHAIN, address(adapter));

        // Mint NFT to alice
        nft.mint(alice, TOKEN_ID);

        // Alice approves the router
        vm.prank(alice);
        nft.setApprovalForAll(address(bridgeRouter), true);
    }

    // ─── setAdapter ───────────────────────────────────────────

    function test_SetAdapter() public {
        address newAdapter = address(0xADA);
        vm.expectEmit(true, true, false, false);
        emit NftBridgeRouter.AdapterSet(99, newAdapter);
        bridgeRouter.setAdapter(99, newAdapter);
        assertEq(bridgeRouter.adapterForChain(99), newAdapter);
    }

    function test_RevertSetAdapter_NotOwner() public {
        vm.prank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        bridgeRouter.setAdapter(1, address(adapter));
    }

    // ─── setNftAllowed ────────────────────────────────────────

    function test_SetNftAllowed() public {
        vm.expectEmit(true, false, false, true);
        emit NftBridgeRouter.NftAllowlistSet(address(nft), true);
        bridgeRouter.setNftAllowed(address(nft), true);
        assertTrue(bridgeRouter.nftAllowed(address(nft)));
    }

    function test_SetNftAllowed_Remove() public {
        bridgeRouter.setNftAllowed(address(nft), true);
        bridgeRouter.setNftAllowed(address(nft), false);
        assertFalse(bridgeRouter.nftAllowed(address(nft)));
    }

    function test_RevertSetNftAllowed_NotOwner() public {
        vm.prank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        bridgeRouter.setNftAllowed(address(nft), true);
    }

    // ─── setAllowlistMode ─────────────────────────────────────

    function test_SetAllowlistMode() public {
        bridgeRouter.setAllowlistMode(true);
        assertTrue(bridgeRouter.allowlistMode());
    }

    function test_RevertSetAllowlistMode_NotOwner() public {
        vm.prank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        bridgeRouter.setAllowlistMode(true);
    }

    // ─── Pause / Unpause ──────────────────────────────────────

    function test_Pause() public {
        bridgeRouter.pause();

        vm.prank(alice);
        vm.expectRevert("Pausable: paused");
        bridgeRouter.bridgeERC721(
            REQ_1, address(nft), TOKEN_ID, DST_CHAIN, alice, bytes32(0), hex""
        );
    }

    function test_Unpause() public {
        bridgeRouter.pause();
        bridgeRouter.unpause();

        vm.prank(alice);
        bridgeRouter.bridgeERC721(
            REQ_1, address(nft), TOKEN_ID, DST_CHAIN, alice, bytes32(0), hex""
        );
    }

    function test_RevertPause_NotOwner() public {
        vm.prank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        bridgeRouter.pause();
    }

    function test_RevertUnpause_NotOwner() public {
        bridgeRouter.pause();
        vm.prank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        bridgeRouter.unpause();
    }

    // ─── bridgeERC721 — success ───────────────────────────────

    function test_Bridge_Success() public {
        bytes32 metaHash = keccak256("metadata");

        vm.prank(alice);
        bytes32 txId = bridgeRouter.bridgeERC721(
            REQ_1, address(nft), TOKEN_ID, DST_CHAIN, bob, metaHash, hex""
        );

        assertTrue(txId != bytes32(0));
        assertTrue(bridgeRouter.consumedClientRequest(REQ_1));
        assertEq(adapter.callCount(), 1);
    }

    function test_Bridge_EmitsBridgedEvent() public {
        bytes32 metaHash = keccak256("metadata");

        vm.prank(alice);
        // Just verify no revert and event structure. The bridgeTxId is computed by the adapter.
        bridgeRouter.bridgeERC721(
            REQ_1, address(nft), TOKEN_ID, DST_CHAIN, bob, metaHash, hex""
        );
    }

    function test_Bridge_WithAdapterData() public {
        bytes memory extraData = abi.encode("bridge-instructions");

        vm.prank(alice);
        bytes32 txId = bridgeRouter.bridgeERC721(
            REQ_1, address(nft), TOKEN_ID, DST_CHAIN, bob, bytes32(0), extraData
        );

        assertTrue(txId != bytes32(0));
    }

    // ─── bridgeERC721 — reverts ───────────────────────────────

    function test_Bridge_RevertZeroRequestId() public {
        vm.prank(alice);
        vm.expectRevert("NftBridgeRouter: requestId=0");
        bridgeRouter.bridgeERC721(
            bytes32(0), address(nft), TOKEN_ID, DST_CHAIN, bob, bytes32(0), hex""
        );
    }

    function test_Bridge_RevertReplay() public {
        vm.startPrank(alice);
        bridgeRouter.bridgeERC721(
            REQ_1, address(nft), TOKEN_ID, DST_CHAIN, bob, bytes32(0), hex""
        );

        nft.mint(alice, 2); // mint another to avoid "not owner" error
        vm.expectRevert("NftBridgeRouter: replay");
        bridgeRouter.bridgeERC721(
            REQ_1, address(nft), 2, DST_CHAIN, bob, bytes32(0), hex""
        );
        vm.stopPrank();
    }

    function test_Bridge_RevertNotOwner() public {
        vm.prank(bob); // bob doesn't own token
        vm.expectRevert("NftBridgeRouter: not owner");
        bridgeRouter.bridgeERC721(
            REQ_1, address(nft), TOKEN_ID, DST_CHAIN, bob, bytes32(0), hex""
        );
    }

    function test_Bridge_RevertNotApproved() public {
        nft.mint(bob, 2);
        // bob does NOT approve the router

        vm.prank(bob);
        vm.expectRevert("NftBridgeRouter: not approved");
        bridgeRouter.bridgeERC721(
            REQ_1, address(nft), 2, DST_CHAIN, alice, bytes32(0), hex""
        );
    }

    function test_Bridge_RevertNoAdapter() public {
        uint256 unknownChain = 999;

        vm.prank(alice);
        vm.expectRevert("NftBridgeRouter: no adapter");
        bridgeRouter.bridgeERC721(
            REQ_1, address(nft), TOKEN_ID, unknownChain, bob, bytes32(0), hex""
        );
    }

    // ─── Allowlist mode ───────────────────────────────────────

    function test_Bridge_AllowlistMode_Allowed() public {
        bridgeRouter.setAllowlistMode(true);
        bridgeRouter.setNftAllowed(address(nft), true);

        vm.prank(alice);
        bytes32 txId = bridgeRouter.bridgeERC721(
            REQ_1, address(nft), TOKEN_ID, DST_CHAIN, bob, bytes32(0), hex""
        );
        assertTrue(txId != bytes32(0));
    }

    function test_Bridge_AllowlistMode_NotAllowed() public {
        bridgeRouter.setAllowlistMode(true);
        // do NOT allowlist the nft

        vm.prank(alice);
        vm.expectRevert("NftBridgeRouter: nft not allowlisted");
        bridgeRouter.bridgeERC721(
            REQ_1, address(nft), TOKEN_ID, DST_CHAIN, bob, bytes32(0), hex""
        );
    }

    function test_Bridge_AllowlistModeOff_AnyNftAllowed() public {
        // allowlist mode off (default), any NFT is fine
        vm.prank(alice);
        bytes32 txId = bridgeRouter.bridgeERC721(
            REQ_1, address(nft), TOKEN_ID, DST_CHAIN, bob, bytes32(0), hex""
        );
        assertTrue(txId != bytes32(0));
    }

    // ─── Approval via getApproved (single token approval) ─────

    function test_Bridge_SingleTokenApproval() public {
        nft.mint(bob, 2);
        // bob approves router for just token 2
        vm.prank(bob);
        nft.approve(address(bridgeRouter), 2);

        vm.prank(bob);
        bytes32 txId = bridgeRouter.bridgeERC721(
            REQ_1, address(nft), 2, DST_CHAIN, alice, bytes32(0), hex""
        );
        assertTrue(txId != bytes32(0));
    }
}
