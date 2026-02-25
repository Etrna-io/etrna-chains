// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {FusionRegistry} from "../src/fusion/FusionRegistry.sol";

contract FusionRegistryTest is Test {
    FusionRegistry fusion;

    address admin = address(this);
    address relayer = address(0xEE01);
    address validator = address(0xEE02);
    address alice = address(0xA1);
    address bob = address(0xB0);

    bytes32 constant UEF_RULES = keccak256("rules-v1");
    bytes32 constant UEF_ARTIFACT = keccak256("artifact-v1");
    bytes32 constant PARAMS_HASH = keccak256("params-v1");
    bytes32 constant VERIFIER_REF = keccak256("eval-batch-1");

    function setUp() public {
        fusion = new FusionRegistry(admin);
        fusion.grantRelayer(relayer);
        fusion.grantValidator(validator);
    }

    // ── Constructor / Roles ─────────────────────────────────────

    function test_constructorGrantsAdminRoles() public view {
        assertTrue(fusion.hasRole(fusion.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(fusion.hasRole(fusion.ADMIN_ROLE(), admin));
    }

    function test_constructorRevertZeroAddress() public {
        vm.expectRevert("FusionRegistry: admin=0");
        new FusionRegistry(address(0));
    }

    function test_grantAndRevokeRelayer() public {
        fusion.grantRelayer(alice);
        assertTrue(fusion.hasRole(fusion.RELAYER_ROLE(), alice));
        fusion.revokeRelayer(alice);
        assertFalse(fusion.hasRole(fusion.RELAYER_ROLE(), alice));
    }

    function test_grantAndRevokeValidator() public {
        fusion.grantValidator(alice);
        assertTrue(fusion.hasRole(fusion.VALIDATOR_ROLE(), alice));
        fusion.revokeValidator(alice);
        assertFalse(fusion.hasRole(fusion.VALIDATOR_ROLE(), alice));
    }

    function test_grantRelayerRevertNonAdmin() public {
        vm.prank(alice);
        vm.expectRevert();
        fusion.grantRelayer(bob);
    }

    function test_grantValidatorRevertNonAdmin() public {
        vm.prank(alice);
        vm.expectRevert();
        fusion.grantValidator(bob);
    }

    // ── createChallenge ─────────────────────────────────────────

    function test_createChallengeHappyPath() public {
        uint256 id = fusion.createChallenge(UEF_RULES, "ipfs://meta");
        assertEq(id, 1);

        (address creator, bytes32 rulesHash, string memory uri, uint64 createdAt, bool active) = fusion.challenges(id);
        assertEq(creator, admin);
        assertEq(rulesHash, UEF_RULES);
        assertEq(uri, "ipfs://meta");
        assertEq(createdAt, uint64(block.timestamp));
        assertTrue(active);
    }

    function test_createChallengeIncrementsId() public {
        uint256 id1 = fusion.createChallenge(UEF_RULES, "a");
        uint256 id2 = fusion.createChallenge(keccak256("rules2"), "b");
        assertEq(id1, 1);
        assertEq(id2, 2);
    }

    function test_createChallengeRevertZeroRulesHash() public {
        vm.expectRevert("FusionRegistry: uefRulesHash=0");
        fusion.createChallenge(bytes32(0), "uri");
    }

    function test_createChallengeFromAnyAddress() public {
        // createChallenge is not role-gated
        vm.prank(alice);
        uint256 id = fusion.createChallenge(UEF_RULES, "from-alice");
        (address creator,,,,) = fusion.challenges(id);
        assertEq(creator, alice);
    }

    function test_createChallengeEmitsEvent() public {
        vm.expectEmit(true, true, true, true);
        emit FusionRegistry.ChallengeCreated(1, admin, UEF_RULES, "ipfs://test");
        fusion.createChallenge(UEF_RULES, "ipfs://test");
    }

    // ── setChallengeActive ──────────────────────────────────────

    function test_setChallengeActive() public {
        uint256 id = fusion.createChallenge(UEF_RULES, "x");
        fusion.setChallengeActive(id, false);
        (,,,, bool active) = fusion.challenges(id);
        assertFalse(active);

        fusion.setChallengeActive(id, true);
        (,,,, active) = fusion.challenges(id);
        assertTrue(active);
    }

    function test_setChallengeActiveRevertNonAdmin() public {
        uint256 id = fusion.createChallenge(UEF_RULES, "x");
        vm.prank(alice);
        vm.expectRevert();
        fusion.setChallengeActive(id, false);
    }

    function test_setChallengeActiveRevertNonExistent() public {
        vm.expectRevert("FusionRegistry: no challenge");
        fusion.setChallengeActive(999, false);
    }

    // ── submit ──────────────────────────────────────────────────

    function test_submitHappyPath() public {
        uint256 cid = fusion.createChallenge(UEF_RULES, "uri");

        vm.prank(alice);
        uint256 sid = fusion.submit(cid, UEF_ARTIFACT, PARAMS_HASH);
        assertEq(sid, 1);

        (
            uint256 challengeId,
            address submitter,
            bytes32 artifactHash,
            bytes32 paramsHash,
            uint64 createdAt,
            bool verified,
            uint16 scoreBps,
            bytes32 verifierRef
        ) = fusion.submissions(sid);

        assertEq(challengeId, cid);
        assertEq(submitter, alice);
        assertEq(artifactHash, UEF_ARTIFACT);
        assertEq(paramsHash, PARAMS_HASH);
        assertEq(createdAt, uint64(block.timestamp));
        assertFalse(verified);
        assertEq(scoreBps, 0);
        assertEq(verifierRef, bytes32(0));
    }

    function test_submitIncrementsId() public {
        uint256 cid = fusion.createChallenge(UEF_RULES, "uri");
        vm.startPrank(alice);
        uint256 s1 = fusion.submit(cid, UEF_ARTIFACT, PARAMS_HASH);
        uint256 s2 = fusion.submit(cid, keccak256("art2"), keccak256("p2"));
        vm.stopPrank();
        assertEq(s1, 1);
        assertEq(s2, 2);
    }

    function test_submitRevertNonExistentChallenge() public {
        vm.prank(alice);
        vm.expectRevert("FusionRegistry: no challenge");
        fusion.submit(999, UEF_ARTIFACT, PARAMS_HASH);
    }

    function test_submitRevertInactiveChallenge() public {
        uint256 cid = fusion.createChallenge(UEF_RULES, "uri");
        fusion.setChallengeActive(cid, false);

        vm.prank(alice);
        vm.expectRevert("FusionRegistry: inactive challenge");
        fusion.submit(cid, UEF_ARTIFACT, PARAMS_HASH);
    }

    function test_submitRevertZeroArtifactHash() public {
        uint256 cid = fusion.createChallenge(UEF_RULES, "uri");
        vm.prank(alice);
        vm.expectRevert("FusionRegistry: uefArtifactHash=0");
        fusion.submit(cid, bytes32(0), PARAMS_HASH);
    }

    function test_submitRevertZeroParamsHash() public {
        uint256 cid = fusion.createChallenge(UEF_RULES, "uri");
        vm.prank(alice);
        vm.expectRevert("FusionRegistry: paramsHash=0");
        fusion.submit(cid, UEF_ARTIFACT, bytes32(0));
    }

    function test_submitEmitsEvent() public {
        uint256 cid = fusion.createChallenge(UEF_RULES, "uri");
        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit FusionRegistry.SubmissionCreated(1, cid, alice, UEF_ARTIFACT, PARAMS_HASH);
        fusion.submit(cid, UEF_ARTIFACT, PARAMS_HASH);
    }

    // ── verifySubmission ────────────────────────────────────────

    function test_verifySubmissionHappyPath() public {
        uint256 cid = fusion.createChallenge(UEF_RULES, "uri");
        vm.prank(alice);
        uint256 sid = fusion.submit(cid, UEF_ARTIFACT, PARAMS_HASH);

        vm.prank(validator);
        fusion.verifySubmission(sid, 8500, VERIFIER_REF);

        (,,,,, bool verified, uint16 scoreBps, bytes32 vRef) = fusion.submissions(sid);
        assertTrue(verified);
        assertEq(scoreBps, 8500);
        assertEq(vRef, VERIFIER_REF);
    }

    function test_verifySubmissionRevertNonValidator() public {
        uint256 cid = fusion.createChallenge(UEF_RULES, "uri");
        vm.prank(alice);
        uint256 sid = fusion.submit(cid, UEF_ARTIFACT, PARAMS_HASH);

        vm.prank(alice);
        vm.expectRevert();
        fusion.verifySubmission(sid, 5000, VERIFIER_REF);
    }

    function test_verifySubmissionRevertNonExistent() public {
        vm.prank(validator);
        vm.expectRevert("FusionRegistry: no submission");
        fusion.verifySubmission(999, 5000, VERIFIER_REF);
    }

    function test_verifySubmissionRevertAlreadyVerified() public {
        uint256 cid = fusion.createChallenge(UEF_RULES, "uri");
        vm.prank(alice);
        uint256 sid = fusion.submit(cid, UEF_ARTIFACT, PARAMS_HASH);

        vm.startPrank(validator);
        fusion.verifySubmission(sid, 8000, VERIFIER_REF);
        vm.expectRevert("FusionRegistry: already verified");
        fusion.verifySubmission(sid, 9000, VERIFIER_REF);
        vm.stopPrank();
    }

    function test_verifySubmissionRevertScoreExceeds10000() public {
        uint256 cid = fusion.createChallenge(UEF_RULES, "uri");
        vm.prank(alice);
        uint256 sid = fusion.submit(cid, UEF_ARTIFACT, PARAMS_HASH);

        vm.prank(validator);
        vm.expectRevert("FusionRegistry: scoreBps>10000");
        fusion.verifySubmission(sid, 10001, VERIFIER_REF);
    }

    function test_verifySubmissionBoundaryScore() public {
        uint256 cid = fusion.createChallenge(UEF_RULES, "uri");
        vm.prank(alice);
        uint256 sid = fusion.submit(cid, UEF_ARTIFACT, PARAMS_HASH);

        // 10000 (100.00%) should succeed
        vm.prank(validator);
        fusion.verifySubmission(sid, 10000, VERIFIER_REF);
        (,,,,, bool verified, uint16 scoreBps,) = fusion.submissions(sid);
        assertTrue(verified);
        assertEq(scoreBps, 10000);
    }

    function test_verifySubmissionEmitsEvent() public {
        uint256 cid = fusion.createChallenge(UEF_RULES, "uri");
        vm.prank(alice);
        uint256 sid = fusion.submit(cid, UEF_ARTIFACT, PARAMS_HASH);

        vm.prank(validator);
        vm.expectEmit(true, true, true, true);
        emit FusionRegistry.SubmissionVerified(sid, cid, validator, 7777, VERIFIER_REF);
        fusion.verifySubmission(sid, 7777, VERIFIER_REF);
    }

    // ── Full lifecycle ──────────────────────────────────────────

    function test_fullChallengeLifecycle() public {
        // 1. Admin creates challenge
        uint256 cid = fusion.createChallenge(UEF_RULES, "ipfs://rules");

        // 2. Multiple users submit
        vm.prank(alice);
        uint256 s1 = fusion.submit(cid, keccak256("alice-art"), keccak256("alice-p"));
        vm.prank(bob);
        uint256 s2 = fusion.submit(cid, keccak256("bob-art"), keccak256("bob-p"));

        // 3. Validator verifies submissions
        vm.startPrank(validator);
        fusion.verifySubmission(s1, 9200, keccak256("batch-1"));
        fusion.verifySubmission(s2, 7800, keccak256("batch-1"));
        vm.stopPrank();

        // 4. Admin deactivates challenge
        fusion.setChallengeActive(cid, false);

        // 5. New submissions rejected
        vm.prank(alice);
        vm.expectRevert("FusionRegistry: inactive challenge");
        fusion.submit(cid, keccak256("late"), keccak256("late-p"));

        // Verify final state
        (,,,,, bool v1, uint16 sc1,) = fusion.submissions(s1);
        (,,,,, bool v2, uint16 sc2,) = fusion.submissions(s2);
        assertTrue(v1);
        assertTrue(v2);
        assertEq(sc1, 9200);
        assertEq(sc2, 7800);
    }
}
