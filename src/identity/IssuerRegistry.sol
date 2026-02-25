// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "../interfaces/IIssuerRegistry.sol";

/**
 * @title IssuerRegistry
 * @notice Registry of approved credential/pass issuers (cities, organizations, events).
 * @dev V1 is role-gated via AccessControl. Later versions may decentralize approvals.
 */
contract IssuerRegistry is AccessControl, IIssuerRegistry {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    /// @dev issuerId => Issuer
    mapping(bytes32 => Issuer) private _issuers;

    /// @dev Track whether an issuerId has ever been registered.
    mapping(bytes32 => bool) private _registered;

    constructor(address admin) {
        require(admin != address(0), "IssuerRegistry: admin is zero");
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
    }

    // ------------ Core logic ------------

    /// @inheritdoc IIssuerRegistry
    function registerIssuer(
        bytes32 issuerId,
        IssuerType issuerType,
        address admin,
        uint256 maxSupply,
        bytes32 metadataHash
    ) external onlyRole(ADMIN_ROLE) {
        require(issuerId != bytes32(0), "IssuerRegistry: empty issuerId");
        require(admin != address(0), "IssuerRegistry: admin is zero");
        require(!_registered[issuerId], "IssuerRegistry: already registered");

        _issuers[issuerId] = Issuer({
            issuerType: issuerType,
            admin: admin,
            active: true,
            maxSupply: maxSupply,
            metadataHash: metadataHash
        });
        _registered[issuerId] = true;

        emit IssuerRegistered(issuerId, issuerType, admin, maxSupply);
    }

    /// @inheritdoc IIssuerRegistry
    function updateIssuer(
        bytes32 issuerId,
        bool active,
        uint256 maxSupply,
        bytes32 metadataHash
    ) external onlyRole(ADMIN_ROLE) {
        require(_registered[issuerId], "IssuerRegistry: not registered");

        Issuer storage issuer = _issuers[issuerId];
        issuer.active = active;
        issuer.maxSupply = maxSupply;
        issuer.metadataHash = metadataHash;

        emit IssuerUpdated(issuerId, active, maxSupply, metadataHash);
    }

    /// @inheritdoc IIssuerRegistry
    function getIssuer(bytes32 issuerId) external view returns (Issuer memory) {
        require(_registered[issuerId], "IssuerRegistry: not registered");
        return _issuers[issuerId];
    }

    /// @inheritdoc IIssuerRegistry
    function isActive(bytes32 issuerId) external view returns (bool) {
        return _registered[issuerId] && _issuers[issuerId].active;
    }
}
