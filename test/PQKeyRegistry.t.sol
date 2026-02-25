// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {PQKeyRegistry} from "../src/pq/PQKeyRegistry.sol";

contract PQKeyRegistryTest is Test {
    PQKeyRegistry registry;

    address alice = address(0xA1);
    address bob = address(0xB0);

    bytes32 constant DILITHIUM = keccak256("dilithium3");
    bytes32 constant KYBER = keccak256("kyber768");

    bytes constant SAMPLE_KEY = hex"aabbccdd0011223344556677";
    bytes constant SAMPLE_KEY2 = hex"ff00ff00ff00ff00";

    function setUp() public {
        registry = new PQKeyRegistry();
    }

    // ── register ────────────────────────────────────────────────

    function test_registerAndRetrieve() public {
        vm.prank(alice);
        registry.register(DILITHIUM, SAMPLE_KEY);

        bytes memory k = registry.keyOf(alice, DILITHIUM);
        assertEq(k, SAMPLE_KEY);
    }

    function test_registerEmptyKeyReverts() public {
        vm.prank(alice);
        vm.expectRevert("PQKeyRegistry: empty");
        registry.register(DILITHIUM, "");
    }

    function test_registerOverwritesExistingKey() public {
        vm.startPrank(alice);
        registry.register(DILITHIUM, SAMPLE_KEY);
        registry.register(DILITHIUM, SAMPLE_KEY2);
        vm.stopPrank();

        bytes memory k = registry.keyOf(alice, DILITHIUM);
        assertEq(k, SAMPLE_KEY2);
    }

    function test_registerMultipleSchemes() public {
        vm.startPrank(alice);
        registry.register(DILITHIUM, SAMPLE_KEY);
        registry.register(KYBER, SAMPLE_KEY2);
        vm.stopPrank();

        assertEq(registry.keyOf(alice, DILITHIUM), SAMPLE_KEY);
        assertEq(registry.keyOf(alice, KYBER), SAMPLE_KEY2);
    }

    function test_registerEmitsEvent() public {
        vm.prank(alice);
        vm.expectEmit(true, true, false, true);
        emit PQKeyRegistry.PQKeyRegistered(alice, DILITHIUM, SAMPLE_KEY);
        registry.register(DILITHIUM, SAMPLE_KEY);
    }

    function test_registerDifferentUsers() public {
        vm.prank(alice);
        registry.register(DILITHIUM, SAMPLE_KEY);
        vm.prank(bob);
        registry.register(DILITHIUM, SAMPLE_KEY2);

        assertEq(registry.keyOf(alice, DILITHIUM), SAMPLE_KEY);
        assertEq(registry.keyOf(bob, DILITHIUM), SAMPLE_KEY2);
    }

    // ── revoke ──────────────────────────────────────────────────

    function test_revokeRemovesKey() public {
        vm.startPrank(alice);
        registry.register(DILITHIUM, SAMPLE_KEY);
        registry.revoke(DILITHIUM);
        vm.stopPrank();

        bytes memory k = registry.keyOf(alice, DILITHIUM);
        assertEq(k.length, 0);
    }

    function test_revokeEmitsEvent() public {
        vm.startPrank(alice);
        registry.register(DILITHIUM, SAMPLE_KEY);
        vm.expectEmit(true, true, false, false);
        emit PQKeyRegistry.PQKeyRevoked(alice, DILITHIUM);
        registry.revoke(DILITHIUM);
        vm.stopPrank();
    }

    function test_revokeNonExistentKeyNoRevert() public {
        // Revoking a key that was never registered should not revert
        vm.prank(alice);
        registry.revoke(DILITHIUM); // should succeed silently
    }

    function test_revokeDoesNotAffectOtherSchemes() public {
        vm.startPrank(alice);
        registry.register(DILITHIUM, SAMPLE_KEY);
        registry.register(KYBER, SAMPLE_KEY2);
        registry.revoke(DILITHIUM);
        vm.stopPrank();

        assertEq(registry.keyOf(alice, DILITHIUM).length, 0);
        assertEq(registry.keyOf(alice, KYBER), SAMPLE_KEY2);
    }

    function test_revokeDoesNotAffectOtherUsers() public {
        vm.prank(alice);
        registry.register(DILITHIUM, SAMPLE_KEY);
        vm.prank(bob);
        registry.register(DILITHIUM, SAMPLE_KEY2);

        vm.prank(alice);
        registry.revoke(DILITHIUM);

        assertEq(registry.keyOf(alice, DILITHIUM).length, 0);
        assertEq(registry.keyOf(bob, DILITHIUM), SAMPLE_KEY2);
    }

    // ── keyOf ────────────────────────────────────────────────────

    function test_keyOfReturnsEmptyForUnknown() public view {
        bytes memory k = registry.keyOf(alice, DILITHIUM);
        assertEq(k.length, 0);
    }

    function test_keyOfUnknownAddress() public view {
        bytes memory k = registry.keyOf(address(0xDEAD), DILITHIUM);
        assertEq(k.length, 0);
    }

    // ── Re-register after revoke ────────────────────────────────

    function test_reRegisterAfterRevoke() public {
        vm.startPrank(alice);
        registry.register(DILITHIUM, SAMPLE_KEY);
        registry.revoke(DILITHIUM);
        registry.register(DILITHIUM, SAMPLE_KEY2);
        vm.stopPrank();

        assertEq(registry.keyOf(alice, DILITHIUM), SAMPLE_KEY2);
    }
}
