// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";

import {EtrnaErrors} from "../lib/EtrnaErrors.sol";

/**
 * @title BlueprintRegistry
 * @notice On-chain registry of EtrnaVerse blueprint definitions.
 *
 * Each blueprint entry stores:
 *  - id (bytes32 hash derived off-chain)
 *  - creator (wallet that registered it)
 *  - metadataHash (IPFS CID or content hash)
 *  - layer (infra / social / economic / environmental)
 *  - active flag
 *  - simScore (updated by oracle after simulation)
 *
 * Blueprints are immutable once registered — only the simScore and active
 * flag can be updated.
 */
contract BlueprintRegistry is AccessControl {
    bytes32 public constant REGISTRAR_ROLE = keccak256("REGISTRAR_ROLE");
    bytes32 public constant ORACLE_ROLE = keccak256("ORACLE_ROLE");

    struct Blueprint {
        address creator;
        bytes32 metadataHash;
        bytes32 layer;
        uint64 registeredAt;
        uint32 simScore;      // 0-10000 (basis points)
        bool active;
    }

    mapping(bytes32 => Blueprint) public blueprints;
    bytes32[] public blueprintIds;

    event BlueprintRegistered(bytes32 indexed blueprintId, address indexed creator, bytes32 layer, bytes32 metadataHash);
    event BlueprintDeactivated(bytes32 indexed blueprintId);
    event BlueprintReactivated(bytes32 indexed blueprintId);
    event SimScoreUpdated(bytes32 indexed blueprintId, uint32 oldScore, uint32 newScore);

    constructor(address admin) {
        if (admin == address(0)) revert EtrnaErrors.ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(REGISTRAR_ROLE, admin);
        _grantRole(ORACLE_ROLE, admin);
    }

    // ─── Registration ──────────────────────────────────────────────────

    function register(
        bytes32 blueprintId,
        address creator,
        bytes32 metadataHash,
        bytes32 layer
    ) external onlyRole(REGISTRAR_ROLE) {
        if (blueprintId == bytes32(0) || creator == address(0)) revert EtrnaErrors.ZeroAddress();
        if (metadataHash == bytes32(0)) revert EtrnaErrors.InvalidInput();
        if (blueprints[blueprintId].creator != address(0)) revert EtrnaErrors.AlreadyExists();

        blueprints[blueprintId] = Blueprint({
            creator: creator,
            metadataHash: metadataHash,
            layer: layer,
            registeredAt: uint64(block.timestamp),
            simScore: 0,
            active: true
        });

        blueprintIds.push(blueprintId);
        emit BlueprintRegistered(blueprintId, creator, layer, metadataHash);
    }

    // ─── Lifecycle ─────────────────────────────────────────────────────

    function deactivate(bytes32 blueprintId) external onlyRole(REGISTRAR_ROLE) {
        Blueprint storage bp = blueprints[blueprintId];
        if (bp.creator == address(0)) revert EtrnaErrors.NotFound();
        if (!bp.active) revert EtrnaErrors.InvalidState();
        bp.active = false;
        emit BlueprintDeactivated(blueprintId);
    }

    function reactivate(bytes32 blueprintId) external onlyRole(REGISTRAR_ROLE) {
        Blueprint storage bp = blueprints[blueprintId];
        if (bp.creator == address(0)) revert EtrnaErrors.NotFound();
        if (bp.active) revert EtrnaErrors.InvalidState();
        bp.active = true;
        emit BlueprintReactivated(blueprintId);
    }

    // ─── Oracle updates ────────────────────────────────────────────────

    function updateSimScore(bytes32 blueprintId, uint32 newScore) external onlyRole(ORACLE_ROLE) {
        if (newScore > 10000) revert EtrnaErrors.InvalidInput();
        Blueprint storage bp = blueprints[blueprintId];
        if (bp.creator == address(0)) revert EtrnaErrors.NotFound();

        uint32 oldScore = bp.simScore;
        bp.simScore = newScore;
        emit SimScoreUpdated(blueprintId, oldScore, newScore);
    }

    // ─── Views ─────────────────────────────────────────────────────────

    function getBlueprintCount() external view returns (uint256) {
        return blueprintIds.length;
    }

    function isActive(bytes32 blueprintId) external view returns (bool) {
        return blueprints[blueprintId].active;
    }

    function getBlueprint(bytes32 blueprintId)
        external
        view
        returns (
            address creator,
            bytes32 metadataHash,
            bytes32 layer,
            uint64 registeredAt,
            uint32 simScore,
            bool active
        )
    {
        Blueprint storage bp = blueprints[blueprintId];
        return (bp.creator, bp.metadataHash, bp.layer, bp.registeredAt, bp.simScore, bp.active);
    }
}
