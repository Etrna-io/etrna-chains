// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl}    from "openzeppelin-contracts/access/AccessControl.sol";
import {ReentrancyGuard}  from "openzeppelin-contracts/security/ReentrancyGuard.sol";

import {EtrnaErrors} from "../lib/EtrnaErrors.sol";

/**
 * @title ComputeCreditVault
 * @notice VIBE‑denominated compute unit management for the Etrna AI agent system.
 *
 * Model tiers define base rates (compute units per VIBE). Batch and priority
 * multipliers adjust cost dynamically. Users deposit VIBE, optionally delegate
 * credits to beneficiaries, and the vault meters usage per inference call.
 *
 * Architecture:
 *   User → deposit(VIBE) → balance
 *   Orchestrator → consumeCredits(user, taskId, agentId, tier, units)
 *   Sponsors → delegateCredits(user → beneficiary, amount)
 *
 * ---------------------------------------------------------------------------
 * v0: off‑chain VIBE accounting (balances tracked in uint256).
 *     On‑chain ERC‑20 pull integration deferred to v1.
 * ---------------------------------------------------------------------------
 */
contract ComputeCreditVault is AccessControl, ReentrancyGuard {
    // ─── Roles ──────────────────────────────────────────────────────────
    bytes32 public constant ADMIN_ROLE        = keccak256("ADMIN_ROLE");
    bytes32 public constant ORCHESTRATOR_ROLE = keccak256("ORCHESTRATOR_ROLE");
    bytes32 public constant TREASURER_ROLE    = keccak256("TREASURER_ROLE");

    // ─── Enums ──────────────────────────────────────────────────────────
    enum ModelTier {
        BASIC,      // small / fast local models
        STANDARD,   // GPT‑4o‑mini class
        ADVANCED,   // GPT‑4o / Claude class
        PREMIUM,    // o1‑preview, deep reasoning
        FRONTIER    // frontier / custom fine‑tuned
    }

    // ─── Structs ────────────────────────────────────────────────────────
    struct TierConfig {
        uint256 baseRatePerUnit;      // VIBE cost per compute unit (18 dec)
        uint16  batchDiscountBps;     // discount for batches of ≥ 10 units
        uint16  priorityMultiplierBps;// surcharge for priority tasks (e.g. 12000 = 1.2×)
        bool    enabled;
    }

    struct UsageRecord {
        address user;
        bytes32 taskId;
        address agentId;
        ModelTier tier;
        uint256 computeUnits;
        uint256 cost;
        uint64  timestamp;
    }

    // ─── Storage ────────────────────────────────────────────────────────
    mapping(address => uint256) public balances;
    mapping(address => mapping(address => uint256)) public delegations; // sponsor → beneficiary → amount
    mapping(ModelTier => TierConfig) public tiers;
    UsageRecord[] public usageLog;

    uint256 public totalDeposited;
    uint256 public totalConsumed;
    uint256 public batchThreshold;  // units required for batch discount (default 10)

    // ─── Events ─────────────────────────────────────────────────────────
    event Deposited(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event CreditsConsumed(
        address indexed user,
        bytes32 indexed taskId,
        address indexed agentId,
        ModelTier tier,
        uint256 computeUnits,
        uint256 cost
    );
    event CreditsDelegated(address indexed sponsor, address indexed beneficiary, uint256 amount);
    event DelegationRevoked(address indexed sponsor, address indexed beneficiary, uint256 amount);
    event TierConfigured(ModelTier indexed tier, uint256 baseRate, uint16 batchDiscount, uint16 priorityMultiplier);

    // ─── Constructor ────────────────────────────────────────────────────
    constructor(address admin) {
        if (admin == address(0)) revert EtrnaErrors.ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
        _grantRole(ORCHESTRATOR_ROLE, admin);
        _grantRole(TREASURER_ROLE, admin);

        batchThreshold = 10;

        // Default tier configs (VIBE cost per compute unit in 18‑decimal wei)
        _configureTier(ModelTier.BASIC,    1e15,   500,  10000); //  0.001 VIBE/unit, 5% batch, 1.0× priority
        _configureTier(ModelTier.STANDARD, 5e15,  1000,  10000); //  0.005 VIBE/unit, 10% batch, 1.0×
        _configureTier(ModelTier.ADVANCED, 25e15, 1500,  12000); //  0.025 VIBE/unit, 15% batch, 1.2× priority
        _configureTier(ModelTier.PREMIUM,  100e15, 2000, 15000); //  0.1   VIBE/unit, 20% batch, 1.5× priority
        _configureTier(ModelTier.FRONTIER, 500e15, 2500, 20000); //  0.5   VIBE/unit, 25% batch, 2.0× priority
    }

    // ─── Deposit / Withdraw ─────────────────────────────────────────────
    function deposit(uint256 amount) external nonReentrant {
        if (amount == 0) revert EtrnaErrors.InvalidInput();
        // v0: off‑chain accounting — caller's balance is incremented.
        // v1: pull VIBE via IERC20(vibeToken).transferFrom(msg.sender, address(this), amount)
        balances[msg.sender] += amount;
        totalDeposited += amount;
        emit Deposited(msg.sender, amount);
    }

    function withdraw(uint256 amount) external nonReentrant {
        if (amount == 0 || amount > balances[msg.sender]) revert EtrnaErrors.InvalidInput();
        balances[msg.sender] -= amount;
        // v1: push VIBE back to user
        emit Withdrawn(msg.sender, amount);
    }

    // ─── Delegation ─────────────────────────────────────────────────────
    function delegateCredits(address beneficiary, uint256 amount) external nonReentrant {
        if (beneficiary == address(0)) revert EtrnaErrors.ZeroAddress();
        if (amount == 0 || amount > balances[msg.sender]) revert EtrnaErrors.InvalidInput();

        balances[msg.sender] -= amount;
        delegations[msg.sender][beneficiary] += amount;
        balances[beneficiary] += amount;
        emit CreditsDelegated(msg.sender, beneficiary, amount);
    }

    function revokeDelegation(address beneficiary, uint256 amount) external nonReentrant {
        if (beneficiary == address(0)) revert EtrnaErrors.ZeroAddress();
        uint256 delegated = delegations[msg.sender][beneficiary];
        if (amount == 0 || amount > delegated) revert EtrnaErrors.InvalidInput();
        // Only revoke if beneficiary has enough balance
        if (amount > balances[beneficiary]) revert EtrnaErrors.InvalidInput();

        delegations[msg.sender][beneficiary] -= amount;
        balances[beneficiary] -= amount;
        balances[msg.sender] += amount;
        emit DelegationRevoked(msg.sender, beneficiary, amount);
    }

    // ─── Compute Consumption (called by orchestrator) ───────────────────
    function consumeCredits(
        address user,
        bytes32 taskId,
        address agentId,
        ModelTier tier,
        uint256 computeUnits,
        bool    isPriority
    ) external onlyRole(ORCHESTRATOR_ROLE) nonReentrant returns (uint256 cost) {
        if (user == address(0) || agentId == address(0)) revert EtrnaErrors.ZeroAddress();
        if (computeUnits == 0) revert EtrnaErrors.InvalidInput();

        TierConfig memory cfg = tiers[tier];
        if (!cfg.enabled) revert EtrnaErrors.NotEnabled();

        cost = _calculateCost(cfg, computeUnits, isPriority);
        if (cost > balances[user]) revert EtrnaErrors.InsufficientStake();

        balances[user] -= cost;
        totalConsumed += cost;

        usageLog.push(UsageRecord({
            user: user,
            taskId: taskId,
            agentId: agentId,
            tier: tier,
            computeUnits: computeUnits,
            cost: cost,
            timestamp: uint64(block.timestamp)
        }));

        emit CreditsConsumed(user, taskId, agentId, tier, computeUnits, cost);
    }

    // ─── Cost Calculation ───────────────────────────────────────────────
    function estimateCost(
        ModelTier tier,
        uint256  computeUnits,
        bool     isPriority
    ) external view returns (uint256) {
        TierConfig memory cfg = tiers[tier];
        if (!cfg.enabled) revert EtrnaErrors.NotEnabled();
        return _calculateCost(cfg, computeUnits, isPriority);
    }

    function _calculateCost(
        TierConfig memory cfg,
        uint256 computeUnits,
        bool    isPriority
    ) internal view returns (uint256 cost) {
        cost = cfg.baseRatePerUnit * computeUnits;

        // Batch discount: if units ≥ threshold, reduce by batchDiscountBps
        if (computeUnits >= batchThreshold && cfg.batchDiscountBps > 0) {
            cost = cost * (10000 - cfg.batchDiscountBps) / 10000;
        }

        // Priority surcharge: multiply by priorityMultiplierBps / 10000
        if (isPriority && cfg.priorityMultiplierBps > 10000) {
            cost = cost * cfg.priorityMultiplierBps / 10000;
        }
    }

    // ─── Admin ──────────────────────────────────────────────────────────
    function configureTier(
        ModelTier tier,
        uint256   baseRate,
        uint16    batchDiscount,
        uint16    priorityMultiplier
    ) external onlyRole(ADMIN_ROLE) {
        _configureTier(tier, baseRate, batchDiscount, priorityMultiplier);
    }

    function setBatchThreshold(uint256 threshold) external onlyRole(ADMIN_ROLE) {
        batchThreshold = threshold;
    }

    function _configureTier(
        ModelTier tier,
        uint256   baseRate,
        uint16    batchDiscount,
        uint16    priorityMultiplier
    ) internal {
        if (baseRate == 0) revert EtrnaErrors.InvalidInput();
        if (batchDiscount > 5000) revert EtrnaErrors.InvalidInput(); // max 50%
        if (priorityMultiplier < 10000) revert EtrnaErrors.InvalidInput(); // min 1.0×

        tiers[tier] = TierConfig({
            baseRatePerUnit: baseRate,
            batchDiscountBps: batchDiscount,
            priorityMultiplierBps: priorityMultiplier,
            enabled: true
        });
        emit TierConfigured(tier, baseRate, batchDiscount, priorityMultiplier);
    }

    // ─── View Helpers ───────────────────────────────────────────────────
    function usageLogLength() external view returns (uint256) { return usageLog.length; }

    function getBalance(address user) external view returns (uint256) { return balances[user]; }

    function getDelegation(address sponsor, address beneficiary) external view returns (uint256) {
        return delegations[sponsor][beneficiary];
    }
}
