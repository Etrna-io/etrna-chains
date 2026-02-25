// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {RandomnessRouter} from "../src/randomness/RandomnessRouter.sol";

contract RandomnessRouterTest is Test {
    RandomnessRouter router;

    address owner = address(this);
    address fulfiller = address(0xF1);
    address alice = address(0xA1);
    address bob = address(0xB0);

    function setUp() public {
        router = new RandomnessRouter();
        router.setFulfiller(fulfiller, true);
    }

    // ── Fulfiller management ────────────────────────────────────

    function test_setFulfillerByOwner() public {
        router.setFulfiller(alice, true);
        assertTrue(router.fulfillers(alice));
        router.setFulfiller(alice, false);
        assertFalse(router.fulfillers(alice));
    }

    function test_setFulfillerRevertNonOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        router.setFulfiller(bob, true);
    }

    // ── Request ─────────────────────────────────────────────────

    function test_requestHappyPath() public {
        vm.prank(alice);
        bytes32 id = router.request(bytes32(uint256(1)));

        (address requester, uint64 createdAt, bool fulfilled, uint256 value, uint32 sourceMask) = router.requests(id);
        assertEq(requester, alice);
        assertEq(createdAt, uint64(block.timestamp));
        assertFalse(fulfilled);
        assertEq(value, 0);
        assertEq(sourceMask, 0);
    }

    function test_requestRevertZeroClientId() public {
        vm.prank(alice);
        vm.expectRevert("RandomnessRouter: requestId=0");
        router.request(bytes32(0));
    }

    function test_requestIncrementsNonce() public {
        vm.startPrank(alice);
        router.request(bytes32(uint256(1)));
        assertEq(router.nonces(alice), 1);
        router.request(bytes32(uint256(1))); // same clientRequestId but different nonce → different id
        assertEq(router.nonces(alice), 2);
        vm.stopPrank();
    }

    function test_sameClientIdDifferentNoncesYieldDifferentIds() public {
        vm.startPrank(alice);
        bytes32 id1 = router.request(bytes32(uint256(42)));
        bytes32 id2 = router.request(bytes32(uint256(42)));
        vm.stopPrank();
        assertTrue(id1 != id2);
    }

    function test_differentUsersCanUseSameClientId() public {
        vm.prank(alice);
        bytes32 idA = router.request(bytes32(uint256(99)));
        vm.prank(bob);
        bytes32 idB = router.request(bytes32(uint256(99)));
        assertTrue(idA != idB);
    }

    // ── Fulfill ─────────────────────────────────────────────────

    function test_fulfillHappyPath() public {
        vm.prank(alice);
        bytes32 id = router.request(bytes32(uint256(1)));

        vm.prank(fulfiller);
        router.fulfill(id, 123456, 0x05);

        (,, bool fulfilled, uint256 value, uint32 sourceMask) = router.requests(id);
        assertTrue(fulfilled);
        assertEq(value, 123456);
        assertEq(sourceMask, 0x05);
    }

    function test_fulfillRevertNotFulfiller() public {
        vm.prank(alice);
        bytes32 id = router.request(bytes32(uint256(1)));

        vm.prank(bob);
        vm.expectRevert("RandomnessRouter: not fulfiller");
        router.fulfill(id, 1, 1);
    }

    function test_fulfillRevertUnknown() public {
        vm.prank(fulfiller);
        vm.expectRevert("RandomnessRouter: unknown");
        router.fulfill(bytes32(uint256(0xdead)), 1, 1);
    }

    function test_fulfillRevertAlreadyDone() public {
        vm.prank(alice);
        bytes32 id = router.request(bytes32(uint256(1)));

        vm.startPrank(fulfiller);
        router.fulfill(id, 1, 1);
        vm.expectRevert("RandomnessRouter: done");
        router.fulfill(id, 2, 2);
        vm.stopPrank();
    }

    function test_fulfillEmitsEvent() public {
        vm.prank(alice);
        bytes32 id = router.request(bytes32(uint256(1)));

        vm.prank(fulfiller);
        vm.expectEmit(true, true, false, true);
        emit RandomnessRouter.Fulfilled(id, fulfiller, 999, 0x0F);
        router.fulfill(id, 999, 0x0F);
    }

    // ── Source mask semantics ───────────────────────────────────

    function test_sourceMaskBits() public {
        vm.prank(alice);
        bytes32 id = router.request(bytes32(uint256(7)));

        // e.g., VRF=1, QRNG=2, drand=4 → combined=7
        vm.prank(fulfiller);
        router.fulfill(id, 42, 7);

        (,,,, uint32 mask) = router.requests(id);
        assertEq(mask & 1, 1); // VRF present
        assertEq(mask & 2, 2); // QRNG present
        assertEq(mask & 4, 4); // drand present
    }
}
