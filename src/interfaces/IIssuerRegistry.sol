// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IIssuerRegistry
/// @notice Registry of approved CommunityPass issuers (cities, orgs, events).
/// @dev V1 is role-gated (multisig/timelock). Later versions may decentralize approvals.
interface IIssuerRegistry {
    enum IssuerType { City, Organization, NetworkEvent }

    struct Issuer {
        IssuerType issuerType;
        address admin;
        bool active;
        uint256 maxSupply; // hard cap per issuer for CommunityPass
        bytes32 metadataHash;
    }

    event IssuerRegistered(bytes32 indexed issuerId, IssuerType issuerType, address admin, uint256 maxSupply);
    event IssuerUpdated(bytes32 indexed issuerId, bool active, uint256 maxSupply, bytes32 metadataHash);

    function registerIssuer(bytes32 issuerId, IssuerType issuerType, address admin, uint256 maxSupply, bytes32 metadataHash) external;
    function updateIssuer(bytes32 issuerId, bool active, uint256 maxSupply, bytes32 metadataHash) external;

    function getIssuer(bytes32 issuerId) external view returns (Issuer memory);
    function isActive(bytes32 issuerId) external view returns (bool);
}
