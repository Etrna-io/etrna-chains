// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/**
 * @title  VibeCheckMissions
 * @author ETRNA Technologies Inc.
 * @notice On-chain mission lifecycle for VibeCheck.
 *         Tracks mission creation, user progress, completions, and
 *         reward allocations.  UUPS-upgradeable behind an ERC-1967 proxy.
 */
contract VibeCheckMissions is Initializable, UUPSUpgradeable, OwnableUpgradeable {
    // ─── Types ──────────────────────────────────────────────────────────
    enum ProgressStatus {
        NotStarted,   // 0
        InProgress,   // 1
        Completed,    // 2
        Expired       // 3
    }

    struct Mission {
        uint8    missionType;       // 0=check-in, 1=rating, 2=social, 3=exploration
        bytes32  venueId;           // scoped venue (0x0 = global)
        uint256  baseRewardUnits;   // base reward in smallest unit
        uint256  bonusMultiplier;   // basis points (10000 = 1×)
        uint256  startAt;
        uint256  endAt;
        uint256  maxCompletions;
        uint256  currentCompletions;
    }

    struct UserProgress {
        address  user;
        uint256  progress;       // basis points (10000 = 100%)
        ProgressStatus status;
        uint256  completedAt;
        uint256  rewardUnits;
    }

    // ─── Storage ────────────────────────────────────────────────────────
    mapping(bytes32 => Mission)                          private _missions;
    mapping(bytes32 => mapping(address => UserProgress)) private _progress;
    mapping(address => bytes32[])                        private _userMissions;

    uint256 public totalMissions;
    uint256 public totalCompletions;

    // ─── Events ─────────────────────────────────────────────────────────
    event MissionCreated(
        bytes32 indexed missionId,
        uint8   missionType,
        bytes32 indexed venueId,
        uint256 baseRewardUnits,
        uint256 startAt,
        uint256 endAt
    );

    event MissionCompleted(
        bytes32 indexed missionId,
        address indexed user,
        uint256 rewardUnits
    );

    event MissionExpired(
        bytes32 indexed missionId
    );

    // ─── Initializer ───────────────────────────────────────────────────
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() external initializer {
        __Ownable_init();
        __UUPSUpgradeable_init();
    }

    // ─── Mission Lifecycle ──────────────────────────────────────────────
    /**
     * @notice Create a new mission (owner only).
     */
    function createMission(
        bytes32 missionId,
        uint8   missionType,
        bytes32 venueId,
        uint256 baseRewardUnits,
        uint256 bonusMultiplier,
        uint256 startAt,
        uint256 endAt,
        uint256 maxCompletions
    ) external onlyOwner {
        require(_missions[missionId].endAt == 0, "VM: mission exists");
        require(endAt > startAt, "VM: invalid window");
        require(maxCompletions > 0, "VM: zero completions");

        _missions[missionId] = Mission({
            missionType:        missionType,
            venueId:            venueId,
            baseRewardUnits:    baseRewardUnits,
            bonusMultiplier:    bonusMultiplier,
            startAt:            startAt,
            endAt:              endAt,
            maxCompletions:     maxCompletions,
            currentCompletions: 0
        });

        totalMissions++;
        emit MissionCreated(missionId, missionType, venueId, baseRewardUnits, startAt, endAt);
    }

    /**
     * @notice Update a user's progress on a mission (owner only).
     *         Automatically completes the mission if progress >= 10000 bps.
     */
    function updateProgress(
        bytes32 missionId,
        address user,
        uint256 progressBps
    ) external onlyOwner {
        Mission storage m = _missions[missionId];
        require(m.endAt != 0, "VM: unknown mission");
        require(block.timestamp >= m.startAt && block.timestamp <= m.endAt, "VM: outside window");
        require(m.currentCompletions < m.maxCompletions, "VM: max completions");

        UserProgress storage up = _progress[missionId][user];

        // First interaction — register
        if (up.status == ProgressStatus.NotStarted) {
            up.user = user;
            up.status = ProgressStatus.InProgress;
            _userMissions[user].push(missionId);
        }

        require(up.status == ProgressStatus.InProgress, "VM: not in progress");
        up.progress = progressBps;

        // Auto-complete at 100%
        if (progressBps >= 10_000) {
            up.status = ProgressStatus.Completed;
            up.completedAt = block.timestamp;
            up.rewardUnits = (m.baseRewardUnits * m.bonusMultiplier) / 10_000;
            m.currentCompletions++;
            totalCompletions++;
            emit MissionCompleted(missionId, user, up.rewardUnits);
        }
    }

    /**
     * @notice Mark a mission as expired (owner only).
     */
    function expireMission(bytes32 missionId) external onlyOwner {
        Mission storage m = _missions[missionId];
        require(m.endAt != 0, "VM: unknown mission");
        m.endAt = block.timestamp;   // close the window
        emit MissionExpired(missionId);
    }

    // ─── View Functions ─────────────────────────────────────────────────
    function getMission(bytes32 missionId)
        external
        view
        returns (
            uint8   missionType,
            bytes32 venueId,
            uint256 baseRewardUnits,
            uint256 bonusMultiplier,
            uint256 startAt,
            uint256 endAt,
            uint256 maxCompletions,
            uint256 currentCompletions
        )
    {
        Mission storage m = _missions[missionId];
        return (
            m.missionType,
            m.venueId,
            m.baseRewardUnits,
            m.bonusMultiplier,
            m.startAt,
            m.endAt,
            m.maxCompletions,
            m.currentCompletions
        );
    }

    function getUserProgress(bytes32 missionId, address user)
        external
        view
        returns (
            address  user_,
            uint256  progress,
            uint8    status,
            uint256  completedAt,
            uint256  rewardUnits
        )
    {
        UserProgress storage up = _progress[missionId][user];
        return (up.user, up.progress, uint8(up.status), up.completedAt, up.rewardUnits);
    }

    function getUserMissions(address user) external view returns (bytes32[] memory) {
        return _userMissions[user];
    }

    function isMissionActive(bytes32 missionId) external view returns (bool) {
        Mission storage m = _missions[missionId];
        return m.endAt != 0
            && block.timestamp >= m.startAt
            && block.timestamp <= m.endAt
            && m.currentCompletions < m.maxCompletions;
    }

    // ─── Storage Gap ────────────────────────────────────────────────────
    uint256[50] private __gap;

    // ─── UUPS Upgrade Auth ──────────────────────────────────────────────
    function _authorizeUpgrade(address) internal override onlyOwner {}
}
