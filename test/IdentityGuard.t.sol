// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/identity/IdentityGuard.sol";
import "../src/identity/IdentityProviderRegistry.sol";

contract IdentityGuardTest is Test {
    IdentityGuard public guard;
    IdentityProviderRegistry public registry;

    address admin = address(0xA);
    address user1 = address(0xB);
    address user2 = address(0xC);

    bytes32 constant PROOF_TYPE_ZK = keccak256("ZK_PROOF");
    bytes32 constant PROOF_TYPE_EUDI = keccak256("EUDI");
    bytes32 constant NULLIFIER_A = keccak256("nullifier_a");
    bytes32 constant NULLIFIER_B = keccak256("nullifier_b");

    function setUp() public {
        vm.prank(admin);
        registry = new IdentityProviderRegistry(admin);
        guard = new IdentityGuard(address(registry));
    }

    // ─── Constructor ─────────────────────────────────────────

    function test_ConstructorSetsRegistry() public view {
        assertEq(address(guard.registry()), address(registry));
    }

    // ─── requireProof (v1 stub) ──────────────────────────────

    function test_RequireProofAlwaysReturnsTrue() public view {
        bool result = guard.requireProof(PROOF_TYPE_ZK, "", NULLIFIER_A);
        assertTrue(result);
    }

    function test_RequireProofWithArbitraryInputs() public view {
        assertTrue(guard.requireProof(bytes32(0), "", bytes32(0)));
        assertTrue(guard.requireProof(PROOF_TYPE_EUDI, hex"deadbeef", NULLIFIER_B));
        assertTrue(guard.requireProof(keccak256("random"), hex"1234", keccak256("other")));
    }

    function test_RequireProofIsView() public view {
        // Verify it doesn't change state — call multiple times
        guard.requireProof(PROOF_TYPE_ZK, "", NULLIFIER_A);
        guard.requireProof(PROOF_TYPE_ZK, "", NULLIFIER_A);
        // No revert means no state change (no replay protection in view)
        assertFalse(guard.nullifierUsed(PROOF_TYPE_ZK, NULLIFIER_A));
    }

    // ─── consumeProof ────────────────────────────────────────

    function test_ConsumeProofSucceeds() public {
        vm.prank(user1);
        guard.consumeProof(PROOF_TYPE_ZK, NULLIFIER_A);

        assertTrue(guard.nullifierUsed(PROOF_TYPE_ZK, NULLIFIER_A));
    }

    function test_ConsumeProofEmitsEvent() public {
        vm.expectEmit(true, true, true, true);
        emit IdentityGuard.ProofConsumed(PROOF_TYPE_ZK, NULLIFIER_A, user1);

        vm.prank(user1);
        guard.consumeProof(PROOF_TYPE_ZK, NULLIFIER_A);
    }

    function test_ConsumeProofRevertReplay() public {
        vm.prank(user1);
        guard.consumeProof(PROOF_TYPE_ZK, NULLIFIER_A);

        vm.prank(user1);
        vm.expectRevert("IdentityGuard: replay");
        guard.consumeProof(PROOF_TYPE_ZK, NULLIFIER_A);
    }

    function test_ConsumeProofRevertReplayDifferentCaller() public {
        vm.prank(user1);
        guard.consumeProof(PROOF_TYPE_ZK, NULLIFIER_A);

        // Same proofType + nullifier from a different caller still replays
        vm.prank(user2);
        vm.expectRevert("IdentityGuard: replay");
        guard.consumeProof(PROOF_TYPE_ZK, NULLIFIER_A);
    }

    function test_ConsumeProofDifferentNullifiersSameType() public {
        vm.prank(user1);
        guard.consumeProof(PROOF_TYPE_ZK, NULLIFIER_A);

        vm.prank(user1);
        guard.consumeProof(PROOF_TYPE_ZK, NULLIFIER_B);

        assertTrue(guard.nullifierUsed(PROOF_TYPE_ZK, NULLIFIER_A));
        assertTrue(guard.nullifierUsed(PROOF_TYPE_ZK, NULLIFIER_B));
    }

    function test_ConsumeProofSameNullifierDifferentTypes() public {
        vm.prank(user1);
        guard.consumeProof(PROOF_TYPE_ZK, NULLIFIER_A);

        vm.prank(user1);
        guard.consumeProof(PROOF_TYPE_EUDI, NULLIFIER_A);

        assertTrue(guard.nullifierUsed(PROOF_TYPE_ZK, NULLIFIER_A));
        assertTrue(guard.nullifierUsed(PROOF_TYPE_EUDI, NULLIFIER_A));
    }

    function test_NullifierUsedReturnsFalseInitially() public view {
        assertFalse(guard.nullifierUsed(PROOF_TYPE_ZK, NULLIFIER_A));
        assertFalse(guard.nullifierUsed(PROOF_TYPE_EUDI, NULLIFIER_B));
    }

    // ─── Anyone can consume proofs ──────────────────────────

    function test_AnyoneCanConsumeProof() public {
        address[] memory callers = new address[](3);
        callers[0] = user1;
        callers[1] = user2;
        callers[2] = admin;

        for (uint256 i = 0; i < callers.length; i++) {
            bytes32 nullifier = keccak256(abi.encode("unique", i));
            vm.prank(callers[i]);
            guard.consumeProof(PROOF_TYPE_ZK, nullifier);
            assertTrue(guard.nullifierUsed(PROOF_TYPE_ZK, nullifier));
        }
    }

    // ─── Multiple proof types isolation ─────────────────────

    function test_ProofTypeIsolation() public {
        bytes32 type1 = keccak256("TYPE_1");
        bytes32 type2 = keccak256("TYPE_2");
        bytes32 type3 = keccak256("TYPE_3");

        vm.startPrank(user1);
        guard.consumeProof(type1, NULLIFIER_A);
        guard.consumeProof(type2, NULLIFIER_A);
        guard.consumeProof(type3, NULLIFIER_A);
        vm.stopPrank();

        assertTrue(guard.nullifierUsed(type1, NULLIFIER_A));
        assertTrue(guard.nullifierUsed(type2, NULLIFIER_A));
        assertTrue(guard.nullifierUsed(type3, NULLIFIER_A));

        // Each type's nullifier is independent
        assertFalse(guard.nullifierUsed(type1, NULLIFIER_B));
    }
}
