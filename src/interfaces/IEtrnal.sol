// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IEtrnal
/// @notice Soulbound identity root for Etrna.
/// @dev Canonical invariants:
/// - Unlimited supply
/// - Non-transferable (all transfer functions MUST revert in implementation)
/// - One Etrnal per wallet is enforced at policy/resolver layer (and MAY be enforced on-chain)
interface IEtrnal {
    event EtrnalMinted(address indexed to, uint256 indexed etrnalId);
    event EtrnalSuspended(uint256 indexed etrnalId, bool suspended, string reason);
    event EtrnalMetadataUpdated(uint256 indexed etrnalId, bytes32 metadataHash);

    function mint(address to, bytes32 metadataHash) external returns (uint256 etrnalId);
    function ownerOf(uint256 etrnalId) external view returns (address);
    function tokenURI(uint256 etrnalId) external view returns (string memory);

    function isSuspended(uint256 etrnalId) external view returns (bool);
    function setSuspended(uint256 etrnalId, bool suspended, string calldata reason) external;
}
