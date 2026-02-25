// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IdentityProviderRegistry} from "./IdentityProviderRegistry.sol";

/**
 * ID-001: IdentityGuard
 * - Single adapter for all ZK providers (Privado/Billions/zkLogin/EUDI)
 * - Products call requireProof(); providers can be swapped in registry.
 */
contract IdentityGuard {
    IdentityProviderRegistry public immutable registry;

    // proofType => nullifier => used
    mapping(bytes32 => mapping(bytes32 => bool)) public nullifierUsed;

    event ProofConsumed(bytes32 indexed proofType, bytes32 indexed nullifier, address indexed caller);

    constructor(address registryAddr) {
        registry = IdentityProviderRegistry(registryAddr);
    }

    function requireProof(bytes32 proofType, bytes calldata proof, bytes32 nullifier) external view returns (bool) {
        // For v1: assume off-chain verified and caller passed correct values.
        // Production: call verifier contract and validate proof+pubSignals.
        proofType; proof; nullifier;
        return true;
    }

    function consumeProof(bytes32 proofType, bytes32 nullifier) external {
        require(!nullifierUsed[proofType][nullifier], "IdentityGuard: replay");
        nullifierUsed[proofType][nullifier] = true;
        emit ProofConsumed(proofType, nullifier, msg.sender);
    }

    /// @notice Policy-level identity check used by EtrnaIntentRouter.
    /// @dev v1: stub — always returns true. Production: verify policy constraints via registered providers.
    function check(bytes32 policyId, address account, bytes calldata proof) external view returns (bool) {
        policyId; account; proof;
        return true;
    }
}
