// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";

interface IERC721Like {
    function ownerOf(uint256 tokenId) external view returns (address);
    function getApproved(uint256 tokenId) external view returns (address);
    function isApprovedForAll(address owner, address operator) external view returns (bool);
}

interface INftBridgeAdapter {
    function bridgeERC721(address nft, uint256 tokenId, uint256 dstChainId, address to, bytes calldata data) external returns (bytes32 bridgeTxId);
}

/// @notice NFT-XRPC: protocol-agnostic NFT cross-chain movement router with metadata anchor.
/// Adapters are expected to implement the actual bridging.
contract NftBridgeRouter is Ownable, ReentrancyGuard, Pausable {
    event AdapterSet(uint256 indexed dstChainId, address indexed adapter);
    event NftAllowlistSet(address indexed nft, bool allowed);
    event Bridged(
        bytes32 indexed clientRequestId,
        address indexed caller,
        address indexed nft,
        uint256 tokenId,
        uint256 dstChainId,
        address to,
        bytes32 bridgeTxId,
        bytes32 uefMetadataHash
    );

    mapping(uint256 => address) public adapterForChain;

    mapping(address => bool) public nftAllowed;
    mapping(bytes32 => bool) public consumedClientRequest;

    /// @notice if enabled, only NFTs explicitly allowlisted can be bridged through this router.
    bool public allowlistMode;

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function setAdapter(uint256 dstChainId, address adapter) external onlyOwner {
        adapterForChain[dstChainId] = adapter;
        emit AdapterSet(dstChainId, adapter);
    }

    function setNftAllowed(address nft, bool allowed) external onlyOwner {
        nftAllowed[nft] = allowed;
        emit NftAllowlistSet(nft, allowed);
    }

    function setAllowlistMode(bool on) external onlyOwner {
        allowlistMode = on;
    }

    function bridgeERC721(
        bytes32 clientRequestId,
        address nft,
        uint256 tokenId,
        uint256 dstChainId,
        address to,
        bytes32 uefMetadataHash,
        bytes calldata data
    ) external nonReentrant whenNotPaused returns (bytes32) {
        require(clientRequestId != bytes32(0), "NftBridgeRouter: requestId=0");
        require(!consumedClientRequest[clientRequestId], "NftBridgeRouter: replay");
        consumedClientRequest[clientRequestId] = true;

        if (allowlistMode) {
            require(nftAllowed[nft], "NftBridgeRouter: nft not allowlisted");
        }

        address owner = IERC721Like(nft).ownerOf(tokenId);
        require(owner == msg.sender, "NftBridgeRouter: not owner");
        require(
            IERC721Like(nft).isApprovedForAll(msg.sender, address(this)) ||
                IERC721Like(nft).getApproved(tokenId) == address(this),
            "NftBridgeRouter: not approved"
        );

        address adapter = adapterForChain[dstChainId];
        require(adapter != address(0), "NftBridgeRouter: no adapter");
        bytes32 bridgeTxId = INftBridgeAdapter(adapter).bridgeERC721(nft, tokenId, dstChainId, to, data);
        emit Bridged(clientRequestId, msg.sender, nft, tokenId, dstChainId, to, bridgeTxId, uefMetadataHash);
        return bridgeTxId;
    }
}
