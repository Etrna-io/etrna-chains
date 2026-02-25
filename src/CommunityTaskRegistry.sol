// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title CommunityTaskRegistry
 * @notice Registry of community-improvement tasks published by verified businesses.
 * @dev Emits events consumed by off-chain services (VibeCheck + Rewards Engine).
 */
interface ICommunityPass {
    function cityPassOf(uint32 cityId, address wallet) external view returns (uint256);
    function isActive(uint256 tokenId) external view returns (bool);
}

contract CommunityTaskRegistry is AccessControl {
    bytes32 public constant CITY_ADMIN_ROLE = keccak256("CITY_ADMIN_ROLE");
    bytes32 public constant BUSINESS_ROLE = keccak256("BUSINESS_ROLE");

    ICommunityPass public communityPass;

    struct Task {
        uint256 id;
        address creator;
        uint32 cityId;
        uint64 createdAt;
        uint64 expiresAt;
        uint32 rewardXP;
        bool active;
    }

    uint256 public nextTaskId = 1;
    mapping(uint256 => Task) public tasks;
    mapping(uint256 => mapping(address => bool)) public completedBy;

    event TaskCreated(
        uint256 indexed id,
        address indexed creator,
        uint32 indexed cityId,
        uint32 rewardXP,
        uint64 expiresAt
    );
    event TaskDeactivated(uint256 indexed id);
    event TaskCompleted(
        uint256 indexed id,
        address indexed account,
        uint32 indexed cityId,
        uint32 rewardXP
    );

    constructor(address admin, address communityPass_) {
        require(admin != address(0), "CommunityTaskRegistry: admin is zero");
        require(communityPass_ != address(0), "CommunityTaskRegistry: pass is zero");
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(CITY_ADMIN_ROLE, admin);
        communityPass = ICommunityPass(communityPass_);
    }

    // ------------ Role management ------------

    function grantCityAdmin(address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(CITY_ADMIN_ROLE, account);
    }

    function grantBusiness(address account) external onlyRole(CITY_ADMIN_ROLE) {
        _grantRole(BUSINESS_ROLE, account);
    }

    // ------------ Task lifecycle ------------

    function createTask(
        uint32 cityId,
        uint32 rewardXP,
        uint64 expiresAt
    ) external onlyRole(BUSINESS_ROLE) returns (uint256 id) {
        require(cityId != 0, "CommunityTaskRegistry: cityId required");
        require(rewardXP > 0, "CommunityTaskRegistry: rewardXP required");

        id = nextTaskId++;
        Task memory t = Task({
            id: id,
            creator: msg.sender,
            cityId: cityId,
            createdAt: uint64(block.timestamp),
            expiresAt: expiresAt,
            rewardXP: rewardXP,
            active: true
        });
        tasks[id] = t;

        emit TaskCreated(id, msg.sender, cityId, rewardXP, expiresAt);
    }

    function deactivateTask(uint256 id) external {
        Task storage t = tasks[id];
        require(t.id != 0, "CommunityTaskRegistry: no task");
        require(
            hasRole(CITY_ADMIN_ROLE, msg.sender) || msg.sender == t.creator,
            "CommunityTaskRegistry: not authorized"
        );
        require(t.active, "CommunityTaskRegistry: already inactive");
        t.active = false;
        emit TaskDeactivated(id);
    }

    function completeTask(uint256 id) external {
        Task memory t = tasks[id];
        require(t.id != 0, "CommunityTaskRegistry: no task");
        require(t.active, "CommunityTaskRegistry: inactive");
        require(!completedBy[id][msg.sender], "CommunityTaskRegistry: already completed");
        if (t.expiresAt != 0) {
            require(block.timestamp <= t.expiresAt, "CommunityTaskRegistry: expired");
        }

        // Residency gate: caller must hold an active CommunityPass for this city
        uint256 passId = communityPass.cityPassOf(t.cityId, msg.sender);
        require(passId != 0, "CommunityTaskRegistry: no pass for city");
        require(communityPass.isActive(passId), "CommunityTaskRegistry: pass inactive");

        completedBy[id][msg.sender] = true;
        emit TaskCompleted(id, msg.sender, t.cityId, t.rewardXP);
        // Off-chain rewards engine will listen for TaskCompleted and mint VIBE accordingly.
    }
}
