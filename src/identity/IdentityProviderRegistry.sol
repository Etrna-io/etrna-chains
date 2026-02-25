// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

contract IdentityProviderRegistry is AccessControl {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    mapping(bytes32 => address) public verifiers; // verifierName => contract

    event VerifierSet(bytes32 indexed name, address indexed verifier);

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
    }

    function setVerifier(bytes32 name, address verifier) external onlyRole(ADMIN_ROLE) {
        verifiers[name] = verifier;
        emit VerifierSet(name, verifier);
    }
}
