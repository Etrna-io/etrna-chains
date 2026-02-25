// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "openzeppelin-contracts/access/AccessControl.sol";

import {EtrnaErrors} from "../lib/EtrnaErrors.sol";

/**
 * @title ValueSignalAggregator (PLE)
 * @notice Aggregates physics-level economic signals used by higher-layer modules.
 *
 * Signals are recorded as int256 basis points per epoch for a subject (user/city/org).
 *
 * Typical signals:
 * - ENERGY_BPS: normalized energy contribution/consumption efficiency
 * - TIME_BPS: time commitments fulfilled
 * - TRUTH_BPS: reality ledger accuracy
 * - COORD_BPS: coordination efficiency
 */
contract ValueSignalAggregator is AccessControl {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant ORACLE_ROLE = keccak256("ORACLE_ROLE");

    event SignalSet(uint64 indexed epoch, bytes32 indexed signalCode, address indexed subject, int256 valueBps);

    // epoch => signalCode => subject => valueBps
    mapping(uint64 => mapping(bytes32 => mapping(address => int256))) public signals;

    constructor(address admin) {
        if (admin == address(0)) revert EtrnaErrors.ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
        _grantRole(ORACLE_ROLE, admin);
    }

    function setSignal(uint64 epoch, bytes32 signalCode, address subject, int256 valueBps) external onlyRole(ORACLE_ROLE) {
        if (epoch == 0) revert EtrnaErrors.InvalidInput();
        if (signalCode == bytes32(0)) revert EtrnaErrors.InvalidInput();
        if (subject == address(0)) revert EtrnaErrors.ZeroAddress();
        if (valueBps > 10000) valueBps = 10000;
        if (valueBps < -10000) valueBps = -10000;

        signals[epoch][signalCode][subject] = valueBps;
        emit SignalSet(epoch, signalCode, subject, valueBps);
    }
}
