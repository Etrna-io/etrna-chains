// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {MeshTypes} from "../mesh/MeshTypes.sol";

/// @title IMeshHub
/// @notice Canonical interface for the Etrna Modular Mesh intent-based execution hub.
/// @dev Kept in sync with MeshHub.sol's external API.
interface IMeshHub {
    event IntentCreated(
        bytes32 indexed intentId,
        address indexed creator,
        MeshTypes.ActionType actionType,
        uint256 srcChainId,
        uint256 dstChainId,
        bytes32 paramsHash
    );
    event IntentRouted(bytes32 indexed intentId, address indexed executor, uint256 dstChainId, bytes routeData);
    event IntentCompleted(bytes32 indexed intentId, bytes32 dstTxHash);
    event IntentFailed(bytes32 indexed intentId, string reason);

    function createIntent(
        MeshTypes.ActionType actionType,
        uint256 dstChainId,
        address asset,
        uint256 amount,
        bytes32 paramsHash
    ) external payable returns (bytes32);

    function markRouted(bytes32 intentId, bytes calldata routeData) external;
    function markCompleted(bytes32 intentId, bytes32 dstTxHash) external;
    function markFailed(bytes32 intentId, string calldata reason) external;

    function getIntent(bytes32 intentId) external view returns (MeshTypes.Intent memory);
    function adapters(uint256 chainId, bytes4 actionSelector) external view returns (address);
    function setAdapter(uint256 chainId, bytes4 actionSelector, address adapter) external;
    function routerBackend() external view returns (address);
    function setRouterBackend(address _routerBackend) external;
}
