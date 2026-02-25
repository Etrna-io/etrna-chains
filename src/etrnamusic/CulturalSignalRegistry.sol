// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "openzeppelin-contracts/access/AccessControl.sol";

import {EtrnaErrors} from "../lib/EtrnaErrors.sol";
import {EtrnaMusicTypes} from "./EtrnaMusicTypes.sol";

/**
 * @title CulturalSignalRegistry
 * @notice On-chain anchor for normalized cultural signal batches.
 *
 * v1 posture:
 * - Hash-first anchoring. Raw data remains off-chain.
 * - ORACLE_ROLE submits signal batches.
 * - Optional summarized metrics are stored for transparency and quick reads.
 */
contract CulturalSignalRegistry is AccessControl {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant ORACLE_ROLE = keccak256("ORACLE_ROLE");

    struct SignalBatch {
        uint256 setId;
        uint64 epoch;
        bytes32 signalHash;
        EtrnaMusicTypes.SignalSummary summary;
    }

    uint256 public nextBatchId;
    mapping(uint256 => SignalBatch) public batches; // batchId => batch
    mapping(uint256 => mapping(uint64 => uint256)) public batchIdOf; // setId => epoch => batchId

    event SignalBatchSubmitted(
        uint256 indexed batchId,
        uint256 indexed setId,
        uint64 indexed epoch,
        bytes32 signalHash,
        int16 attentionBps,
        int16 syncBps,
        int16 momentumBps,
        int16 localityBps,
        int16 densityBps
    );

    constructor(address admin) {
        if (admin == address(0)) revert EtrnaErrors.ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
        _grantRole(ORACLE_ROLE, admin);
    }

    function submitSignalBatch(
        uint256 setId,
        uint64 epoch,
        bytes32 signalHash,
        EtrnaMusicTypes.SignalSummary calldata summary
    ) external onlyRole(ORACLE_ROLE) returns (uint256 batchId) {
        if (setId == 0 || epoch == 0 || signalHash == bytes32(0)) revert EtrnaErrors.InvalidInput();
        if (batchIdOf[setId][epoch] != 0) revert EtrnaErrors.AlreadyExists();

        batchId = ++nextBatchId;
        batches[batchId] = SignalBatch({setId: setId, epoch: epoch, signalHash: signalHash, summary: summary});
        batchIdOf[setId][epoch] = batchId;

        emit SignalBatchSubmitted(
            batchId,
            setId,
            epoch,
            signalHash,
            summary.attentionBps,
            summary.syncBps,
            summary.momentumBps,
            summary.localityBps,
            summary.densityBps
        );
    }
}
