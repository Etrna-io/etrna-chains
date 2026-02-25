// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IRewardsDistributor
/// @notice On-chain distributor that mints VIBE (MINTER_ROLE) and disperses per epoch.
/// @dev Off-chain Rewards Engine computes allocations; on-chain validates signatures and mints.
interface IRewardsDistributor {
    struct Allocation {
        address to;
        uint256 amount;
    }

    event EpochExecuted(uint256 indexed epochId, uint256 totalDistributed);

    function executeEpoch(uint256 epochId, Allocation[] calldata allocations, bytes calldata adminSig) external;
}
