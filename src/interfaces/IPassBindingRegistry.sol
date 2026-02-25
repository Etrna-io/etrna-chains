// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IPassBindingRegistry
/// @notice Optional on-chain binding registry to link passes to an Etrnal identity.
/// @dev Binding is required to activate privileges. Transfers may be restricted while bound.
interface IPassBindingRegistry {
    enum PassType { EtrnaPass, CommunityPass }

    struct Binding {
        PassType passType;
        address passContract;
        uint256 tokenId;
        uint256 etrnalId;
        uint64 boundAt;
        bool active;
    }

    event PassBound(PassType indexed passType, address indexed passContract, uint256 indexed tokenId, uint256 etrnalId);
    event PassUnbound(PassType indexed passType, address indexed passContract, uint256 indexed tokenId, uint256 etrnalId);

    function bind(PassType passType, address passContract, uint256 tokenId, uint256 etrnalId) external;
    function unbind(PassType passType, address passContract, uint256 tokenId) external;

    function getBinding(PassType passType, address passContract, uint256 tokenId) external view returns (Binding memory);
    function isBound(PassType passType, address passContract, uint256 tokenId) external view returns (bool);
}
