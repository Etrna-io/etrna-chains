// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "openzeppelin-contracts/access/AccessControl.sol";

import {EtrnaErrors} from "../lib/EtrnaErrors.sol";

/**
 * @title RealityState
 * @notice Minimal state registry derived from RealityLedger assertions.
 *
 * v0: role-gated state updates. In later versions, this can be driven by
 * probabilistic consensus or solver networks, with proofs of derivation.
 */
contract RealityState is AccessControl {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant STATE_WRITER_ROLE = keccak256("STATE_WRITER_ROLE");

    event StateSet(bytes32 indexed topic, bytes32 indexed key, bytes32 value, address indexed writer);

    // topic => key => value
    mapping(bytes32 => mapping(bytes32 => bytes32)) public state;

    constructor(address admin) {
        if (admin == address(0)) revert EtrnaErrors.ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
        _grantRole(STATE_WRITER_ROLE, admin);
    }

    function setState(bytes32 topic, bytes32 key, bytes32 value) external onlyRole(STATE_WRITER_ROLE) {
        if (topic == bytes32(0) || key == bytes32(0)) revert EtrnaErrors.InvalidInput();
        state[topic][key] = value;
        emit StateSet(topic, key, value, msg.sender);
    }

    function grantStateWriter(address writer) external onlyRole(ADMIN_ROLE) {
        if (writer == address(0)) revert EtrnaErrors.ZeroAddress();
        _grantRole(STATE_WRITER_ROLE, writer);
    }
}
