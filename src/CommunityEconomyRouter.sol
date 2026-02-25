// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title CommunityEconomyRouter
 * @notice Thin on-chain router to distribute city-level rewards via an external RewardDistributor.
 * @dev Designed to be called by an off-chain service that has computed per-resident amounts.
 */
interface IRewardDistributor {
    function distributeReward(address to, uint256 amount) external;
}

contract CommunityEconomyRouter is AccessControl, ReentrancyGuard {
    bytes32 public constant DISTRIBUTOR_ROLE = keccak256("DISTRIBUTOR_ROLE");

    IRewardDistributor public immutable rewardDistributor;

    event CityRewardBatch(
        uint32 indexed cityId,
        uint256 indexed epochId,
        uint256 residents,
        uint256 totalAmount
    );

    constructor(address admin, address rewardDistributor_) {
        require(admin != address(0), "CommunityEconomyRouter: admin is zero");
        require(rewardDistributor_ != address(0), "CommunityEconomyRouter: distributor is zero");
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(DISTRIBUTOR_ROLE, admin);
        rewardDistributor = IRewardDistributor(rewardDistributor_);
    }

    /**
     * @notice Distribute pre-computed rewards to a batch of residents for a given city + epoch.
     * @dev Intended to be called by a backend service in small batches to avoid gas limits.
     */
    uint256 public constant MAX_BATCH_SIZE = 200;

    function distributeCityRewards(
        uint32 cityId,
        uint256 epochId,
        address[] calldata residents,
        uint256[] calldata amounts
    ) external onlyRole(DISTRIBUTOR_ROLE) nonReentrant {
        require(cityId != 0, "CommunityEconomyRouter: cityId required");
        require(residents.length == amounts.length, "CommunityEconomyRouter: length mismatch");
        require(residents.length <= MAX_BATCH_SIZE, "CommunityEconomyRouter: batch too large");
        uint256 totalAmount;
        for (uint256 i = 0; i < residents.length; i++) {
            address to = residents[i];
            uint256 amt = amounts[i];
            if (to == address(0) || amt == 0) continue;
            rewardDistributor.distributeReward(to, amt);
            totalAmount += amt;
        }
        emit CityRewardBatch(cityId, epochId, residents.length, totalAmount);
    }
}
