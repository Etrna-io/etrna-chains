// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/mesh/MeshHub.sol";
import "../src/mesh/MeshTypes.sol";

contract MeshHubTest is Test {
    MeshHub public hub;

    address owner = address(this);
    address router = address(0xBEEF);
    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    address adapter1 = address(0xADA1);
    address adapter2 = address(0xADA2);

    function setUp() public {
        hub = new MeshHub(router);
    }

    // ─── Constructor ──────────────────────────────────────────

    function test_Constructor() public view {
        assertEq(hub.routerBackend(), router);
        assertEq(hub.owner(), owner);
    }

    // ─── setRouterBackend ─────────────────────────────────────

    function test_SetRouterBackend() public {
        hub.setRouterBackend(bob);
        assertEq(hub.routerBackend(), bob);
    }

    function test_RevertSetRouterBackend_NotOwner() public {
        vm.prank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        hub.setRouterBackend(bob);
    }

    // ─── setAdapter ───────────────────────────────────────────

    function test_SetAdapter() public {
        bytes4 sel = bytes4(keccak256("MINT_NFT"));
        hub.setAdapter(1, sel, adapter1);
        assertEq(hub.adapters(1, sel), adapter1);
    }

    function test_SetAdapter_OverwriteExisting() public {
        bytes4 sel = bytes4(keccak256("MINT_NFT"));
        hub.setAdapter(1, sel, adapter1);
        hub.setAdapter(1, sel, adapter2);
        assertEq(hub.adapters(1, sel), adapter2);
    }

    function test_RevertSetAdapter_NotOwner() public {
        vm.prank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        hub.setAdapter(1, bytes4(0), adapter1);
    }

    // ─── createIntent ─────────────────────────────────────────

    function test_CreateIntent() public {
        vm.prank(alice);
        bytes32 intentId = hub.createIntent(
            MeshTypes.ActionType.MINT_NFT,
            42,
            address(0),
            100,
            keccak256("params")
        );
        assertTrue(intentId != bytes32(0));

        MeshTypes.Intent memory intent = hub.getIntent(intentId);
        assertEq(intent.creator, alice);
        assertEq(uint256(intent.actionType), uint256(MeshTypes.ActionType.MINT_NFT));
        assertEq(intent.dstChainId, 42);
        assertEq(intent.asset, address(0));
        assertEq(intent.amount, 100);
        assertEq(intent.paramsHash, keccak256("params"));
        assertEq(uint256(intent.status), uint256(MeshTypes.IntentStatus.PENDING));
        assertEq(intent.createdAt, block.timestamp);
    }

    function test_CreateIntent_EmitsEvent() public {
        vm.prank(alice);
        vm.expectEmit(false, true, false, true);
        emit MeshHub.IntentCreated(
            bytes32(0), // intentId not checked (indexed, hard to predict)
            alice,
            MeshTypes.ActionType.BRIDGE,
            block.chainid,
            10,
            keccak256("data")
        );
        hub.createIntent(MeshTypes.ActionType.BRIDGE, 10, address(0), 0, keccak256("data"));
    }

    function test_CreateIntent_PayableAcceptsValue() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        bytes32 id = hub.createIntent{value: 0.5 ether}(
            MeshTypes.ActionType.STAKE,
            1,
            address(0),
            1 ether,
            bytes32(0)
        );
        assertTrue(id != bytes32(0));
    }

    function test_RevertCreateIntent_UnknownAction() public {
        vm.prank(alice);
        vm.expectRevert("MeshHub: invalid action");
        hub.createIntent(MeshTypes.ActionType.UNKNOWN, 1, address(0), 0, bytes32(0));
    }

    // ─── Full lifecycle: create → route → complete ────────────

    function test_Lifecycle_CreateRouteComplete() public {
        vm.prank(alice);
        bytes32 intentId = hub.createIntent(
            MeshTypes.ActionType.BRIDGE,
            10,
            address(0),
            500,
            keccak256("bridge-params")
        );

        // Route
        vm.prank(router);
        hub.markRouted(intentId, abi.encode("route-data"));

        MeshTypes.Intent memory routed = hub.getIntent(intentId);
        assertEq(uint256(routed.status), uint256(MeshTypes.IntentStatus.ROUTED));

        // Complete
        bytes32 dstTxHash = keccak256("dst-tx");
        vm.prank(router);
        hub.markCompleted(intentId, dstTxHash);

        MeshTypes.Intent memory completed = hub.getIntent(intentId);
        assertEq(uint256(completed.status), uint256(MeshTypes.IntentStatus.COMPLETED));
    }

    // ─── Full lifecycle: create → route → fail ────────────────

    function test_Lifecycle_CreateRouteFail() public {
        vm.prank(alice);
        bytes32 intentId = hub.createIntent(
            MeshTypes.ActionType.SWAP,
            5,
            address(0),
            200,
            bytes32(0)
        );

        vm.prank(router);
        hub.markRouted(intentId, hex"");

        vm.prank(router);
        hub.markFailed(intentId, "adapter error");

        MeshTypes.Intent memory failed = hub.getIntent(intentId);
        assertEq(uint256(failed.status), uint256(MeshTypes.IntentStatus.FAILED));
    }

    // ─── markFailed from PENDING ──────────────────────────────

    function test_MarkFailed_FromPending() public {
        vm.prank(alice);
        bytes32 intentId = hub.createIntent(
            MeshTypes.ActionType.UNSTAKE,
            1,
            address(0),
            0,
            bytes32(0)
        );

        vm.prank(router);
        hub.markFailed(intentId, "cancelled");

        MeshTypes.Intent memory failed = hub.getIntent(intentId);
        assertEq(uint256(failed.status), uint256(MeshTypes.IntentStatus.FAILED));
    }

    // ─── markRouted events ────────────────────────────────────

    function test_MarkRouted_EmitsEvent() public {
        vm.prank(alice);
        bytes32 intentId = hub.createIntent(
            MeshTypes.ActionType.MINT_NFT,
            42,
            address(0),
            1,
            bytes32(0)
        );

        bytes memory routeData = abi.encode("some-route");
        vm.prank(router);
        vm.expectEmit(true, true, false, true);
        emit MeshHub.IntentRouted(intentId, router, 42, routeData);
        hub.markRouted(intentId, routeData);
    }

    function test_MarkCompleted_EmitsEvent() public {
        vm.prank(alice);
        bytes32 intentId = hub.createIntent(
            MeshTypes.ActionType.BRIDGE,
            10,
            address(0),
            0,
            bytes32(0)
        );

        vm.prank(router);
        hub.markRouted(intentId, hex"");

        bytes32 dstTx = keccak256("done");
        vm.prank(router);
        vm.expectEmit(true, false, false, true);
        emit MeshHub.IntentCompleted(intentId, dstTx);
        hub.markCompleted(intentId, dstTx);
    }

    function test_MarkFailed_EmitsEvent() public {
        vm.prank(alice);
        bytes32 intentId = hub.createIntent(
            MeshTypes.ActionType.STAKE,
            1,
            address(0),
            0,
            bytes32(0)
        );

        vm.prank(router);
        vm.expectEmit(true, false, false, true);
        emit MeshHub.IntentFailed(intentId, "oops");
        hub.markFailed(intentId, "oops");
    }

    // ─── Access control: onlyRouter ───────────────────────────

    function test_RevertMarkRouted_NotRouter() public {
        vm.prank(alice);
        bytes32 id = hub.createIntent(MeshTypes.ActionType.BRIDGE, 1, address(0), 0, bytes32(0));

        vm.prank(alice);
        vm.expectRevert("MeshHub: not router");
        hub.markRouted(id, hex"");
    }

    function test_RevertMarkCompleted_NotRouter() public {
        vm.prank(alice);
        bytes32 id = hub.createIntent(MeshTypes.ActionType.BRIDGE, 1, address(0), 0, bytes32(0));

        vm.prank(router);
        hub.markRouted(id, hex"");

        vm.prank(alice);
        vm.expectRevert("MeshHub: not router");
        hub.markCompleted(id, bytes32(0));
    }

    function test_RevertMarkFailed_NotRouter() public {
        vm.prank(alice);
        bytes32 id = hub.createIntent(MeshTypes.ActionType.BRIDGE, 1, address(0), 0, bytes32(0));

        vm.prank(alice);
        vm.expectRevert("MeshHub: not router");
        hub.markFailed(id, "fail");
    }

    function test_OwnerCanRouteIntents() public {
        // owner is also allowed by onlyRouter modifier
        vm.prank(alice);
        bytes32 id = hub.createIntent(MeshTypes.ActionType.BRIDGE, 1, address(0), 0, bytes32(0));

        // owner (this contract) can call markRouted
        hub.markRouted(id, hex"");
        MeshTypes.Intent memory intent = hub.getIntent(id);
        assertEq(uint256(intent.status), uint256(MeshTypes.IntentStatus.ROUTED));
    }

    // ─── State transition errors ──────────────────────────────

    function test_RevertMarkRouted_UnknownIntent() public {
        vm.prank(router);
        vm.expectRevert("MeshHub: unknown intent");
        hub.markRouted(bytes32(uint256(999)), hex"");
    }

    function test_RevertMarkRouted_NotPending() public {
        vm.prank(alice);
        bytes32 id = hub.createIntent(MeshTypes.ActionType.BRIDGE, 1, address(0), 0, bytes32(0));

        vm.startPrank(router);
        hub.markRouted(id, hex"");
        vm.expectRevert("MeshHub: not pending");
        hub.markRouted(id, hex"");
        vm.stopPrank();
    }

    function test_RevertMarkCompleted_NotRouted() public {
        vm.prank(alice);
        bytes32 id = hub.createIntent(MeshTypes.ActionType.BRIDGE, 1, address(0), 0, bytes32(0));

        vm.prank(router);
        vm.expectRevert("MeshHub: not routed");
        hub.markCompleted(id, bytes32(0));
    }

    function test_RevertMarkFailed_FromCompleted() public {
        vm.prank(alice);
        bytes32 id = hub.createIntent(MeshTypes.ActionType.BRIDGE, 1, address(0), 0, bytes32(0));

        vm.startPrank(router);
        hub.markRouted(id, hex"");
        hub.markCompleted(id, bytes32(0));
        vm.expectRevert("MeshHub: invalid state");
        hub.markFailed(id, "too late");
        vm.stopPrank();
    }

    function test_RevertMarkFailed_AlreadyFailed() public {
        vm.prank(alice);
        bytes32 id = hub.createIntent(MeshTypes.ActionType.BRIDGE, 1, address(0), 0, bytes32(0));

        vm.startPrank(router);
        hub.markFailed(id, "first fail");
        vm.expectRevert("MeshHub: invalid state");
        hub.markFailed(id, "second fail");
        vm.stopPrank();
    }

    // ─── getIntent ────────────────────────────────────────────

    function test_GetIntent_ReturnsDefault() public view {
        MeshTypes.Intent memory intent = hub.getIntent(bytes32(uint256(42)));
        assertEq(intent.creator, address(0));
        assertEq(uint256(intent.status), uint256(MeshTypes.IntentStatus.NONE));
    }
}
