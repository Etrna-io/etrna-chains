// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IIssuerRegistry} from "./IIssuerRegistry.sol";

/// @title ICommunityPass
/// @notice Contextual access NFT issued by approved issuers (cities, orgs, events).
/// @dev Canonical invariants:
/// - Unlimited global supply
/// - Hard cap enforced per issuerId via IssuerRegistry
/// - Always bound to an Etrnal to be useful (binding enforced by resolver and/or registry)
interface ICommunityPass {
    event CommunityPassMinted(bytes32 indexed issuerId, address indexed to, uint256 indexed tokenId);
    event CommunityPassRevoked(bytes32 indexed issuerId, uint256 indexed tokenId, string reason);

    function issuerIdOf(uint256 tokenId) external view returns (bytes32);
    function mint(bytes32 issuerId, address to) external returns (uint256 tokenId);
    function revoke(uint256 tokenId, string calldata reason) external;

    function tokenURI(uint256 tokenId) external view returns (string memory);
}
