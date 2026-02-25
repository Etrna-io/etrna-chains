// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

import {EtrnaErrors} from "../lib/EtrnaErrors.sol";

/**
 * @title ReceiptNFT
 * @notice Non-transferable (soulbound) ERC-721 receipt tokens for on-chain
 *         EtrnaVerse deployment events.
 *
 * When a blueprint is deployed to a target chain, the deployer mints a
 * ReceiptNFT that permanently records:
 *  - blueprintId (bytes32 hash)
 *  - targetChainId
 *  - contractAddress (deployed)
 *  - deployTxHash
 *  - timestamp
 *
 * Soulbound: transfers are blocked (except mint and burn).
 */
contract ReceiptNFT is ERC721, AccessControl {
    using Strings for uint256;

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    struct Receipt {
        bytes32 blueprintId;
        uint64 targetChainId;
        address deployedContract;
        bytes32 deployTxHash;
        uint64 timestamp;
        string label;
    }

    uint256 public nextTokenId;
    string private _baseTokenURI;

    mapping(uint256 => Receipt) public receipts;

    event ReceiptMinted(
        uint256 indexed tokenId,
        address indexed deployer,
        bytes32 indexed blueprintId,
        uint64 targetChainId,
        address deployedContract,
        bytes32 deployTxHash
    );

    event BaseURISet(string newBaseURI);

    constructor(address admin) ERC721("EtrnaVerse Deployment Receipt", "ETRNA-RECEIPT") {
        if (admin == address(0)) revert EtrnaErrors.ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE, admin);
    }

    // ─── Minting ───────────────────────────────────────────────────────

    function mintReceipt(
        address deployer,
        bytes32 blueprintId,
        uint64 targetChainId,
        address deployedContract,
        bytes32 deployTxHash,
        string calldata label
    ) external onlyRole(MINTER_ROLE) returns (uint256 tokenId) {
        if (deployer == address(0)) revert EtrnaErrors.ZeroAddress();
        if (blueprintId == bytes32(0)) revert EtrnaErrors.InvalidInput();
        if (deployedContract == address(0)) revert EtrnaErrors.ZeroAddress();

        tokenId = ++nextTokenId;
        receipts[tokenId] = Receipt({
            blueprintId: blueprintId,
            targetChainId: targetChainId,
            deployedContract: deployedContract,
            deployTxHash: deployTxHash,
            timestamp: uint64(block.timestamp),
            label: label
        });

        _safeMint(deployer, tokenId);

        emit ReceiptMinted(
            tokenId,
            deployer,
            blueprintId,
            targetChainId,
            deployedContract,
            deployTxHash
        );
    }

    // ─── Soulbound: block transfers ────────────────────────────────────

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 batchSize
    ) internal override {
        // Allow mint (from == 0) and burn (to == 0), block all transfers
        if (from != address(0) && to != address(0)) {
            revert EtrnaErrors.Unauthorized();
        }
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }

    // ─── Metadata ──────────────────────────────────────────────────────

    function setBaseURI(string calldata newBaseURI) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _baseTokenURI = newBaseURI;
        emit BaseURISet(newBaseURI);
    }

    function _baseURI() internal view override returns (string memory) {
        return _baseTokenURI;
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_exists(tokenId), "ERC721: invalid token ID");
        return string.concat(_baseURI(), tokenId.toString(), ".json");
    }

    // ─── Views ─────────────────────────────────────────────────────────

    function getReceipt(uint256 tokenId)
        external
        view
        returns (
            bytes32 blueprintId,
            uint64 targetChainId,
            address deployedContract,
            bytes32 deployTxHash,
            uint64 timestamp,
            string memory label
        )
    {
        require(_exists(tokenId), "ERC721: invalid token ID");
        Receipt storage r = receipts[tokenId];
        return (r.blueprintId, r.targetChainId, r.deployedContract, r.deployTxHash, r.timestamp, r.label);
    }

    // ─── Interface support ─────────────────────────────────────────────

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
