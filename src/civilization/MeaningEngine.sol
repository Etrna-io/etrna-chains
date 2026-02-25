// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "openzeppelin-contracts/access/AccessControl.sol";

import {ValueSignalAggregator} from "./ValueSignalAggregator.sol";
import {EtrnaErrors} from "../lib/EtrnaErrors.sol";

/**
 * @title MeaningEngine
 * @notice Computes Meaning Score deltas from physics-level signals and reality accuracy.
 *
 * v0:
 * - Governance sets weights for signal codes
 * - Oracle sets per-epoch signals
 * - Anyone can query derived meaning for a subject
 */
contract MeaningEngine is AccessControl {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    event WeightSet(bytes32 indexed signalCode, int256 weightBps);

    ValueSignalAggregator public immutable aggregator;

    // signalCode => weightBps (can be negative)
    mapping(bytes32 => int256) public weights;

    constructor(address admin, address aggregator_) {
        if (admin == address(0) || aggregator_ == address(0)) revert EtrnaErrors.ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
        aggregator = ValueSignalAggregator(aggregator_);
    }

    function setWeight(bytes32 signalCode, int256 weightBps) external onlyRole(ADMIN_ROLE) {
        if (signalCode == bytes32(0)) revert EtrnaErrors.InvalidInput();
        if (weightBps > 10000) weightBps = 10000;
        if (weightBps < -10000) weightBps = -10000;
        weights[signalCode] = weightBps;
        emit WeightSet(signalCode, weightBps);
    }

    /// @notice Computes meaning for a subject in an epoch as a weighted sum of signals.
    /// This is a deterministic "first pass" scorer; future versions will incorporate
    /// trajectory, drift, and narrative alignment.
    function meaningBps(uint64 epoch, address subject, bytes32[] calldata signalCodes) external view returns (int256) {
        if (epoch == 0) revert EtrnaErrors.InvalidInput();
        if (subject == address(0)) revert EtrnaErrors.ZeroAddress();

        int256 total;
        for (uint256 i = 0; i < signalCodes.length; i++) {
            bytes32 code = signalCodes[i];
            int256 v = aggregator.signals(epoch, code, subject);
            int256 w = weights[code];
            // v and w are bps, scale back to bps with /10000
            total += (v * w) / 10000;
        }
        // clamp
        if (total > 10000) total = 10000;
        if (total < -10000) total = -10000;
        return total;
    }
}
