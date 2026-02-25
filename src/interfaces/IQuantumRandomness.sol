// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IQuantumRandomness
/// @notice Auditable authorized randomness fulfilment (Quantum Relay).
interface IQuantumRandomness {
    event RandomnessRequested(uint256 indexed requestId, address indexed requester, bytes32 purpose);
    event RandomnessFulfilled(uint256 indexed requestId, bytes32 randomness);

    function requestRandomness(bytes32 purpose) external returns (uint256 requestId);
    function fulfillRandomness(uint256 requestId, bytes32 randomness, bytes calldata fulfillerSig) external;
}
