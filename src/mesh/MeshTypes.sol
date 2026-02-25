// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title MeshTypes
/// @notice Shared types for Etrna Modular Mesh (intent-based execution).
library MeshTypes {
    enum IntentStatus {
        NONE,
        PENDING,
        ROUTED,
        COMPLETED,
        FAILED
    }

    enum ActionType {
        UNKNOWN,
        MINT_NFT,
        STAKE,
        UNSTAKE,
        BRIDGE,
        SWAP
    }

    /// @notice Intent represents a user-declared desired outcome; off-chain routing produces routeData for adapters.
    struct Intent {
        address creator;
        ActionType actionType;
        uint256 srcChainId;
        uint256 dstChainId;
        address asset;
        uint256 amount;
        bytes32 paramsHash;
        IntentStatus status;
        uint256 createdAt;
    }
}
