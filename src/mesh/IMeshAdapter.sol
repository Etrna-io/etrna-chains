// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IMeshAdapter
/// @notice Adapter interface for executing a routed intent on a destination chain.
interface IMeshAdapter {
    function execute(bytes32 intentId, bytes calldata routeData) external;
}
