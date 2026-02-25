// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/seaport/EtrnaZone.sol";

// ── Mock IdentityGuard ────────────────────────────────────────
contract MockZoneGuard {
    bool public returnValue = true;
    bytes32 public lastProofType;
    bytes public lastProof;
    bytes32 public lastNullifier;

    function setReturn(bool v) external {
        returnValue = v;
    }

    function requireProof(bytes32 proofType, bytes calldata proof, bytes32 nullifier) external view returns (bool) {
        // Can't set state in view, but we can still return
        // Store params via a workaround for verification in tests is not possible in view;
        // we simply return the configured value.
        proofType; proof; nullifier;
        return returnValue;
    }
}

// ── Failing guard for revert testing ──────────────────────────
contract RevertingGuard {
    function requireProof(bytes32, bytes calldata, bytes32) external pure returns (bool) {
        revert("proof invalid");
    }
}

contract EtrnaZoneTest is Test {
    EtrnaZone public zone;
    MockZoneGuard public guard;

    bytes32 constant PROOF_TYPE = keccak256("sybil-resistance");
    address alice = address(0xA11CE);
    address bob = address(0xB0B);

    function setUp() public {
        guard = new MockZoneGuard();
        zone = new EtrnaZone(address(guard), PROOF_TYPE);
    }

    // ─── Constructor ──────────────────────────────────────────

    function test_Constructor() public view {
        assertEq(zone.identityGuard(), address(guard));
        assertEq(zone.proofType(), PROOF_TYPE);
    }

    function test_RevertConstructor_ZeroGuard() public {
        vm.expectRevert("EtrnaZone: guard=0");
        new EtrnaZone(address(0), PROOF_TYPE);
    }

    function test_Constructor_ZeroProofType() public {
        // Zero proof type is valid (just a bytes32)
        EtrnaZone z = new EtrnaZone(address(guard), bytes32(0));
        assertEq(z.proofType(), bytes32(0));
    }

    // ─── validate — success ───────────────────────────────────

    function test_Validate_ReturnsTrue() public {
        guard.setReturn(true);

        bytes memory proof = abi.encode("valid-proof-data");
        bytes32 nullifier = keccak256("nullifier-1");

        bool ok = zone.validate(alice, bob, proof, nullifier);
        assertTrue(ok);
    }

    function test_Validate_ReturnsFalse() public {
        guard.setReturn(false);

        bytes memory proof = abi.encode("invalid-proof");
        bytes32 nullifier = keccak256("nullifier-2");

        bool ok = zone.validate(alice, bob, proof, nullifier);
        assertFalse(ok);
    }

    function test_Validate_EmptyProof() public {
        guard.setReturn(true);

        bool ok = zone.validate(alice, bob, hex"", bytes32(0));
        assertTrue(ok);
    }

    function test_Validate_IsViewFunction() public view {
        // Calling validate should not modify state (it's a view function)
        bool ok = zone.validate(alice, bob, hex"", bytes32(0));
        assertTrue(ok);
    }

    function test_Validate_DifferentFulfillerOfferer() public {
        guard.setReturn(true);

        // validate works regardless of who the fulfiller/offerer are
        bool ok1 = zone.validate(alice, bob, hex"", bytes32(0));
        bool ok2 = zone.validate(bob, alice, hex"", bytes32(0));
        bool ok3 = zone.validate(address(0), address(0), hex"", bytes32(0));

        assertTrue(ok1);
        assertTrue(ok2);
        assertTrue(ok3);
    }

    // ─── validate — guard reverts ─────────────────────────────

    function test_Validate_GuardReverts() public {
        RevertingGuard badGuard = new RevertingGuard();
        EtrnaZone zoneWithBadGuard = new EtrnaZone(address(badGuard), PROOF_TYPE);

        vm.expectRevert("proof invalid");
        zoneWithBadGuard.validate(alice, bob, hex"", bytes32(0));
    }

    // ─── Immutability ─────────────────────────────────────────

    function test_Immutable_IdentityGuard() public view {
        // identityGuard and proofType are immutable — set at construction
        assertEq(zone.identityGuard(), address(guard));
        assertEq(zone.proofType(), PROOF_TYPE);
    }

    // ─── Different proof types ────────────────────────────────

    function test_DifferentProofTypes() public {
        bytes32 pt1 = keccak256("kyc");
        bytes32 pt2 = keccak256("captcha");

        EtrnaZone zone1 = new EtrnaZone(address(guard), pt1);
        EtrnaZone zone2 = new EtrnaZone(address(guard), pt2);

        assertEq(zone1.proofType(), pt1);
        assertEq(zone2.proofType(), pt2);

        // Both should validate successfully since guard returns true
        assertTrue(zone1.validate(alice, bob, hex"", bytes32(0)));
        assertTrue(zone2.validate(alice, bob, hex"", bytes32(0)));
    }
}
