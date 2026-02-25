// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title QuantumKeyPolicyRegistry
/// @notice Registry for PQC key policies and key-rotation requirements.
/// @dev v1 is a lightweight placeholder to canonize the interface; extend for OQS / HSM integrations.
contract QuantumKeyPolicyRegistry is Ownable {
    event PolicySet(bytes32 indexed policyId, string name, string uri);

    struct Policy {
        string name;
        string uri; // off-chain policy document (e.g., IPFS)
        bool exists;
    }

    mapping(bytes32 => Policy) public policies;

    constructor() Ownable() {}

    function setPolicy(bytes32 policyId, string calldata name, string calldata uri) external onlyOwner {
        policies[policyId] = Policy({name: name, uri: uri, exists: true});
        emit PolicySet(policyId, name, uri);
    }

    function getPolicy(bytes32 policyId) external view returns (Policy memory) {
        return policies[policyId];
    }
}
