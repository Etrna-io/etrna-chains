// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Minimal interface for Etrna Quantum Relay v1.
interface IQuantumRelay {
    function requestRandomness() external returns (uint256 requestId);
    function getRandomness(uint256 requestId) external view returns (bytes32 value, bool fulfilled);
}
