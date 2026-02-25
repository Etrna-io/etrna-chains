// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

/**
 * @title EtrnaNodeRegistry
 * @notice On-chain registry for ETRNA device-as-node network.
 *         Tracks node registration, heartbeats, tiers, and $VIBE multipliers.
 * @dev Emits events for off-chain indexer to sync with PostgreSQL.
 */
contract EtrnaNodeRegistry is Ownable, ReentrancyGuard, Pausable {

    // ── Enums ──
    enum NodeStatus { INACTIVE, ACTIVE, PAUSED, SLASHED }
    enum NodeTier { SPARK, PULSE, SIGNAL, BEACON, NEXUS }

    // ── Structs ──
    struct NodeInfo {
        address operator;
        string  deviceId;
        NodeStatus status;
        NodeTier tier;
        uint256 registeredAt;
        uint256 lastHeartbeat;
        uint256 uptimeSeconds;
        uint256 totalRewards;
        uint16  multiplierBps;   // e.g. 15000 = 1.5x
        string  city;
        int32   lat;             // scaled by 1e6
        int32   lng;             // scaled by 1e6
    }

    // ── State ──
    uint256 public nodeCount;
    mapping(uint256 => NodeInfo) public nodes;
    mapping(address => uint256[]) public operatorNodes;
    mapping(bytes32 => uint256) public deviceToNode;  // keccak256(operator, deviceId) => nodeId

    uint256 public constant HEARTBEAT_INTERVAL = 5 minutes;
    uint256 public constant HEARTBEAT_GRACE = 15 minutes;

    // ── Tier thresholds (uptime seconds) ──
    uint256[5] public tierThresholds = [
        0,          // SPARK
        86400,      // PULSE — 1 day
        604800,     // SIGNAL — 7 days
        2592000,    // BEACON — 30 days
        7776000     // NEXUS — 90 days
    ];

    // ── Events (for off-chain indexer) ──
    event NodeRegistered(uint256 indexed nodeId, address indexed operator, string deviceId, string city, uint256 timestamp);
    event NodeActivated(uint256 indexed nodeId, address indexed operator, uint256 timestamp);
    event NodeDeactivated(uint256 indexed nodeId, address indexed operator, uint256 timestamp);
    event NodePaused(uint256 indexed nodeId, address indexed operator, uint256 timestamp);
    event Heartbeat(uint256 indexed nodeId, address indexed operator, uint256 uptimeSeconds, uint256 timestamp);
    event TierUpgraded(uint256 indexed nodeId, NodeTier oldTier, NodeTier newTier, uint256 timestamp);
    event RewardClaimed(uint256 indexed nodeId, address indexed operator, uint256 amount, uint256 timestamp);
    event NodeSlashed(uint256 indexed nodeId, string reason, uint256 timestamp);
    event MultiplierUpdated(uint256 indexed nodeId, uint16 oldBps, uint16 newBps, uint256 timestamp);

    constructor() Ownable() {}

    // ═══════════════════════════════════════════════════════════════════════
    //  REGISTRATION
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Register a new node for the caller's address.
     * @param deviceId Unique device identifier (e.g. hardware fingerprint)
     * @param city City name for geo-mapping
     * @param lat Latitude × 1e6 (e.g. 43651070 for 43.651070)
     * @param lng Longitude × 1e6
     */
    function registerNode(
        string calldata deviceId,
        string calldata city,
        int32 lat,
        int32 lng
    ) external whenNotPaused returns (uint256 nodeId) {
        bytes32 deviceKey = keccak256(abi.encodePacked(msg.sender, deviceId));
        require(deviceToNode[deviceKey] == 0, "Device already registered");

        nodeCount++;
        nodeId = nodeCount;

        nodes[nodeId] = NodeInfo({
            operator: msg.sender,
            deviceId: deviceId,
            status: NodeStatus.ACTIVE,
            tier: NodeTier.SPARK,
            registeredAt: block.timestamp,
            lastHeartbeat: block.timestamp,
            uptimeSeconds: 0,
            totalRewards: 0,
            multiplierBps: 10000, // 1.0x base
            city: city,
            lat: lat,
            lng: lng
        });

        deviceToNode[deviceKey] = nodeId;
        operatorNodes[msg.sender].push(nodeId);

        emit NodeRegistered(nodeId, msg.sender, deviceId, city, block.timestamp);
        emit NodeActivated(nodeId, msg.sender, block.timestamp);
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  HEARTBEAT
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Submit a heartbeat proving the node is alive.
     *         Automatically upgrades tier based on cumulative uptime.
     */
    function heartbeat(uint256 nodeId) external whenNotPaused {
        NodeInfo storage node = nodes[nodeId];
        require(node.operator == msg.sender, "Not your node");
        require(node.status == NodeStatus.ACTIVE, "Node not active");

        uint256 elapsed = block.timestamp - node.lastHeartbeat;
        require(elapsed >= HEARTBEAT_INTERVAL, "Too soon");

        // Cap credited uptime at grace period to prevent gaming
        uint256 credited = elapsed > HEARTBEAT_GRACE ? HEARTBEAT_GRACE : elapsed;
        node.uptimeSeconds += credited;
        node.lastHeartbeat = block.timestamp;

        emit Heartbeat(nodeId, msg.sender, node.uptimeSeconds, block.timestamp);

        // Check tier upgrade
        _checkTierUpgrade(nodeId);
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  STATUS MANAGEMENT
    // ═══════════════════════════════════════════════════════════════════════

    function deactivateNode(uint256 nodeId) external {
        NodeInfo storage node = nodes[nodeId];
        require(node.operator == msg.sender, "Not your node");
        require(node.status == NodeStatus.ACTIVE, "Not active");
        node.status = NodeStatus.INACTIVE;
        emit NodeDeactivated(nodeId, msg.sender, block.timestamp);
    }

    function reactivateNode(uint256 nodeId) external whenNotPaused {
        NodeInfo storage node = nodes[nodeId];
        require(node.operator == msg.sender, "Not your node");
        require(node.status == NodeStatus.INACTIVE || node.status == NodeStatus.PAUSED, "Cannot reactivate");
        node.status = NodeStatus.ACTIVE;
        node.lastHeartbeat = block.timestamp;
        emit NodeActivated(nodeId, msg.sender, block.timestamp);
    }

    function pauseNode(uint256 nodeId) external {
        NodeInfo storage node = nodes[nodeId];
        require(node.operator == msg.sender, "Not your node");
        require(node.status == NodeStatus.ACTIVE, "Not active");
        node.status = NodeStatus.PAUSED;
        emit NodePaused(nodeId, msg.sender, block.timestamp);
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  ADMIN
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Slash a misbehaving node (admin only).
     */
    function slashNode(uint256 nodeId, string calldata reason) external onlyOwner {
        NodeInfo storage node = nodes[nodeId];
        require(node.status != NodeStatus.SLASHED, "Already slashed");
        node.status = NodeStatus.SLASHED;
        node.multiplierBps = 5000; // 0.5x penalty
        emit NodeSlashed(nodeId, reason, block.timestamp);
    }

    /**
     * @notice Update multiplier for a node (admin or automated reward system).
     */
    function setMultiplier(uint256 nodeId, uint16 newBps) external onlyOwner {
        NodeInfo storage node = nodes[nodeId];
        uint16 oldBps = node.multiplierBps;
        node.multiplierBps = newBps;
        emit MultiplierUpdated(nodeId, oldBps, newBps, block.timestamp);
    }

    /**
     * @notice Update tier thresholds.
     */
    function setTierThresholds(uint256[5] calldata newThresholds) external onlyOwner {
        tierThresholds = newThresholds;
    }

    function pause() external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }

    // ═══════════════════════════════════════════════════════════════════════
    //  VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    function getNode(uint256 nodeId) external view returns (NodeInfo memory) {
        return nodes[nodeId];
    }

    function getOperatorNodes(address operator) external view returns (uint256[] memory) {
        return operatorNodes[operator];
    }

    function getOperatorNodeCount(address operator) external view returns (uint256) {
        return operatorNodes[operator].length;
    }

    function isNodeAlive(uint256 nodeId) external view returns (bool) {
        NodeInfo memory node = nodes[nodeId];
        if (node.status != NodeStatus.ACTIVE) return false;
        return (block.timestamp - node.lastHeartbeat) <= HEARTBEAT_GRACE;
    }

    function getNodeTier(uint256 nodeId) external view returns (NodeTier) {
        return nodes[nodeId].tier;
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  INTERNAL
    // ═══════════════════════════════════════════════════════════════════════

    function _checkTierUpgrade(uint256 nodeId) internal {
        NodeInfo storage node = nodes[nodeId];
        NodeTier currentTier = node.tier;
        NodeTier newTier = currentTier;

        for (uint256 i = 4; i > uint256(currentTier); i--) {
            if (node.uptimeSeconds >= tierThresholds[i]) {
                newTier = NodeTier(i);
                break;
            }
        }

        if (newTier != currentTier) {
            node.tier = newTier;

            // Auto-upgrade multiplier with tier
            uint16 tierMultiplier = _tierMultiplier(newTier);
            if (tierMultiplier > node.multiplierBps) {
                uint16 old = node.multiplierBps;
                node.multiplierBps = tierMultiplier;
                emit MultiplierUpdated(nodeId, old, tierMultiplier, block.timestamp);
            }

            emit TierUpgraded(nodeId, currentTier, newTier, block.timestamp);
        }
    }

    function _tierMultiplier(NodeTier tier) internal pure returns (uint16) {
        if (tier == NodeTier.SPARK)  return 10000; // 1.0x
        if (tier == NodeTier.PULSE)  return 12000; // 1.2x
        if (tier == NodeTier.SIGNAL) return 15000; // 1.5x
        if (tier == NodeTier.BEACON) return 18000; // 1.8x
        if (tier == NodeTier.NEXUS)  return 25000; // 2.5x
        return 10000;
    }
}
