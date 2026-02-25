// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "openzeppelin-contracts/access/AccessControl.sol";

import {IEtrnaERC20} from "../interfaces/IEtrnaERC20.sol";
import {IQuantumRelay} from "../interfaces/IQuantumRelay.sol";
import {RealityTypes} from "./RealityTypes.sol";
import {EtrnaErrors} from "../lib/EtrnaErrors.sol";

/**
 * @title RealityLedger (RL1)
 * @notice Canonical, time-ordered ledger of "Reality Assertions" for Etrna.
 *
 * Design goals (v0):
 * - Cheap on-chain anchoring (hashes, not raw payloads)
 * - Economic skin-in-the-game via $ETR staking
 * - Extensible schemas/topics
 * - Pluggable randomness anchoring (Quantum Relay) for timestamp hardening
 *
 * This is intentionally conservative: it provides an audit-grade substrate
 * for off-chain reasoning and dispute resolution.
 */
contract RealityLedger is AccessControl {
    using RealityTypes for RealityTypes.Assertion;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant ARBITER_ROLE = keccak256("ARBITER_ROLE");

    event AssertionSubmitted(
        uint256 indexed assertionId,
        address indexed asserter,
        bytes32 indexed topic,
        bytes32 schema,
        bytes32 contentHash,
        uint256 stake,
        uint256 randomnessRequestId
    );

    event AssertionChallenged(
        uint256 indexed assertionId,
        uint256 indexed challengeId,
        address indexed challenger,
        uint256 stake
    );

    event AssertionResolved(
        uint256 indexed assertionId,
        uint256 indexed challengeId,
        bool outcomeTrue,
        address resolver
    );

    IEtrnaERC20 public immutable etr;
    IQuantumRelay public quantumRelay; // optional

    uint256 public minStake;

    uint256 public assertionCount;
    uint256 public challengeCount;

    mapping(uint256 => RealityTypes.Assertion) public assertions;
    mapping(uint256 => RealityTypes.Challenge) public challenges;

    constructor(address admin, address etrToken, uint256 minStake_) {
        if (admin == address(0) || etrToken == address(0)) revert EtrnaErrors.ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
        _grantRole(ARBITER_ROLE, admin); // v0: admin can arbitrate; migrate to timelock later

        etr = IEtrnaERC20(etrToken);
        minStake = minStake_;
    }

    function setQuantumRelay(address relay) external onlyRole(ADMIN_ROLE) {
        quantumRelay = IQuantumRelay(relay);
    }

    function setMinStake(uint256 newMin) external onlyRole(ADMIN_ROLE) {
        minStake = newMin;
    }

    /// @notice Submit a reality assertion anchored by contentHash (payload kept off-chain).
    /// @param topic High-level subject (e.g., CITY:TORONTO, COMPANY:ACME, PAPER:DOI, etc.)
    /// @param schema Schema identifier for canonical decoding/validation off-chain.
    /// @param contentHash Hash of canonicalized payload.
    /// @param stake Amount of $ETR to stake.
    function submitAssertion(bytes32 topic, bytes32 schema, bytes32 contentHash, uint256 stake)
        external
        returns (uint256 assertionId)
    {
        if (topic == bytes32(0) || schema == bytes32(0) || contentHash == bytes32(0)) revert EtrnaErrors.InvalidInput();
        if (stake < minStake) revert EtrnaErrors.InsufficientStake();

        // Pull stake in $ETR (economic commitment)
        bool ok = etr.transferFrom(msg.sender, address(this), stake);
        if (!ok) revert EtrnaErrors.InvalidState();

        assertionId = ++assertionCount;

        uint256 reqId;
        if (address(quantumRelay) != address(0)) {
            // Optional: harden ordering with randomness beacon request.
            // Off-chain systems can use (block, reqId) as an additional anchor.
            reqId = quantumRelay.requestRandomness();
        }

        assertions[assertionId] = RealityTypes.Assertion({
            asserter: msg.sender,
            assertedAt: uint64(block.timestamp),
            schema: schema,
            topic: topic,
            contentHash: contentHash,
            stake: stake,
            status: RealityTypes.AssertionStatus.Active,
            challengeId: 0
        });

        emit AssertionSubmitted(assertionId, msg.sender, topic, schema, contentHash, stake, reqId);
    }

    /// @notice Challenge an active assertion by staking $ETR.
    function challengeAssertion(uint256 assertionId, uint256 stake)
        external
        returns (uint256 challengeId)
    {
        RealityTypes.Assertion storage a = assertions[assertionId];
        if (a.asserter == address(0)) revert EtrnaErrors.NotFound();
        if (a.status != RealityTypes.AssertionStatus.Active) revert EtrnaErrors.NotActive();
        if (stake < a.stake) revert EtrnaErrors.InsufficientStake();

        bool ok = etr.transferFrom(msg.sender, address(this), stake);
        if (!ok) revert EtrnaErrors.InvalidState();

        challengeId = ++challengeCount;
        challenges[challengeId] = RealityTypes.Challenge({
            challenger: msg.sender,
            challengedAt: uint64(block.timestamp),
            stake: stake,
            resolved: false,
            outcomeTrue: false
        });

        a.status = RealityTypes.AssertionStatus.Challenged;
        a.challengeId = challengeId;

        emit AssertionChallenged(assertionId, challengeId, msg.sender, stake);
    }

    /// @notice Resolve a challenged assertion. v0 is role-gated arbitration.
    /// Future versions: automated / probabilistic / multi-party resolution.
    function resolveAssertion(uint256 assertionId, bool outcomeTrue) external onlyRole(ARBITER_ROLE) {
        RealityTypes.Assertion storage a = assertions[assertionId];
        if (a.asserter == address(0)) revert EtrnaErrors.NotFound();
        if (a.status != RealityTypes.AssertionStatus.Challenged) revert EtrnaErrors.InvalidState();

        uint256 challengeId = a.challengeId;
        RealityTypes.Challenge storage c = challenges[challengeId];
        if (c.challenger == address(0)) revert EtrnaErrors.NotFound();
        if (c.resolved) revert EtrnaErrors.InvalidState();

        c.resolved = true;
        c.outcomeTrue = outcomeTrue;

        a.status = outcomeTrue ? RealityTypes.AssertionStatus.ResolvedTrue : RealityTypes.AssertionStatus.ResolvedFalse;

        // Economic settlement (v0, simple):
        // - If true: challenger loses stake to asserter
        // - If false: asserter loses stake to challenger
        if (outcomeTrue) {
            bool ok1 = etr.transfer(a.asserter, c.stake);
            if (!ok1) revert EtrnaErrors.InvalidState();
            bool ok2 = etr.transfer(a.asserter, a.stake);
            if (!ok2) revert EtrnaErrors.InvalidState();
        } else {
            bool ok3 = etr.transfer(c.challenger, a.stake);
            if (!ok3) revert EtrnaErrors.InvalidState();
            bool ok4 = etr.transfer(c.challenger, c.stake);
            if (!ok4) revert EtrnaErrors.InvalidState();
        }

        emit AssertionResolved(assertionId, challengeId, outcomeTrue, msg.sender);
    }
}
