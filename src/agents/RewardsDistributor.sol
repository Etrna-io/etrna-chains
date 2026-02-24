// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl}   from "openzeppelin-contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/security/ReentrancyGuard.sol";
import {ECDSA}           from "openzeppelin-contracts/utils/cryptography/ECDSA.sol";

import {EtrnaErrors} from "../lib/EtrnaErrors.sol";

/**
 * @title RewardsDistributor
 * @notice On-chain VIBE minting and distribution based on meaning scores.
 *
 * The off‑chain Rewards Engine computes per‑epoch allocations (using
 * MeaningEngine bps, reality accuracy, agent contributions) and submits
 * them here. The contract validates admin signature, enforces epoch caps,
 * and mints VIBE via IVibeToken.
 *
 * Budget caps prevent runaway inflation:
 *   - Per‑epoch cap (adjustable by admin)
 *   - Cumulative budget tracking
 *
 * Architecture:
 *   Off‑chain Rewards Engine → compute allocations → sign digest
 *   Admin/Orchestrator → executeEpoch(epochId, allocations, sig)
 *   Contract → validate sig, enforce cap, IVibeToken.mint()
 *
 * ---------------------------------------------------------------------------
 * v0: admin‑signed epochs. v1: multi‑sig + timelock governance.
 * ---------------------------------------------------------------------------
 */

interface IVibeTokenMinter {
    function mint(address to, uint256 amount) external;
    function totalSupply() external view returns (uint256);
    function maxSupply() external view returns (uint256);
}

contract RewardsDistributor is AccessControl, ReentrancyGuard {
    using ECDSA for bytes32;

    // ─── Roles ──────────────────────────────────────────────────────────
    bytes32 public constant ADMIN_ROLE     = keccak256("ADMIN_ROLE");
    bytes32 public constant EXECUTOR_ROLE  = keccak256("EXECUTOR_ROLE");

    // ─── Structs ────────────────────────────────────────────────────────
    struct Allocation {
        address to;
        uint256 amount;
    }

    struct EpochRecord {
        uint256 epochId;
        uint256 totalDistributed;
        uint256 allocationCount;
        uint64  executedAt;
        address executor;
    }

    // ─── Storage ────────────────────────────────────────────────────────
    IVibeTokenMinter public immutable vibeToken;
    address public signer;                // off‑chain rewards engine signer

    mapping(uint256 => EpochRecord) public epochs;
    mapping(uint256 => bool) public epochExecuted;

    uint256 public epochCap;              // max VIBE per epoch (18 dec)
    uint256 public totalMinted;           // cumulative VIBE minted
    uint256 public totalBudget;           // hard ceiling (0 = uncapped, use vibeToken.maxSupply)
    uint256 public lastEpochId;

    // ─── Events ─────────────────────────────────────────────────────────
    event EpochExecuted(uint256 indexed epochId, uint256 totalDistributed, uint256 allocationCount);
    event AllocationMinted(uint256 indexed epochId, address indexed to, uint256 amount);
    event SignerUpdated(address indexed oldSigner, address indexed newSigner);
    event EpochCapUpdated(uint256 oldCap, uint256 newCap);
    event BudgetUpdated(uint256 oldBudget, uint256 newBudget);

    // ─── Constructor ────────────────────────────────────────────────────
    constructor(
        address admin,
        address _vibeToken,
        address _signer,
        uint256 _epochCap
    ) {
        if (admin == address(0) || _vibeToken == address(0) || _signer == address(0))
            revert EtrnaErrors.ZeroAddress();
        if (_epochCap == 0) revert EtrnaErrors.InvalidInput();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
        _grantRole(EXECUTOR_ROLE, admin);

        vibeToken = IVibeTokenMinter(_vibeToken);
        signer    = _signer;
        epochCap  = _epochCap;
    }

    // ═══════════════════════════════════════════════════════════════════
    //  EPOCH EXECUTION
    // ═══════════════════════════════════════════════════════════════════

    /**
     * @notice Execute a reward epoch — validate signature, enforce caps, mint VIBE.
     * @param epochId Monotonically increasing epoch identifier.
     * @param allocations Array of (address, amount) reward allocations.
     * @param sig EIP‑191 signature from the off‑chain rewards engine signer.
     */
    function executeEpoch(
        uint256           epochId,
        Allocation[] calldata allocations,
        bytes        calldata sig
    ) external onlyRole(EXECUTOR_ROLE) nonReentrant {
        // ── Replay protection ──
        if (epochExecuted[epochId]) revert EtrnaErrors.AlreadyExists();
        if (epochId <= lastEpochId) revert EtrnaErrors.InvalidInput();
        if (allocations.length == 0) revert EtrnaErrors.InvalidInput();

        // ── Signature validation ──
        bytes32 digest = _epochDigest(epochId, allocations);
        address recovered = digest.toEthSignedMessageHash().recover(sig);
        if (recovered != signer) revert EtrnaErrors.Unauthorized();

        // ── Sum and validate budget ──
        uint256 total;
        for (uint256 i; i < allocations.length; i++) {
            if (allocations[i].to == address(0)) revert EtrnaErrors.ZeroAddress();
            if (allocations[i].amount == 0) revert EtrnaErrors.InvalidInput();
            total += allocations[i].amount;
        }

        // Per‑epoch cap
        if (total > epochCap) revert EtrnaErrors.InvalidInput();

        // Cumulative budget
        if (totalBudget > 0 && totalMinted + total > totalBudget) {
            revert EtrnaErrors.InvalidInput();
        }

        // ── Mint VIBE ──
        for (uint256 i; i < allocations.length; i++) {
            vibeToken.mint(allocations[i].to, allocations[i].amount);
            emit AllocationMinted(epochId, allocations[i].to, allocations[i].amount);
        }

        // ── Record ──
        epochExecuted[epochId] = true;
        lastEpochId = epochId;
        totalMinted += total;

        epochs[epochId] = EpochRecord({
            epochId: epochId,
            totalDistributed: total,
            allocationCount: allocations.length,
            executedAt: uint64(block.timestamp),
            executor: msg.sender
        });

        emit EpochExecuted(epochId, total, allocations.length);
    }

    // ═══════════════════════════════════════════════════════════════════
    //  DIGEST
    // ═══════════════════════════════════════════════════════════════════

    function _epochDigest(
        uint256              epochId,
        Allocation[] calldata allocations
    ) internal view returns (bytes32) {
        // Chain‑specific digest prevents cross‑chain replay
        bytes memory packed = abi.encodePacked(
            block.chainid,
            address(this),
            epochId
        );
        for (uint256 i; i < allocations.length; i++) {
            packed = abi.encodePacked(packed, allocations[i].to, allocations[i].amount);
        }
        return keccak256(packed);
    }

    /**
     * @notice Compute the digest for a given epoch (view — for off‑chain signer).
     */
    function computeDigest(
        uint256              epochId,
        Allocation[] calldata allocations
    ) external view returns (bytes32) {
        return _epochDigest(epochId, allocations);
    }

    // ═══════════════════════════════════════════════════════════════════
    //  ADMIN
    // ═══════════════════════════════════════════════════════════════════

    function setSigner(address _signer) external onlyRole(ADMIN_ROLE) {
        if (_signer == address(0)) revert EtrnaErrors.ZeroAddress();
        address old = signer;
        signer = _signer;
        emit SignerUpdated(old, _signer);
    }

    function setEpochCap(uint256 _cap) external onlyRole(ADMIN_ROLE) {
        if (_cap == 0) revert EtrnaErrors.InvalidInput();
        uint256 old = epochCap;
        epochCap = _cap;
        emit EpochCapUpdated(old, _cap);
    }

    function setTotalBudget(uint256 _budget) external onlyRole(ADMIN_ROLE) {
        uint256 old = totalBudget;
        totalBudget = _budget;
        emit BudgetUpdated(old, _budget);
    }

    // ═══════════════════════════════════════════════════════════════════
    //  VIEW HELPERS
    // ═══════════════════════════════════════════════════════════════════

    function remainingBudget() external view returns (uint256) {
        if (totalBudget == 0) return type(uint256).max;
        if (totalMinted >= totalBudget) return 0;
        return totalBudget - totalMinted;
    }

    function isEpochExecuted(uint256 epochId) external view returns (bool) {
        return epochExecuted[epochId];
    }
}
