// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./QuantumRandomness.sol";

/// @title QuantumConsumerBase
/// @notice Base contract for consumers of QuantumRandomness.
abstract contract QuantumConsumerBase {
    QuantumRandomness public immutable quantumRandomness;

    mapping(bytes32 => bool) internal pendingRequests;

    event QuantumRandomnessRequested(bytes32 indexed requestId);
    event QuantumRandomnessConsumed(bytes32 indexed requestId, uint256 randomValue);

    constructor(address qrAddress) {
        require(qrAddress != address(0), "QuantumConsumerBase: zero address");
        quantumRandomness = QuantumRandomness(qrAddress);
    }

    function _requestQuantumRandomness() internal returns (bytes32) {
        bytes32 requestId = quantumRandomness.requestRandomness();
        pendingRequests[requestId] = true;
        emit QuantumRandomnessRequested(requestId);
        return requestId;
    }

    function _consumeQuantumRandomness(bytes32 requestId) internal returns (uint256) {
        require(pendingRequests[requestId], "QuantumConsumerBase: not pending");
        QuantumRandomness.Request memory r = quantumRandomness.readRandomness(requestId);
        require(r.fulfilled, "QuantumConsumerBase: not fulfilled");
        delete pendingRequests[requestId];
        emit QuantumRandomnessConsumed(requestId, r.randomValue);
        return r.randomValue;
    }
}
