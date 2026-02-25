// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "../interfaces/IEtrnal.sol";

/**
 * @title Etrnal
 * @notice Soulbound ERC-721 representing the root identity anchor in the ETRNA ecosystem.
 * @dev Non-transferable. One Etrnal per wallet enforced on-chain.
 */
contract Etrnal is ERC721, AccessControl, IEtrnal {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    uint256 private _nextId = 1;

    /// @dev etrnalId => metadataHash
    mapping(uint256 => bytes32) private _metadataHash;

    /// @dev address => etrnalId (0 = none)
    mapping(address => uint256) public etrnalOf;

    /// @dev etrnalId => suspended flag
    mapping(uint256 => bool) private _suspended;

    string private _baseTokenURI;

    constructor(
        string memory name_,
        string memory symbol_,
        string memory baseTokenURI_,
        address admin
    ) ERC721(name_, symbol_) {
        require(admin != address(0), "Etrnal: admin is zero");
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE, admin);
        _baseTokenURI = baseTokenURI_;
    }

    // ------------ Core logic ------------

    /// @inheritdoc IEtrnal
    function mint(address to, bytes32 metadataHash) external onlyRole(MINTER_ROLE) returns (uint256 etrnalId) {
        require(to != address(0), "Etrnal: to is zero");
        require(etrnalOf[to] == 0, "Etrnal: already has etrnal");

        etrnalId = _nextId++;
        _safeMint(to, etrnalId);
        _metadataHash[etrnalId] = metadataHash;
        etrnalOf[to] = etrnalId;

        emit EtrnalMinted(to, etrnalId);
    }

    /// @inheritdoc IEtrnal
    function isSuspended(uint256 etrnalId) external view returns (bool) {
        require(_exists(etrnalId), "Etrnal: nonexistent token");
        return _suspended[etrnalId];
    }

    /// @inheritdoc IEtrnal
    function setSuspended(uint256 etrnalId, bool suspended, string calldata reason) external onlyRole(ADMIN_ROLE) {
        require(_exists(etrnalId), "Etrnal: nonexistent token");
        _suspended[etrnalId] = suspended;
        emit EtrnalSuspended(etrnalId, suspended, reason);
    }

    /// @notice Update the metadata hash for an Etrnal token.
    function updateMetadata(uint256 etrnalId, bytes32 metadataHash) external onlyRole(ADMIN_ROLE) {
        require(_exists(etrnalId), "Etrnal: nonexistent token");
        _metadataHash[etrnalId] = metadataHash;
        emit EtrnalMetadataUpdated(etrnalId, metadataHash);
    }

    /// @notice Returns the metadata hash for a given Etrnal.
    function getMetadataHash(uint256 etrnalId) external view returns (bytes32) {
        require(_exists(etrnalId), "Etrnal: nonexistent token");
        return _metadataHash[etrnalId];
    }

    // ------------ Soulbound enforcement ------------

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 batchSize
    ) internal override {
        // Allow minting (from == 0) and burning (to == 0) only.
        if (from != address(0) && to != address(0)) {
            revert("Etrnal: soulbound");
        }
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }

    // ------------ Metadata ------------

    function tokenURI(uint256 etrnalId) public view override(ERC721, IEtrnal) returns (string memory) {
        require(_exists(etrnalId), "Etrnal: nonexistent token");
        string memory base = _baseURI();
        return bytes(base).length > 0
            ? string.concat(base, Strings.toString(etrnalId))
            : "";
    }

    function _baseURI() internal view override returns (string memory) {
        return _baseTokenURI;
    }

    function setBaseURI(string calldata newBaseURI) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _baseTokenURI = newBaseURI;
    }

    // ------------ Interface support (dual inheritance fix) ------------

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    // ------------ View helpers ------------

    /// @notice Explicit ownerOf override satisfying both ERC721 and IEtrnal.
    function ownerOf(uint256 tokenId) public view override(ERC721, IEtrnal) returns (address) {
        return super.ownerOf(tokenId);
    }

    function nextTokenId() external view returns (uint256) {
        return _nextId;
    }
}
