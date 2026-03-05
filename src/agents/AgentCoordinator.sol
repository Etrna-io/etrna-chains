// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl}   from "openzeppelin-contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/security/ReentrancyGuard.sol";

import {EtrnaErrors} from "../lib/EtrnaErrors.sol";

/**
 * @title AgentCoordinator
 * @notice Implements multi‑agent collaboration protocols for complex tasks.
 *
 * Supports five collaboration modes:
 *   1. SEQUENTIAL — Pipeline: agents execute in order, passing output → input.
 *   2. PARALLEL   — Fan‑out: all agents work concurrently; aggregator combines results.
 *   3. CONSENSUS  — Vote: agents vote on an answer; supermajority wins.
 *   4. SPECIALIST  — Route: each sub‑task dispatched to the best specialist.
 *   5. COMPETITIVE — Race: multiple agents compete; best result wins reward.
 *
 * Teams of agents can be formed, dissolved and managed. Consensus thresholds
 * and deadlines are enforced on‑chain; rewards are proportional to contribution.
 *
 * ---------------------------------------------------------------------------
 * v0: collaboration bookkeeping and reward distribution only.
 *     Off‑chain meta‑agent handles actual orchestration logic.
 * ---------------------------------------------------------------------------
 */
contract AgentCoordinator is AccessControl, ReentrancyGuard {
    // ─── Roles ──────────────────────────────────────────────────────────
    bytes32 public constant ADMIN_ROLE        = keccak256("ADMIN_ROLE");
    bytes32 public constant ORCHESTRATOR_ROLE = keccak256("ORCHESTRATOR_ROLE");
    bytes32 public constant ARBITER_ROLE      = keccak256("ARBITER_ROLE");

    // ─── Limits ─────────────────────────────────────────────────────────
    uint256 public constant MAX_AGENTS_PER_COLLAB = 20;
    uint256 public constant MAX_TEAM_MEMBERS      = 50;

    // ─── Enums ──────────────────────────────────────────────────────────
    enum CollaborationMode {
        SEQUENTIAL,
        PARALLEL,
        CONSENSUS,
        SPECIALIST,
        COMPETITIVE
    }

    enum CollabStatus {
        ACTIVE,
        COMPLETED,
        FAILED,
        CANCELLED,
        DISPUTED
    }

    enum TeamStatus { ACTIVE, DISSOLVED }

    // ─── Structs ────────────────────────────────────────────────────────

    struct Team {
        uint256     teamId;
        bytes32     name;
        address[]   members;
        address     lead;
        TeamStatus  status;
        uint64      createdAt;
    }

    struct CollaborationTask {
        uint256             id;
        uint256             teamId;          // 0 = ad‑hoc (no team)
        address             creator;
        bytes32             intentHash;      // off‑chain intent anchor
        CollaborationMode   mode;
        CollabStatus        status;
        address[]           agents;
        uint256             budgetVibe;      // total VIBE budget
        uint64              deadline;
        uint16              consensusThresholdBps; // e.g. 6000 = 60%
        uint256             resultCount;
        bytes32             finalResultHash;
        uint64              createdAt;
        uint64              completedAt;
    }

    struct AgentResult {
        address agent;
        bytes32 resultHash;
        int256  qualityBps;     // ±10 000 (assigned by arbiter/votes)
        uint64  submittedAt;
        bool    isWinner;
    }

    struct ConsensusVote {
        address agent;
        bytes32 proposedHash;
        uint64  votedAt;
    }

    // ─── Storage ────────────────────────────────────────────────────────
    mapping(uint256 => Team) public teams;
    mapping(uint256 => CollaborationTask) public collabs;
    mapping(uint256 => AgentResult[]) public results;       // collabId → results
    mapping(uint256 => ConsensusVote[]) public votes;       // collabId → votes
    mapping(uint256 => mapping(address => uint256)) public rewards; // collabId → agent → VIBE reward

    uint256 public nextTeamId;
    uint256 public nextCollabId;

    // ─── Events ─────────────────────────────────────────────────────────
    event TeamCreated(uint256 indexed teamId, bytes32 name, address indexed lead);
    event TeamDissolved(uint256 indexed teamId);
    event MemberAdded(uint256 indexed teamId, address indexed member);
    event MemberRemoved(uint256 indexed teamId, address indexed member);

    event CollaborationCreated(uint256 indexed collabId, CollaborationMode mode, uint256 agentCount);
    event ResultSubmitted(uint256 indexed collabId, address indexed agent, bytes32 resultHash);
    event VoteCast(uint256 indexed collabId, address indexed agent, bytes32 proposedHash);
    event CollaborationCompleted(uint256 indexed collabId, bytes32 finalResult, uint256 totalReward);
    event CollaborationFailed(uint256 indexed collabId, string reason);
    event RewardDistributed(uint256 indexed collabId, address indexed agent, uint256 amount);
    event WinnerSelected(uint256 indexed collabId, address indexed winner, bytes32 resultHash);

    // ─── Constructor ────────────────────────────────────────────────────
    constructor(address admin) {
        if (admin == address(0)) revert EtrnaErrors.ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
        _grantRole(ORCHESTRATOR_ROLE, admin);
        _grantRole(ARBITER_ROLE, admin);
    }

    // ═══════════════════════════════════════════════════════════════════
    //  TEAM MANAGEMENT
    // ═══════════════════════════════════════════════════════════════════

    function createTeam(
        bytes32        name,
        address[] calldata members
    ) external returns (uint256 teamId) {
        if (name == bytes32(0)) revert EtrnaErrors.InvalidInput();
        if (members.length == 0) revert EtrnaErrors.InvalidInput();

        for (uint256 i; i < members.length; i++) {
            require(members[i] != address(0), "AC: zero address");
        }

        teamId = ++nextTeamId;
        teams[teamId] = Team({
            teamId: teamId,
            name: name,
            members: members,
            lead: msg.sender,
            status: TeamStatus.ACTIVE,
            createdAt: uint64(block.timestamp)
        });

        emit TeamCreated(teamId, name, msg.sender);
    }

    function addMember(uint256 teamId, address member) external {
        Team storage t = teams[teamId];
        if (t.lead != msg.sender) revert EtrnaErrors.Unauthorized();
        if (t.status != TeamStatus.ACTIVE) revert EtrnaErrors.InvalidState();
        if (member == address(0)) revert EtrnaErrors.ZeroAddress();
        require(t.members.length < MAX_TEAM_MEMBERS, "AC: team full");
        for (uint256 i; i < t.members.length; i++) {
            require(t.members[i] != member, "AC: duplicate member");
        }
        t.members.push(member);
        emit MemberAdded(teamId, member);
    }

    function dissolveTeam(uint256 teamId) external {
        Team storage t = teams[teamId];
        if (t.lead != msg.sender && !hasRole(ADMIN_ROLE, msg.sender)) revert EtrnaErrors.Unauthorized();
        t.status = TeamStatus.DISSOLVED;
        emit TeamDissolved(teamId);
    }

    // ═══════════════════════════════════════════════════════════════════
    //  COLLABORATION LIFECYCLE
    // ═══════════════════════════════════════════════════════════════════

    function createCollaboration(
        uint256             teamId,          // 0 for ad‑hoc
        bytes32             intentHash,
        CollaborationMode   mode,
        address[] calldata  agentAddrs,
        uint256             budgetVibe,
        uint64              deadline,
        uint16              consensusThresholdBps
    ) external nonReentrant returns (uint256 collabId) {
        require(agentAddrs.length > 0, "AC: no agents");
        require(agentAddrs.length <= MAX_AGENTS_PER_COLLAB, "AC: too many agents");
        if (intentHash == bytes32(0)) revert EtrnaErrors.InvalidInput();
        if (agentAddrs.length < 2) revert EtrnaErrors.InvalidInput(); // need ≥ 2 agents
        if (budgetVibe == 0) revert EtrnaErrors.InvalidInput();
        if (deadline <= block.timestamp) revert EtrnaErrors.InvalidInput();

        // Consensus mode requires threshold
        if (mode == CollaborationMode.CONSENSUS) {
            if (consensusThresholdBps < 5000 || consensusThresholdBps > 10000) {
                revert EtrnaErrors.InvalidInput(); // 50%–100%
            }
        }

        collabId = ++nextCollabId;

        CollaborationTask storage c = collabs[collabId];
        c.id                      = collabId;
        c.teamId                  = teamId;
        c.creator                 = msg.sender;
        c.intentHash              = intentHash;
        c.mode                    = mode;
        c.status                  = CollabStatus.ACTIVE;
        c.agents                  = agentAddrs;
        c.budgetVibe              = budgetVibe;
        c.deadline                = deadline;
        c.consensusThresholdBps   = consensusThresholdBps;
        c.createdAt               = uint64(block.timestamp);

        emit CollaborationCreated(collabId, mode, agentAddrs.length);
    }

    // ─── Result Submission ──────────────────────────────────────────────

    function submitResult(
        uint256 collabId,
        bytes32 resultHash
    ) external {
        CollaborationTask storage c = collabs[collabId];
        if (c.creator == address(0)) revert EtrnaErrors.NotFound();
        if (c.status != CollabStatus.ACTIVE) revert EtrnaErrors.InvalidState();
        if (block.timestamp > c.deadline) revert EtrnaErrors.Expired();
        if (!_isParticipant(c.agents, msg.sender)) revert EtrnaErrors.Unauthorized();
        if (resultHash == bytes32(0)) revert EtrnaErrors.InvalidInput();

        results[collabId].push(AgentResult({
            agent: msg.sender,
            resultHash: resultHash,
            qualityBps: 0,
            submittedAt: uint64(block.timestamp),
            isWinner: false
        }));
        c.resultCount++;

        emit ResultSubmitted(collabId, msg.sender, resultHash);

        // Auto‑complete for PARALLEL mode when all agents submitted
        if (c.mode == CollaborationMode.PARALLEL && c.resultCount == c.agents.length) {
            _completeParallel(collabId);
        }
    }

    // ─── Consensus Vote ─────────────────────────────────────────────────

    function castVote(
        uint256 collabId,
        bytes32 proposedHash
    ) external {
        CollaborationTask storage c = collabs[collabId];
        if (c.creator == address(0)) revert EtrnaErrors.NotFound();
        if (c.mode != CollaborationMode.CONSENSUS) revert EtrnaErrors.InvalidState();
        if (c.status != CollabStatus.ACTIVE) revert EtrnaErrors.InvalidState();
        if (block.timestamp > c.deadline) revert EtrnaErrors.Expired();
        if (!_isParticipant(c.agents, msg.sender)) revert EtrnaErrors.Unauthorized();
        if (proposedHash == bytes32(0)) revert EtrnaErrors.InvalidInput();

        votes[collabId].push(ConsensusVote({
            agent: msg.sender,
            proposedHash: proposedHash,
            votedAt: uint64(block.timestamp)
        }));

        emit VoteCast(collabId, msg.sender, proposedHash);

        // Check consensus after every vote
        _checkConsensus(collabId);
    }

    // ─── Sequential Pipeline Advance ────────────────────────────────────

    function advancePipeline(
        uint256 collabId,
        bytes32 resultHash
    ) external onlyRole(ORCHESTRATOR_ROLE) {
        CollaborationTask storage c = collabs[collabId];
        if (c.creator == address(0)) revert EtrnaErrors.NotFound();
        if (c.mode != CollaborationMode.SEQUENTIAL) revert EtrnaErrors.InvalidState();
        if (c.status != CollabStatus.ACTIVE) revert EtrnaErrors.InvalidState();

        uint256 step = c.resultCount;
        if (step >= c.agents.length) revert EtrnaErrors.InvalidState();

        results[collabId].push(AgentResult({
            agent: c.agents[step],
            resultHash: resultHash,
            qualityBps: 0,
            submittedAt: uint64(block.timestamp),
            isWinner: false
        }));
        c.resultCount++;

        emit ResultSubmitted(collabId, c.agents[step], resultHash);

        // Pipeline complete when all steps done
        if (c.resultCount == c.agents.length) {
            c.finalResultHash = resultHash; // last step's result
            c.status          = CollabStatus.COMPLETED;
            c.completedAt     = uint64(block.timestamp);
            _distributeRewardsEvenly(collabId);
            emit CollaborationCompleted(collabId, resultHash, c.budgetVibe);
        }
    }

    // ─── Competition: Select Winner ─────────────────────────────────────

    function selectWinner(
        uint256 collabId,
        address winner
    ) external onlyRole(ARBITER_ROLE) nonReentrant {
        CollaborationTask storage c = collabs[collabId];
        if (c.creator == address(0)) revert EtrnaErrors.NotFound();
        if (c.mode != CollaborationMode.COMPETITIVE) revert EtrnaErrors.InvalidState();
        if (c.status != CollabStatus.ACTIVE) revert EtrnaErrors.InvalidState();
        if (!_isParticipant(c.agents, winner)) revert EtrnaErrors.InvalidInput();

        AgentResult[] storage res = results[collabId];
        bool found = false;
        for (uint256 i; i < res.length; i++) {
            if (res[i].agent == winner) {
                res[i].isWinner      = true;
                c.finalResultHash    = res[i].resultHash;
                found = true;
                break;
            }
        }
        if (!found) revert EtrnaErrors.NotFound();

        c.status      = CollabStatus.COMPLETED;
        c.completedAt = uint64(block.timestamp);

        // Winner takes 80%, rest split 20%
        uint256 winnerReward = c.budgetVibe * 8000 / 10000;
        uint256 participationReward = 0;
        if (c.agents.length > 1) {
            participationReward = (c.budgetVibe - winnerReward) / (c.agents.length - 1);
        }

        rewards[collabId][winner] = winnerReward;
        emit RewardDistributed(collabId, winner, winnerReward);

        for (uint256 i; i < c.agents.length; i++) {
            if (c.agents[i] != winner) {
                rewards[collabId][c.agents[i]] = participationReward;
                emit RewardDistributed(collabId, c.agents[i], participationReward);
            }
        }

        emit WinnerSelected(collabId, winner, c.finalResultHash);
        emit CollaborationCompleted(collabId, c.finalResultHash, c.budgetVibe);
    }

    // ─── Specialist: Score + Complete ───────────────────────────────────

    function scoreResult(
        uint256 collabId,
        address agent,
        int256  qualityBps
    ) external onlyRole(ARBITER_ROLE) {
        AgentResult[] storage res = results[collabId];
        for (uint256 i; i < res.length; i++) {
            if (res[i].agent == agent) {
                int256 clamped = qualityBps;
                if (clamped > 10000) clamped = 10000;
                if (clamped < -10000) clamped = -10000;
                res[i].qualityBps = clamped;
                return;
            }
        }
        revert EtrnaErrors.NotFound();
    }

    function completeCollaboration(
        uint256 collabId,
        bytes32 finalResult
    ) external onlyRole(ORCHESTRATOR_ROLE) nonReentrant {
        CollaborationTask storage c = collabs[collabId];
        if (c.creator == address(0)) revert EtrnaErrors.NotFound();
        if (c.status != CollabStatus.ACTIVE) revert EtrnaErrors.InvalidState();

        c.finalResultHash = finalResult;
        c.status          = CollabStatus.COMPLETED;
        c.completedAt     = uint64(block.timestamp);

        // Distribute based on quality scores
        _distributeRewardsByQuality(collabId);

        emit CollaborationCompleted(collabId, finalResult, c.budgetVibe);
    }

    function failCollaboration(
        uint256 collabId,
        string  calldata reason
    ) external onlyRole(ORCHESTRATOR_ROLE) {
        CollaborationTask storage c = collabs[collabId];
        if (c.creator == address(0)) revert EtrnaErrors.NotFound();
        if (c.status != CollabStatus.ACTIVE) revert EtrnaErrors.InvalidState();
        c.status = CollabStatus.FAILED;
        emit CollaborationFailed(collabId, reason);
    }

    // ═══════════════════════════════════════════════════════════════════
    //  INTERNAL
    // ═══════════════════════════════════════════════════════════════════

    function _isParticipant(address[] storage agents, address addr) internal view returns (bool) {
        for (uint256 i; i < agents.length; i++) {
            if (agents[i] == addr) return true;
        }
        return false;
    }

    function _checkConsensus(uint256 collabId) internal {
        CollaborationTask storage c = collabs[collabId];
        ConsensusVote[] storage v   = votes[collabId];

        // Count votes per hash
        // Simple O(n²) — acceptable for small agent sets (≤20)
        uint256 totalVotes = v.length;
        if (totalVotes == 0) return;

        bytes32 bestHash;
        uint256 bestCount;

        for (uint256 i; i < totalVotes; i++) {
            uint256 count;
            for (uint256 j; j < totalVotes; j++) {
                if (v[j].proposedHash == v[i].proposedHash) count++;
            }
            if (count > bestCount) {
                bestCount = count;
                bestHash  = v[i].proposedHash;
            }
        }

        // Check threshold
        uint256 approvalBps = (bestCount * 10000) / c.agents.length;
        if (approvalBps >= c.consensusThresholdBps) {
            c.finalResultHash = bestHash;
            c.status          = CollabStatus.COMPLETED;
            c.completedAt     = uint64(block.timestamp);
            _distributeRewardsEvenly(collabId);
            emit CollaborationCompleted(collabId, bestHash, c.budgetVibe);
        }
    }

    function _completeParallel(uint256 collabId) internal {
        CollaborationTask storage c = collabs[collabId];
        AgentResult[] storage res = results[collabId];

        // Use first result as final (aggregation happens off‑chain)
        c.finalResultHash = res[0].resultHash;
        c.status          = CollabStatus.COMPLETED;
        c.completedAt     = uint64(block.timestamp);
        _distributeRewardsEvenly(collabId);
        emit CollaborationCompleted(collabId, c.finalResultHash, c.budgetVibe);
    }

    function _distributeRewardsEvenly(uint256 collabId) internal {
        CollaborationTask storage c = collabs[collabId];
        uint256 perAgent = c.budgetVibe / c.agents.length;
        for (uint256 i; i < c.agents.length; i++) {
            rewards[collabId][c.agents[i]] = perAgent;
            emit RewardDistributed(collabId, c.agents[i], perAgent);
        }
    }

    function _distributeRewardsByQuality(uint256 collabId) internal {
        CollaborationTask storage c = collabs[collabId];
        AgentResult[] storage res   = results[collabId];

        // Sum positive quality scores
        uint256 totalPositive;
        for (uint256 i; i < res.length; i++) {
            if (res[i].qualityBps > 0) {
                totalPositive += uint256(res[i].qualityBps);
            }
        }

        if (totalPositive == 0) {
            // Fallback: even distribution
            _distributeRewardsEvenly(collabId);
            return;
        }

        for (uint256 i; i < res.length; i++) {
            if (res[i].qualityBps > 0) {
                uint256 share = c.budgetVibe * uint256(res[i].qualityBps) / totalPositive;
                rewards[collabId][res[i].agent] = share;
                emit RewardDistributed(collabId, res[i].agent, share);
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    //  VIEW HELPERS
    // ═══════════════════════════════════════════════════════════════════

    function getTeamMembers(uint256 teamId) external view returns (address[] memory) {
        return teams[teamId].members;
    }

    function getCollabAgents(uint256 collabId) external view returns (address[] memory) {
        return collabs[collabId].agents;
    }

    function getResults(uint256 collabId) external view returns (AgentResult[] memory) {
        return results[collabId];
    }

    function getVotes(uint256 collabId) external view returns (ConsensusVote[] memory) {
        return votes[collabId];
    }

    function getReward(uint256 collabId, address agent) external view returns (uint256) {
        return rewards[collabId][agent];
    }

    function teamCount() external view returns (uint256) { return nextTeamId; }
    function collabCount() external view returns (uint256) { return nextCollabId; }
}
