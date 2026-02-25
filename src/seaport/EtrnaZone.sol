// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IIdentityGuard {
    function requireProof(bytes32 proofType, bytes calldata proof, bytes32 nullifier) external view returns (bool);
}

contract EtrnaZone {
    event ZoneValidated(address indexed fulfiller, address indexed offerer, bytes32 proofType);

    address public immutable identityGuard;
    bytes32 public immutable proofType;

    constructor(address _identityGuard, bytes32 _proofType) {
        require(_identityGuard != address(0), "EtrnaZone: guard=0");
        identityGuard = _identityGuard;
        proofType = _proofType;
    }

    /**
     * Seaport Zone interface varies by version.
     * This is a minimal "zone-like" contract: your Seaport integration layer should call validate()
     * before fulfilling order when zone is specified.
     */
    function validate(address fulfiller, address offerer, bytes calldata proof, bytes32 nullifier) external view returns (bool) {
        bool ok = IIdentityGuard(identityGuard).requireProof(proofType, proof, nullifier);
        // event not emitted in view; emit from router if needed
        fulfiller; offerer;
        return ok;
    }
}
