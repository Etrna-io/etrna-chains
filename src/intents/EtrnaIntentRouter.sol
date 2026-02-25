// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

interface IIdentityGuard {
    function check(bytes32 policyId, address account, bytes calldata proof) external view returns (bool ok);
}

interface IMeshHub {
    function createIntent(uint8 actionType, uint256 dstChainId, address asset, uint256 amount, bytes32 paramsHash) external payable returns (bytes32);
}

/// @notice INT-002: Intent Router that can be called directly OR via an ERC-4337 smart account.
/// It optionally enforces IdentityGuard policy checks before creating MeshHub intents.
/// Execution remains in your offchain modular-mesh-router.
contract EtrnaIntentRouter is Ownable, ReentrancyGuard {
    event PolicySet(bytes32 indexed policyId, bool enabled);
    event MeshHubSet(address indexed meshHub);
    event IdentityGuardSet(address indexed identityGuard);
    /// @notice emitted after we successfully forward an intent to MeshHub.
    event IntentForwarded(bytes32 indexed intentId, bytes32 indexed clientRequestId, address indexed caller, bytes32 policyId);

    /// @notice protects clients (and relayers) from accidental double-submission.
    event ClientRequestConsumed(bytes32 indexed clientRequestId, address indexed caller);

    address public meshHub;
    address public identityGuard;

    mapping(bytes32 => bool) public policyEnabled;

    /// @dev global replay protection keyed by clientRequestId.
    /// Recommended: clientRequestId = keccak256(abi.encodePacked(wallet, appDomain, nonce)).
    mapping(bytes32 => bool) public consumedClientRequest;

    constructor(address _meshHub, address _identityGuard) {
        require(_meshHub != address(0), "EtrnaIntentRouter: meshHub=0");
        meshHub = _meshHub;
        identityGuard = _identityGuard;
    }

    function setMeshHub(address _meshHub) external onlyOwner {
        require(_meshHub != address(0), "EtrnaIntentRouter: meshHub=0");
        meshHub = _meshHub;
        emit MeshHubSet(_meshHub);
    }

    function setIdentityGuard(address _identityGuard) external onlyOwner {
        identityGuard = _identityGuard;
        emit IdentityGuardSet(_identityGuard);
    }

    function setPolicy(bytes32 policyId, bool enabled) external onlyOwner {
        policyEnabled[policyId] = enabled;
        emit PolicySet(policyId, enabled);
    }

    /// @notice Creates an intent with replay protection.
    /// @param clientRequestId caller-provided idempotency key.
    function createRoutedIntent(
        bytes32 clientRequestId,
        bytes32 policyId,
        bytes calldata proof,
        uint8 actionType,
        uint256 dstChainId,
        address asset,
        uint256 amount,
        bytes32 paramsHash
    ) external payable nonReentrant returns (bytes32) {
        require(clientRequestId != bytes32(0), "EtrnaIntentRouter: requestId=0");
        require(!consumedClientRequest[clientRequestId], "EtrnaIntentRouter: replay");
        consumedClientRequest[clientRequestId] = true;
        emit ClientRequestConsumed(clientRequestId, msg.sender);

        if (policyId != bytes32(0) && policyEnabled[policyId]) {
            require(identityGuard != address(0), "EtrnaIntentRouter: guard not set");
            bool ok = IIdentityGuard(identityGuard).check(policyId, msg.sender, proof);
            require(ok, "EtrnaIntentRouter: policy failed");
        }

        bytes32 intentId = IMeshHub(meshHub).createIntent{value: msg.value}(actionType, dstChainId, asset, amount, paramsHash);
        emit IntentForwarded(intentId, clientRequestId, msg.sender, policyId);
        return intentId;
    }
}
