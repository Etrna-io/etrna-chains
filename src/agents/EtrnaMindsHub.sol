// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl}   from "openzeppelin-contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/security/ReentrancyGuard.sol";

import {EtrnaErrors} from "../lib/EtrnaErrors.sol";

/**
 * @title EtrnaMindsHub
 * @notice Decentralised AI marketplace and orchestration hub.
 *
 * Agents register by staking ETR tokens and listing their capabilities,
 * compute credits and reputation. Users create tasks with required
 * capabilities and budgets; the hub assigns agents, tracks compute
 * consumption, and distributes rewards or slashes stakes on failures.
 *
 * Multi‑agent tasks, federated fine‑tune NFTs, and reputation boosts
 * are all managed on‑chain.
 *
 * Architecture:
 *   Agent → register(stake, capabilities) → agentProfiles[addr]
 *   User  → createTask(caps, budget, deadline) → taskQueue[id]
 *   Orchestrator → assignAgents(), completeTask(), failTask()
 *   Rewards → reputationOf[agent], fineTuneNFTs[modelId]
 *
 * ---------------------------------------------------------------------------
 * v0: ETR stake is off‑chain accounting (same pattern as CognitionMesh).
 *     ERC‑20 pull integration deferred to v1.
 * ---------------------------------------------------------------------------
 */
contract EtrnaMindsHub is AccessControl, ReentrancyGuard {
    // ─── Roles ──────────────────────────────────────────────────────────
    bytes32 public constant ADMIN_ROLE        = keccak256("ADMIN_ROLE");
    bytes32 public constant ORCHESTRATOR_ROLE = keccak256("ORCHESTRATOR_ROLE");
    bytes32 public constant VALIDATOR_ROLE    = keccak256("VALIDATOR_ROLE");

    // ─── Enums ──────────────────────────────────────────────────────────
    enum AgentStatus   { INACTIVE, ACTIVE, PAUSED, SLASHED, RETIRED }
    enum TaskStatus    { PENDING, ASSIGNED, IN_PROGRESS, COMPLETED, FAILED, DISPUTED }
    enum TaskPriority  { LOW, NORMAL, HIGH, URGENT }

    // ─── Structs ────────────────────────────────────────────────────────
    struct AgentProfile {
        address   owner;
        bytes32   name;             // keccak‑shortened display name
        uint256   stakeAmount;      // ETR staked
        int256    reputationBps;    // ±10 000 bps
        uint256   successCount;
        uint256   failCount;
        uint256   totalRewardsEarned;
        uint64    registeredAt;
        AgentStatus status;
        bytes32[] capabilities;     // e.g. keccak("VENUE_ADVISOR"), keccak("MUSIC_CURATOR")
        uint256   computeCredits;   // credits deposited in ComputeCreditVault
    }

    struct TaskEntry {
        uint256        id;
        address        creator;
        bytes32        intentHash;        // off‑chain intent anchor
        bytes32[]      requiredCaps;
        uint256        budgetVibe;        // VIBE budget
        uint64         deadline;
        TaskPriority   priority;
        TaskStatus     status;
        address[]      assignedAgents;
        bytes32        resultHash;        // off‑chain result anchor
        uint256        rewardPerAgent;
        uint64         createdAt;
        uint64         completedAt;
    }

    struct FineTuneNFT {
        uint256 modelId;
        address creator;
        bytes32 domainHash;       // e.g. keccak("nightlife"), keccak("music")
        uint256 royaltyBps;       // royalty per reuse
        uint256 usageCount;
        int256  qualityScoreBps;  // ±10 000
        uint64  mintedAt;
    }

    // ─── Storage ────────────────────────────────────────────────────────
    mapping(address => AgentProfile)  public agents;
    mapping(uint256 => TaskEntry)     public tasks;
    mapping(uint256 => FineTuneNFT)   public fineTuneModels;

    address[] public registeredAgents;
    uint256   public nextTaskId;
    uint256   public nextModelId;

    // Config
    uint256 public minStake;           // minimum ETR to register
    uint256 public slashPercentBps;    // slash percentage (default 1000 = 10%)
    uint256 public reputationBoostBps; // boost per success (default 100 = 1%)
    uint256 public maxAgentsPerTask;   // max agents assignable (default 5)

    // ─── Events ─────────────────────────────────────────────────────────
    event AgentRegistered(address indexed agent, bytes32 name, uint256 stake);
    event AgentStatusChanged(address indexed agent, AgentStatus newStatus);
    event AgentSlashed(address indexed agent, uint256 slashAmount, string reason);
    event AgentReputationUpdated(address indexed agent, int256 newReputationBps);

    event TaskCreated(uint256 indexed taskId, address indexed creator, uint256 budget);
    event AgentsAssigned(uint256 indexed taskId, address[] agents);
    event TaskCompleted(uint256 indexed taskId, bytes32 resultHash, uint256 totalReward);
    event TaskFailed(uint256 indexed taskId, string reason);
    event TaskDisputed(uint256 indexed taskId, address indexed disputer);

    event FineTuneModelRegistered(uint256 indexed modelId, address indexed creator, bytes32 domainHash);
    event FineTuneModelUsed(uint256 indexed modelId, address indexed user, uint256 royaltyPaid);

    event ComputeCreditsDeposited(address indexed agent, uint256 amount);

    // ─── Constructor ────────────────────────────────────────────────────
    constructor(address admin) {
        if (admin == address(0)) revert EtrnaErrors.ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
        _grantRole(ORCHESTRATOR_ROLE, admin);
        _grantRole(VALIDATOR_ROLE, admin);

        minStake           = 100e18;   // 100 ETR
        slashPercentBps    = 1000;     // 10%
        reputationBoostBps = 100;      // +1% per success
        maxAgentsPerTask   = 5;
    }

    // ═══════════════════════════════════════════════════════════════════
    //  AGENT REGISTRATION
    // ═══════════════════════════════════════════════════════════════════

    function registerAgent(
        bytes32   name,
        uint256   stakeAmount,
        bytes32[] calldata capabilities
    ) external nonReentrant {
        if (name == bytes32(0)) revert EtrnaErrors.InvalidInput();
        if (stakeAmount < minStake) revert EtrnaErrors.InsufficientStake();
        if (capabilities.length == 0) revert EtrnaErrors.InvalidInput();
        if (agents[msg.sender].registeredAt != 0) revert EtrnaErrors.AlreadyExists();

        // v0: off‑chain stake accounting
        agents[msg.sender] = AgentProfile({
            owner: msg.sender,
            name: name,
            stakeAmount: stakeAmount,
            reputationBps: 5000, // start at 50% (neutral)
            successCount: 0,
            failCount: 0,
            totalRewardsEarned: 0,
            registeredAt: uint64(block.timestamp),
            status: AgentStatus.ACTIVE,
            capabilities: capabilities,
            computeCredits: 0
        });
        registeredAgents.push(msg.sender);

        emit AgentRegistered(msg.sender, name, stakeAmount);
    }

    function pauseAgent() external {
        AgentProfile storage a = agents[msg.sender];
        if (a.registeredAt == 0) revert EtrnaErrors.NotFound();
        if (a.status != AgentStatus.ACTIVE) revert EtrnaErrors.InvalidState();
        a.status = AgentStatus.PAUSED;
        emit AgentStatusChanged(msg.sender, AgentStatus.PAUSED);
    }

    function resumeAgent() external {
        AgentProfile storage a = agents[msg.sender];
        if (a.registeredAt == 0) revert EtrnaErrors.NotFound();
        if (a.status != AgentStatus.PAUSED) revert EtrnaErrors.InvalidState();
        a.status = AgentStatus.ACTIVE;
        emit AgentStatusChanged(msg.sender, AgentStatus.ACTIVE);
    }

    function retireAgent() external {
        AgentProfile storage a = agents[msg.sender];
        if (a.registeredAt == 0) revert EtrnaErrors.NotFound();
        a.status = AgentStatus.RETIRED;
        emit AgentStatusChanged(msg.sender, AgentStatus.RETIRED);
    }

    function depositComputeCredits(uint256 amount) external nonReentrant {
        if (amount == 0) revert EtrnaErrors.InvalidInput();
        AgentProfile storage a = agents[msg.sender];
        if (a.registeredAt == 0) revert EtrnaErrors.NotFound();
        a.computeCredits += amount;
        emit ComputeCreditsDeposited(msg.sender, amount);
    }

    // ═══════════════════════════════════════════════════════════════════
    //  TASK MANAGEMENT
    // ═══════════════════════════════════════════════════════════════════

    function createTask(
        bytes32        intentHash,
        bytes32[]  calldata requiredCaps,
        uint256        budgetVibe,
        uint64         deadline,
        TaskPriority   priority
    ) external nonReentrant returns (uint256 taskId) {
        if (intentHash == bytes32(0)) revert EtrnaErrors.InvalidInput();
        if (requiredCaps.length == 0) revert EtrnaErrors.InvalidInput();
        if (budgetVibe == 0) revert EtrnaErrors.InvalidInput();
        if (deadline <= block.timestamp) revert EtrnaErrors.InvalidInput();

        taskId = ++nextTaskId;

        TaskEntry storage t = tasks[taskId];
        t.id             = taskId;
        t.creator        = msg.sender;
        t.intentHash     = intentHash;
        t.requiredCaps   = requiredCaps;
        t.budgetVibe     = budgetVibe;
        t.deadline       = deadline;
        t.priority       = priority;
        t.status         = TaskStatus.PENDING;
        t.createdAt      = uint64(block.timestamp);

        emit TaskCreated(taskId, msg.sender, budgetVibe);
    }

    function assignAgents(
        uint256        taskId,
        address[] calldata agentAddrs
    ) external onlyRole(ORCHESTRATOR_ROLE) {
        TaskEntry storage t = tasks[taskId];
        if (t.creator == address(0)) revert EtrnaErrors.NotFound();
        if (t.status != TaskStatus.PENDING) revert EtrnaErrors.InvalidState();
        if (agentAddrs.length == 0 || agentAddrs.length > maxAgentsPerTask) revert EtrnaErrors.InvalidInput();

        for (uint256 i; i < agentAddrs.length; i++) {
            AgentProfile storage a = agents[agentAddrs[i]];
            if (a.status != AgentStatus.ACTIVE) revert EtrnaErrors.NotActive();
        }

        t.assignedAgents = agentAddrs;
        t.status = TaskStatus.ASSIGNED;
        t.rewardPerAgent = t.budgetVibe / agentAddrs.length;

        emit AgentsAssigned(taskId, agentAddrs);
    }

    function completeTask(
        uint256 taskId,
        bytes32 resultHash
    ) external onlyRole(ORCHESTRATOR_ROLE) nonReentrant {
        TaskEntry storage t = tasks[taskId];
        if (t.creator == address(0)) revert EtrnaErrors.NotFound();
        if (t.status != TaskStatus.ASSIGNED && t.status != TaskStatus.IN_PROGRESS) revert EtrnaErrors.InvalidState();
        if (resultHash == bytes32(0)) revert EtrnaErrors.InvalidInput();

        t.resultHash  = resultHash;
        t.status      = TaskStatus.COMPLETED;
        t.completedAt = uint64(block.timestamp);

        // Reward agents — reputation boost + accounting
        uint256 totalReward;
        for (uint256 i; i < t.assignedAgents.length; i++) {
            AgentProfile storage a = agents[t.assignedAgents[i]];
            a.successCount++;
            a.totalRewardsEarned += t.rewardPerAgent;
            totalReward += t.rewardPerAgent;

            // Reputation boost (clamped to 10000)
            int256 newRep = a.reputationBps + int256(uint256(reputationBoostBps));
            if (newRep > 10000) newRep = 10000;
            a.reputationBps = newRep;
            emit AgentReputationUpdated(t.assignedAgents[i], newRep);
        }

        emit TaskCompleted(taskId, resultHash, totalReward);
    }

    function failTask(
        uint256 taskId,
        string  calldata reason
    ) external onlyRole(ORCHESTRATOR_ROLE) nonReentrant {
        TaskEntry storage t = tasks[taskId];
        if (t.creator == address(0)) revert EtrnaErrors.NotFound();
        if (t.status != TaskStatus.ASSIGNED && t.status != TaskStatus.IN_PROGRESS) revert EtrnaErrors.InvalidState();

        t.status = TaskStatus.FAILED;

        // Slash agents
        for (uint256 i; i < t.assignedAgents.length; i++) {
            _slashAgent(t.assignedAgents[i], reason);
        }

        emit TaskFailed(taskId, reason);
    }

    function disputeTask(uint256 taskId) external {
        TaskEntry storage t = tasks[taskId];
        if (t.creator == address(0)) revert EtrnaErrors.NotFound();
        if (t.status != TaskStatus.COMPLETED) revert EtrnaErrors.InvalidState();
        if (msg.sender != t.creator) revert EtrnaErrors.Unauthorized();

        t.status = TaskStatus.DISPUTED;
        emit TaskDisputed(taskId, msg.sender);
    }

    // ═══════════════════════════════════════════════════════════════════
    //  SLASHING
    // ═══════════════════════════════════════════════════════════════════

    function slashAgent(address agent, string calldata reason) external onlyRole(VALIDATOR_ROLE) {
        _slashAgent(agent, reason);
    }

    function _slashAgent(address agent, string memory reason) internal {
        AgentProfile storage a = agents[agent];
        if (a.registeredAt == 0) revert EtrnaErrors.NotFound();

        uint256 slashAmount = a.stakeAmount * slashPercentBps / 10000;
        a.stakeAmount -= slashAmount;
        a.failCount++;

        // Reputation penalty (–2× boost per failure)
        int256 penalty = -int256(uint256(reputationBoostBps)) * 2;
        int256 newRep  = a.reputationBps + penalty;
        if (newRep < 0) newRep = 0;
        a.reputationBps = newRep;

        // Auto‑suspend if stake drops below minimum
        if (a.stakeAmount < minStake) {
            a.status = AgentStatus.SLASHED;
            emit AgentStatusChanged(agent, AgentStatus.SLASHED);
        }

        emit AgentSlashed(agent, slashAmount, reason);
        emit AgentReputationUpdated(agent, newRep);
    }

    // ═══════════════════════════════════════════════════════════════════
    //  FINE‑TUNE NFTs
    // ═══════════════════════════════════════════════════════════════════

    function registerFineTuneModel(
        bytes32 domainHash,
        uint256 royaltyBps
    ) external nonReentrant returns (uint256 modelId) {
        if (domainHash == bytes32(0)) revert EtrnaErrors.InvalidInput();
        if (royaltyBps > 2500) revert EtrnaErrors.InvalidInput(); // max 25% royalty

        AgentProfile storage a = agents[msg.sender];
        if (a.registeredAt == 0 || a.status != AgentStatus.ACTIVE) revert EtrnaErrors.NotActive();

        modelId = ++nextModelId;
        fineTuneModels[modelId] = FineTuneNFT({
            modelId: modelId,
            creator: msg.sender,
            domainHash: domainHash,
            royaltyBps: royaltyBps,
            usageCount: 0,
            qualityScoreBps: 5000, // neutral
            mintedAt: uint64(block.timestamp)
        });

        emit FineTuneModelRegistered(modelId, msg.sender, domainHash);
    }

    function useFineTuneModel(uint256 modelId) external nonReentrant {
        FineTuneNFT storage m = fineTuneModels[modelId];
        if (m.creator == address(0)) revert EtrnaErrors.NotFound();
        m.usageCount++;
        // v1: calculate royalty from compute cost and transfer to creator
        emit FineTuneModelUsed(modelId, msg.sender, 0);
    }

    function scoreFineTuneModel(uint256 modelId, int256 deltaBps) external onlyRole(VALIDATOR_ROLE) {
        FineTuneNFT storage m = fineTuneModels[modelId];
        if (m.creator == address(0)) revert EtrnaErrors.NotFound();
        int256 next = m.qualityScoreBps + deltaBps;
        if (next > 10000) next = 10000;
        if (next < -10000) next = -10000;
        m.qualityScoreBps = next;
    }

    // ═══════════════════════════════════════════════════════════════════
    //  ADMIN
    // ═══════════════════════════════════════════════════════════════════

    function setMinStake(uint256 _minStake) external onlyRole(ADMIN_ROLE) {
        minStake = _minStake;
    }
    function setSlashPercent(uint256 _bps) external onlyRole(ADMIN_ROLE) {
        if (_bps > 5000) revert EtrnaErrors.InvalidInput(); // max 50%
        slashPercentBps = _bps;
    }
    function setReputationBoost(uint256 _bps) external onlyRole(ADMIN_ROLE) {
        if (_bps > 1000) revert EtrnaErrors.InvalidInput(); // max 10%
        reputationBoostBps = _bps;
    }
    function setMaxAgentsPerTask(uint256 _max) external onlyRole(ADMIN_ROLE) {
        if (_max == 0 || _max > 20) revert EtrnaErrors.InvalidInput();
        maxAgentsPerTask = _max;
    }

    // ═══════════════════════════════════════════════════════════════════
    //  VIEW HELPERS
    // ═══════════════════════════════════════════════════════════════════

    function getAgentCapabilities(address agent) external view returns (bytes32[] memory) {
        return agents[agent].capabilities;
    }

    function getTaskAssignedAgents(uint256 taskId) external view returns (address[] memory) {
        return tasks[taskId].assignedAgents;
    }

    function getTaskRequiredCaps(uint256 taskId) external view returns (bytes32[] memory) {
        return tasks[taskId].requiredCaps;
    }

    function registeredAgentCount() external view returns (uint256) {
        return registeredAgents.length;
    }

    function isAgentActive(address agent) external view returns (bool) {
        return agents[agent].status == AgentStatus.ACTIVE;
    }

    function getAgentSuccessRate(address agent) external view returns (uint256) {
        AgentProfile storage a = agents[agent];
        uint256 total = a.successCount + a.failCount;
        if (total == 0) return 0;
        return (a.successCount * 10000) / total;
    }
}
