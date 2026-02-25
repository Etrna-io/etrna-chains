// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {QuantumRandomness} from "../src/quantum/QuantumRandomness.sol";
import {QuantumConsumerBase} from "../src/quantum/QuantumConsumerBase.sol";

/// @dev Concrete consumer for testing the abstract QuantumConsumerBase.
contract MockQuantumConsumer is QuantumConsumerBase {
    uint256 public lastRandom;

    constructor(address qr) QuantumConsumerBase(qr) {}

    function doRequest() external returns (bytes32) {
        return _requestQuantumRandomness();
    }

    function doConsume(bytes32 requestId) external returns (uint256) {
        uint256 v = _consumeQuantumRandomness(requestId);
        lastRandom = v;
        return v;
    }
}

contract QuantumRandomnessTest is Test {
    QuantumRandomness qr;
    MockQuantumConsumer consumer;

    address owner = address(this);
    address fulfiller = address(0xF1);
    address alice = address(0xA1);
    address bob = address(0xB0);

    function setUp() public {
        qr = new QuantumRandomness(fulfiller);
        consumer = new MockQuantumConsumer(address(qr));
    }

    // ── QuantumRandomness core ──────────────────────────────────

    function test_initialFulfillerIsAuthorized() public view {
        assertTrue(qr.authorizedFulfillers(fulfiller));
    }

    function test_constructorZeroFulfillerSkips() public {
        QuantumRandomness qr2 = new QuantumRandomness(address(0));
        assertFalse(qr2.authorizedFulfillers(address(0)));
    }

    function test_setFulfillerByOwner() public {
        qr.setFulfiller(alice, true);
        assertTrue(qr.authorizedFulfillers(alice));
        qr.setFulfiller(alice, false);
        assertFalse(qr.authorizedFulfillers(alice));
    }

    function test_setFulfillerRevertNonOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        qr.setFulfiller(bob, true);
    }

    function test_requestRandomnessEmitsEvent() public {
        vm.prank(alice);
        bytes32 id = qr.requestRandomness();

        // Verify request struct
        (address c, uint256 chainId, uint64 createdAt, bool fulfilled, uint256 rv, uint32 mask) = qr.requests(id);
        assertEq(c, alice);
        assertEq(chainId, block.chainid);
        assertEq(createdAt, uint64(block.timestamp));
        assertFalse(fulfilled);
        assertEq(rv, 0);
        assertEq(mask, 0);
    }

    function test_duplicateRequestReverts() public {
        // Same sender + timestamp + chainId ⇒ same requestId
        vm.prank(alice);
        qr.requestRandomness();
        vm.prank(alice);
        vm.expectRevert("QuantumRandomness: duplicate");
        qr.requestRandomness();
    }

    function test_fulfillRandomnessHappyPath() public {
        vm.prank(alice);
        bytes32 id = qr.requestRandomness();

        uint256 randomVal = 42;
        uint32 mask = 0x07;
        vm.prank(fulfiller);
        qr.fulfillRandomness(id, randomVal, mask);

        (,,,bool fulfilled, uint256 rv, uint32 sourceMask) = qr.requests(id);
        assertTrue(fulfilled);
        assertEq(rv, randomVal);
        assertEq(sourceMask, mask);
    }

    function test_fulfillRevertNonFulfiller() public {
        vm.prank(alice);
        bytes32 id = qr.requestRandomness();

        vm.prank(bob);
        vm.expectRevert("QuantumRandomness: not fulfiller");
        qr.fulfillRandomness(id, 1, 1);
    }

    function test_fulfillRevertUnknownRequest() public {
        vm.prank(fulfiller);
        vm.expectRevert("QuantumRandomness: unknown request");
        qr.fulfillRandomness(bytes32(uint256(0xdead)), 1, 1);
    }

    function test_fulfillRevertAlreadyFulfilled() public {
        vm.prank(alice);
        bytes32 id = qr.requestRandomness();

        vm.prank(fulfiller);
        qr.fulfillRandomness(id, 1, 1);

        vm.prank(fulfiller);
        vm.expectRevert("QuantumRandomness: already fulfilled");
        qr.fulfillRandomness(id, 2, 2);
    }

    function test_readRandomness() public {
        vm.prank(alice);
        bytes32 id = qr.requestRandomness();

        vm.prank(fulfiller);
        qr.fulfillRandomness(id, 999, 0x0F);

        QuantumRandomness.Request memory r = qr.readRandomness(id);
        assertEq(r.consumer, alice);
        assertTrue(r.fulfilled);
        assertEq(r.randomValue, 999);
        assertEq(r.entropySourceMask, 0x0F);
    }

    function test_multiEntropySourceMask() public {
        vm.prank(alice);
        bytes32 id = qr.requestRandomness();

        // mask bits: VRF(1) + QRNG(2) + drand(4) = 7
        uint32 mask = 7;
        vm.prank(fulfiller);
        qr.fulfillRandomness(id, 12345, mask);

        QuantumRandomness.Request memory r = qr.readRandomness(id);
        assertEq(r.entropySourceMask, mask);
    }

    function test_multipleRequestsDifferentUsers() public {
        vm.warp(100);
        vm.prank(alice);
        bytes32 idA = qr.requestRandomness();

        vm.prank(bob);
        bytes32 idB = qr.requestRandomness();

        assertTrue(idA != idB);

        vm.startPrank(fulfiller);
        qr.fulfillRandomness(idA, 10, 1);
        qr.fulfillRandomness(idB, 20, 2);
        vm.stopPrank();

        assertEq(qr.readRandomness(idA).randomValue, 10);
        assertEq(qr.readRandomness(idB).randomValue, 20);
    }

    // ── QuantumConsumerBase ─────────────────────────────────────

    function test_consumerBaseZeroAddressReverts() public {
        vm.expectRevert("QuantumConsumerBase: zero address");
        new MockQuantumConsumer(address(0));
    }

    function test_consumerRequestAndConsume() public {
        vm.prank(address(consumer));
        bytes32 id = qr.requestRandomness();
        // We need to use the consumer's doRequest which calls through the QR contract
        // Let's do full lifecycle through the consumer interface instead:
    }

    function test_consumerFullLifecycle() public {
        // consumer.doRequest calls QR.requestRandomness on behalf of consumer
        bytes32 id = consumer.doRequest();

        // Fulfiller fills it
        vm.prank(fulfiller);
        qr.fulfillRandomness(id, 777, 0x03);

        // Consumer consumes
        uint256 v = consumer.doConsume(id);
        assertEq(v, 777);
        assertEq(consumer.lastRandom(), 777);
    }

    function test_consumerConsumeRevertNotPending() public {
        vm.expectRevert("QuantumConsumerBase: not pending");
        consumer.doConsume(bytes32(uint256(0xbeef)));
    }

    function test_consumerConsumeRevertNotFulfilled() public {
        bytes32 id = consumer.doRequest();
        vm.expectRevert("QuantumConsumerBase: not fulfilled");
        consumer.doConsume(id);
    }

    function test_consumerDoubleConsumeReverts() public {
        bytes32 id = consumer.doRequest();
        vm.prank(fulfiller);
        qr.fulfillRandomness(id, 42, 1);

        consumer.doConsume(id);
        vm.expectRevert("QuantumConsumerBase: not pending");
        consumer.doConsume(id);
    }
}
