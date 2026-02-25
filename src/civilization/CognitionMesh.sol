// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "openzeppelin-contracts/access/AccessControl.sol";

import {EtrnaErrors} from "../lib/EtrnaErrors.sol";

/**
 * @title CognitionMesh
 * @notice On-chain registry for cognitive tasks and performance scoring.
 *
 * v0 provides:
 * - task submission (hash pointers)
 * - task assignment bookkeeping
 * - accuracy score updates (role-gated)
 */
contract CognitionMesh is AccessControl {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant ROUTER_ROLE = keccak256("ROUTER_ROLE");
    bytes32 public constant SCORER_ROLE = keccak256("SCORER_ROLE");

    event TaskCreated(uint256 indexed taskId, address indexed creator, bytes32 indexed kind, bytes32 payloadHash);
    event TaskAssigned(uint256 indexed taskId, address indexed worker);
    event TaskCompleted(uint256 indexed taskId, bytes32 resultHash);
    event WorkerScored(address indexed worker, int256 deltaBps, int256 newScoreBps);

    struct Task {
        address creator;
        address worker;
        uint64 createdAt;
        uint64 completedAt;
        bytes32 kind;        // e.g., ANALYTICAL, CREATIVE, ETHICAL, PREDICTIVE
        bytes32 payloadHash; // off-chain payload anchor
        bytes32 resultHash;  // off-chain result anchor
    }

    uint256 public nextTaskId;
    mapping(uint256 => Task) public tasks;

    // Worker score in basis points, centered at 0. Positive = historically accurate.
    mapping(address => int256) public workerScoreBps;

    constructor(address admin) {
        if (admin == address(0)) revert EtrnaErrors.ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
        _grantRole(ROUTER_ROLE, admin);
        _grantRole(SCORER_ROLE, admin);
    }

    function createTask(bytes32 kind, bytes32 payloadHash) external returns (uint256 taskId) {
        if (kind == bytes32(0) || payloadHash == bytes32(0)) revert EtrnaErrors.InvalidInput();
        taskId = ++nextTaskId;
        tasks[taskId] = Task({
            creator: msg.sender,
            worker: address(0),
            createdAt: uint64(block.timestamp),
            completedAt: 0,
            kind: kind,
            payloadHash: payloadHash,
            resultHash: bytes32(0)
        });
        emit TaskCreated(taskId, msg.sender, kind, payloadHash);
    }

    function assignTask(uint256 taskId, address worker) external onlyRole(ROUTER_ROLE) {
        if (worker == address(0)) revert EtrnaErrors.ZeroAddress();
        Task storage t = tasks[taskId];
        if (t.creator == address(0)) revert EtrnaErrors.NotFound();
        if (t.worker != address(0)) revert EtrnaErrors.AlreadyExists();
        t.worker = worker;
        emit TaskAssigned(taskId, worker);
    }

    function completeTask(uint256 taskId, bytes32 resultHash) external {
        Task storage t = tasks[taskId];
        if (t.creator == address(0)) revert EtrnaErrors.NotFound();
        if (t.worker != msg.sender) revert EtrnaErrors.Unauthorized();
        if (t.completedAt != 0) revert EtrnaErrors.InvalidState();
        if (resultHash == bytes32(0)) revert EtrnaErrors.InvalidInput();

        t.resultHash = resultHash;
        t.completedAt = uint64(block.timestamp);
        emit TaskCompleted(taskId, resultHash);
    }

    function scoreWorker(address worker, int256 deltaBps) external onlyRole(SCORER_ROLE) {
        if (worker == address(0)) revert EtrnaErrors.ZeroAddress();
        int256 next = workerScoreBps[worker] + deltaBps;
        // clamp to [-10000,10000]
        if (next > 10000) next = 10000;
        if (next < -10000) next = -10000;
        workerScoreBps[worker] = next;
        emit WorkerScored(worker, deltaBps, next);
    }
}
