// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import {MeshTypes} from "./MeshTypes.sol";
import {IMeshAdapter} from "./IMeshAdapter.sol";

/// @title MeshHub
/// @notice On-chain anchor for Etrna Modular Mesh intents (cross-chain routing + execution tracking).
/// @dev v1: stores intents + lifecycle events. Off-chain routerBackend computes routes and triggers adapters via messaging.
///      Future: add fee accounting, per-action escrow, and on-chain adapter execution for same-chain paths.
contract MeshHub is Ownable, ReentrancyGuard {
    event IntentCreated(
        bytes32 indexed intentId,
        address indexed creator,
        MeshTypes.ActionType actionType,
        uint256 srcChainId,
        uint256 dstChainId,
        bytes32 paramsHash
    );

    event IntentRouted(
        bytes32 indexed intentId,
        address indexed executor,
        uint256 dstChainId,
        bytes routeData
    );

    event IntentCompleted(bytes32 indexed intentId, bytes32 dstTxHash);
    event IntentFailed(bytes32 indexed intentId, string reason);
    event EmergencyWithdraw(address indexed to, uint256 amount);

    mapping(bytes32 => MeshTypes.Intent) public intents;

    /// @notice chainId => actionSelector => adapter
    mapping(uint256 => mapping(bytes4 => address)) public adapters;

    /// @notice Nonce to prevent intent ID collisions.
    uint256 private _nonce;

    /// @notice Authorized off-chain router/relayer that can mark routing outcomes.
    address public routerBackend;

    modifier onlyRouter() {
        require(msg.sender == routerBackend || msg.sender == owner(), "MeshHub: not router");
        _;
    }

    constructor(address _routerBackend) Ownable() {
        routerBackend = _routerBackend;
    }

    function setRouterBackend(address _routerBackend) external onlyOwner {
        routerBackend = _routerBackend;
    }

    function setAdapter(uint256 chainId, bytes4 actionSelector, address adapter) external onlyOwner {
        adapters[chainId][actionSelector] = adapter;
    }

    /// @notice Create an intent for an action to be routed and executed.
    function createIntent(
        MeshTypes.ActionType actionType,
        uint256 dstChainId,
        address asset,
        uint256 amount,
        bytes32 paramsHash
    ) external payable nonReentrant returns (bytes32) {
        require(actionType != MeshTypes.ActionType.UNKNOWN, "MeshHub: invalid action");

        uint256 srcChainId;
        assembly {
            srcChainId := chainid()
        }

        _nonce++;
        bytes32 intentId = keccak256(
            abi.encodePacked(
                msg.sender,
                block.timestamp,
                srcChainId,
                dstChainId,
                asset,
                amount,
                paramsHash,
                _nonce
            )
        );
        require(intents[intentId].creator == address(0), "MeshHub: duplicate intent");

        intents[intentId] = MeshTypes.Intent({
            creator: msg.sender,
            actionType: actionType,
            srcChainId: srcChainId,
            dstChainId: dstChainId,
            asset: asset,
            amount: amount,
            paramsHash: paramsHash,
            status: MeshTypes.IntentStatus.PENDING,
            createdAt: block.timestamp
        });

        emit IntentCreated(intentId, msg.sender, actionType, srcChainId, dstChainId, paramsHash);
        return intentId;
    }

    function markRouted(bytes32 intentId, bytes calldata routeData) external onlyRouter {
        MeshTypes.Intent storage intent = intents[intentId];
        require(intent.creator != address(0), "MeshHub: unknown intent");
        require(intent.status == MeshTypes.IntentStatus.PENDING, "MeshHub: not pending");

        intent.status = MeshTypes.IntentStatus.ROUTED;
        emit IntentRouted(intentId, msg.sender, intent.dstChainId, routeData);
    }

    function markCompleted(bytes32 intentId, bytes32 dstTxHash) external onlyRouter {
        MeshTypes.Intent storage intent = intents[intentId];
        require(intent.creator != address(0), "MeshHub: unknown intent");
        require(intent.status == MeshTypes.IntentStatus.ROUTED, "MeshHub: not routed");

        intent.status = MeshTypes.IntentStatus.COMPLETED;
        emit IntentCompleted(intentId, dstTxHash);
    }

    function markFailed(bytes32 intentId, string calldata reason) external onlyRouter {
        MeshTypes.Intent storage intent = intents[intentId];
        require(intent.creator != address(0), "MeshHub: unknown intent");
        require(intent.status == MeshTypes.IntentStatus.ROUTED, "MeshHub: not routed");

        intent.status = MeshTypes.IntentStatus.FAILED;
        emit IntentFailed(intentId, reason);
    }

    /// @notice Allow owner to rescue ETH that would otherwise be permanently locked.
    function emergencyWithdraw(address payable to, uint256 amount) external onlyOwner nonReentrant {
        require(to != address(0), "MH: zero address");
        require(amount <= address(this).balance, "MH: insufficient");
        (bool ok,) = to.call{value: amount}("");
        require(ok, "MH: withdraw failed");
        emit EmergencyWithdraw(to, amount);
    }

    function getIntent(bytes32 intentId) external view returns (MeshTypes.Intent memory) {
        return intents[intentId];
    }
}
