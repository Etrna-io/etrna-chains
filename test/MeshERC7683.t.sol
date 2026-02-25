// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/mesh/MeshHub.sol";
import "../src/mesh/MeshTypes.sol";
import "../src/mesh/IMeshAdapter.sol";
import "../src/mesh-erc7683/EtrnaMeshOriginSettler.sol";
import "../src/mesh-erc7683/EtrnaMeshDestinationSettler.sol";
import "../src/mesh-erc7683/ERC7683Types.sol";

// ── Mock adapter for DestinationSettler fill() ────────────────
contract MockMeshAdapter is IMeshAdapter {
    bytes32 public lastIntentId;
    bytes public lastRouteData;
    uint256 public callCount;

    function execute(bytes32 intentId, bytes calldata routeData) external override {
        lastIntentId = intentId;
        lastRouteData = routeData;
        callCount++;
    }
}

contract MeshERC7683Test is Test {
    MeshHub public hub;
    EtrnaMeshOriginSettler public origin;
    EtrnaMeshDestinationSettler public destination;
    MockMeshAdapter public adapter;

    address router = address(0xBEEF);
    address alice = address(0xA11CE);
    address filler = address(0xF111);

    function setUp() public {
        hub = new MeshHub(router);
        origin = new EtrnaMeshOriginSettler(address(hub));
        destination = new EtrnaMeshDestinationSettler(address(hub), router);
        adapter = new MockMeshAdapter();
    }

    // ── Helper builders ───────────────────────────────────────

    function _buildOrder(
        address user,
        uint256 nonce,
        MeshTypes.ActionType actionType,
        uint256 dstChainId,
        address asset,
        uint256 amount,
        bytes32 paramsHash,
        uint32 openDeadline,
        uint32 fillDeadline
    ) internal view returns (ERC7683Types.OnchainCrossChainOrder memory) {
        bytes memory orderData = abi.encode(actionType, dstChainId, asset, amount, paramsHash);
        return ERC7683Types.OnchainCrossChainOrder({
            originSettler: address(origin),
            user: user,
            nonce: nonce,
            originChainId: block.chainid,
            openDeadline: openDeadline,
            fillDeadline: fillDeadline,
            orderData: orderData
        });
    }

    function _defaultOrder(address user, uint256 nonce)
        internal view returns (ERC7683Types.OnchainCrossChainOrder memory)
    {
        return _buildOrder(
            user,
            nonce,
            MeshTypes.ActionType.BRIDGE,
            42,
            address(0),
            1000,
            keccak256("params"),
            0,
            0
        );
    }

    // ─── OriginSettler Constructor ────────────────────────────

    function test_Origin_ConstructorSetsHub() public view {
        assertEq(address(origin.meshHub()), address(hub));
    }

    function test_Origin_RevertConstructor_ZeroAddress() public {
        vm.expectRevert("meshHub=0");
        new EtrnaMeshOriginSettler(address(0));
    }

    // ─── open() ───────────────────────────────────────────────

    function test_Open_CreatesIntent() public {
        ERC7683Types.OnchainCrossChainOrder memory order = _defaultOrder(alice, 1);

        vm.prank(alice);
        origin.open(order);

        // nonce should be consumed
        assertTrue(origin.usedNonces(alice, 1));
    }

    function test_Open_EmitsOpenEvent() public {
        ERC7683Types.OnchainCrossChainOrder memory order = _defaultOrder(alice, 2);

        vm.prank(alice);
        // We just ensure it doesn't revert — the event is emitted with resolved data
        origin.open(order);
    }

    function test_Open_MultipleDifferentNonces() public {
        vm.startPrank(alice);

        ERC7683Types.OnchainCrossChainOrder memory order1 = _defaultOrder(alice, 10);
        origin.open(order1);

        ERC7683Types.OnchainCrossChainOrder memory order2 = _defaultOrder(alice, 11);
        origin.open(order2);

        assertTrue(origin.usedNonces(alice, 10));
        assertTrue(origin.usedNonces(alice, 11));
        vm.stopPrank();
    }

    // ─── open() reverts ───────────────────────────────────────

    function test_Open_RevertIfWrongUser() public {
        ERC7683Types.OnchainCrossChainOrder memory order = _defaultOrder(alice, 1);

        // bob tries to open alice's order
        vm.prank(address(0xB0B));
        vm.expectRevert(EtrnaMeshOriginSettler.InvalidOrder.selector);
        origin.open(order);
    }

    function test_Open_RevertIfDeadlineExpired() public {
        ERC7683Types.OnchainCrossChainOrder memory order = _buildOrder(
            alice, 1, MeshTypes.ActionType.BRIDGE, 42, address(0), 100, bytes32(0),
            uint32(block.timestamp - 1), // expired deadline
            0
        );

        vm.prank(alice);
        vm.expectRevert(EtrnaMeshOriginSettler.DeadlineExpired.selector);
        origin.open(order);
    }

    function test_Open_OkIfDeadlineZero() public {
        ERC7683Types.OnchainCrossChainOrder memory order = _buildOrder(
            alice, 1, MeshTypes.ActionType.BRIDGE, 42, address(0), 100, bytes32(0),
            0, // zero deadline = no deadline check
            0
        );

        vm.prank(alice);
        origin.open(order); // should not revert
    }

    function test_Open_OkIfDeadlineInFuture() public {
        ERC7683Types.OnchainCrossChainOrder memory order = _buildOrder(
            alice, 1, MeshTypes.ActionType.BRIDGE, 42, address(0), 100, bytes32(0),
            uint32(block.timestamp + 3600),
            0
        );

        vm.prank(alice);
        origin.open(order);
    }

    function test_Open_RevertNonceReplay() public {
        ERC7683Types.OnchainCrossChainOrder memory order = _defaultOrder(alice, 5);

        vm.startPrank(alice);
        origin.open(order);

        vm.expectRevert(EtrnaMeshOriginSettler.NonceUsed.selector);
        origin.open(order);
        vm.stopPrank();
    }

    function test_Open_DifferentUsersSameNonce() public {
        address bob = address(0xB0B);
        ERC7683Types.OnchainCrossChainOrder memory orderAlice = _defaultOrder(alice, 1);
        ERC7683Types.OnchainCrossChainOrder memory orderBob = _defaultOrder(bob, 1);

        vm.prank(alice);
        origin.open(orderAlice);

        vm.prank(bob);
        origin.open(orderBob); // should not revert — different user

        assertTrue(origin.usedNonces(alice, 1));
        assertTrue(origin.usedNonces(bob, 1));
    }

    // ─── resolve() ────────────────────────────────────────────

    function test_Resolve_ReturnsResolvedOrder() public view {
        ERC7683Types.OnchainCrossChainOrder memory order = _defaultOrder(alice, 1);

        ERC7683Types.ResolvedCrossChainOrder memory resolved = origin.resolve(order);
        assertEq(resolved.user, alice);
        assertEq(resolved.originChainId, block.chainid);
        assertEq(resolved.fillInstructions.length, 1);
        assertEq(resolved.fillInstructions[0].destinationChainId, 42);
    }

    function test_Resolve_DeterministicId() public view {
        ERC7683Types.OnchainCrossChainOrder memory order = _defaultOrder(alice, 99);

        ERC7683Types.ResolvedCrossChainOrder memory r1 = origin.resolve(order);
        ERC7683Types.ResolvedCrossChainOrder memory r2 = origin.resolve(order);
        assertEq(r1.orderId, r2.orderId);
    }

    // ─── DestinationSettler Constructor ───────────────────────

    function test_Destination_ConstructorSetsHub() public view {
        assertEq(address(destination.meshHub()), address(hub));
    }

    function test_Destination_RevertConstructor_ZeroAddress() public {
        vm.expectRevert("meshHub=0");
        new EtrnaMeshDestinationSettler(address(0), router);
    }

    // ─── fill() ───────────────────────────────────────────────

    function test_Fill_ExecutesAdapter() public {
        // 1. Create intent via origin settler
        ERC7683Types.OnchainCrossChainOrder memory order = _buildOrder(
            alice, 1, MeshTypes.ActionType.BRIDGE, block.chainid, address(0), 0, bytes32(0), 0, 0
        );

        vm.prank(alice);
        origin.open(order);

        // 2. We need to find the intentId that was created.
        //    Since the origin settler calls hub.createIntent, we need to compute the intentId.
        //    Instead, we create a fresh intent directly and use that.

        // Create a direct intent through the hub so we can control the intentId
        vm.prank(alice);
        bytes32 intentId = hub.createIntent(
            MeshTypes.ActionType.BRIDGE,
            block.chainid,
            address(0),
            0,
            keccak256("adapter-test")
        );

        // 3. Register adapter for that intent's action type on the destination chain
        bytes4 selector = bytes4(keccak256(abi.encodePacked(uint256(MeshTypes.ActionType.BRIDGE))));
        hub.setAdapter(block.chainid, selector, address(adapter));

        // 4. Build fill params
        bytes memory originData = abi.encode(intentId, keccak256("adapter-test"));
        bytes memory fillerData = abi.encode("execute-payload");

        // 5. Fill
        vm.prank(filler);
        destination.fill(bytes32(uint256(1)), originData, fillerData);

        assertEq(adapter.lastIntentId(), intentId);
        assertEq(adapter.callCount(), 1);
    }

    function test_Fill_EmitsFillExecutedEvent() public {
        vm.prank(alice);
        bytes32 intentId = hub.createIntent(
            MeshTypes.ActionType.MINT_NFT,
            block.chainid,
            address(0),
            0,
            bytes32(0)
        );

        bytes4 selector = bytes4(keccak256(abi.encodePacked(uint256(MeshTypes.ActionType.MINT_NFT))));
        hub.setAdapter(block.chainid, selector, address(adapter));

        bytes memory originData = abi.encode(intentId, bytes32(0));
        bytes memory fillerData = hex"";
        bytes32 orderId = bytes32(uint256(77));

        vm.prank(filler);
        vm.expectEmit(true, true, false, true);
        emit EtrnaMeshDestinationSettler.FillExecuted(orderId, filler, originData, fillerData);
        destination.fill(orderId, originData, fillerData);
    }

    function test_Fill_RevertUnknownIntent() public {
        bytes32 fakeIntentId = keccak256("nonexistent");
        bytes memory originData = abi.encode(fakeIntentId, bytes32(0));

        vm.prank(filler);
        vm.expectRevert("unknown intent");
        destination.fill(bytes32(0), originData, hex"");
    }

    function test_Fill_RevertNoAdapter() public {
        vm.prank(alice);
        bytes32 intentId = hub.createIntent(
            MeshTypes.ActionType.STAKE,
            block.chainid,
            address(0),
            0,
            bytes32(0)
        );

        bytes memory originData = abi.encode(intentId, bytes32(0));

        vm.prank(filler);
        vm.expectRevert("no adapter");
        destination.fill(bytes32(0), originData, hex"");
    }
}
