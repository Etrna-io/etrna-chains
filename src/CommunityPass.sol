// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Context.sol";

/**
 * @title CommunityPass
 * @notice Soulbound ERC-721 representing a resident's civic identity for a specific city.
 * @dev One pass per (cityId, wallet). Non-transferable after mint. Designed to plug into
 *      Etrna's entitlements and rewards engines for local economies.
 */
contract CommunityPass is ERC721Enumerable, AccessControl {
    bytes32 public constant CITY_ADMIN_ROLE = keccak256("CITY_ADMIN_ROLE");
    bytes32 public constant REGISTRAR_ROLE = keccak256("REGISTRAR_ROLE");

    struct PassData {
        uint32 cityId;
        uint64 issuedAt;
        bool active;
    }

    // tokenId => PassData
    mapping(uint256 => PassData) private _passData;

    // cityId => wallet => tokenId (0 = none)
    mapping(uint32 => mapping(address => uint256)) public cityPassOf;

    string private _baseTokenURI;
    uint256 private _nextId = 1;

    event PassIssued(uint256 indexed tokenId, address indexed to, uint32 indexed cityId);
    event PassRevoked(uint256 indexed tokenId, address indexed owner, uint32 indexed cityId);
    event BaseURIUpdated(string newBaseURI);

    constructor(
        string memory name_,
        string memory symbol_,
        string memory baseTokenURI_,
        address admin
    ) ERC721(name_, symbol_) {
        require(admin != address(0), "CommunityPass: admin is zero");
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(CITY_ADMIN_ROLE, admin);
        _grantRole(REGISTRAR_ROLE, admin);
        _baseTokenURI = baseTokenURI_;
    }

    // ------------ Admin configuration ------------

    function setBaseURI(string calldata newBaseURI) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _baseTokenURI = newBaseURI;
        emit BaseURIUpdated(newBaseURI);
    }

    function grantCityAdmin(address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(CITY_ADMIN_ROLE, account);
    }

    function grantRegistrar(address account) external onlyRole(CITY_ADMIN_ROLE) {
        _grantRole(REGISTRAR_ROLE, account);
    }

    // ------------ Core logic ------------

    /**
     * @notice Issue a new Community Pass to a resident for a given city.
     * @dev One pass per (cityId, wallet). Mint is non-transferable (soulbound).
     */
    function issuePass(address to, uint32 cityId)
        external
        onlyRole(REGISTRAR_ROLE)
        returns (uint256 tokenId)
    {
        require(to != address(0), "CommunityPass: to is zero");
        require(cityId != 0, "CommunityPass: invalid cityId");
        require(cityPassOf[cityId][to] == 0, "CommunityPass: pass exists");

        tokenId = _nextId++;
        _safeMint(to, tokenId);

        PassData memory data = PassData({
            cityId: cityId,
            issuedAt: uint64(block.timestamp),
            active: true
        });
        _passData[tokenId] = data;
        cityPassOf[cityId][to] = tokenId;

        emit PassIssued(tokenId, to, cityId);
    }

    /**
     * @notice Revoke a Community Pass (e.g., residency lost or fraud).
     * @dev Burns the token and clears mappings.
     */
    function revokePass(uint256 tokenId) external onlyRole(CITY_ADMIN_ROLE) {
        address owner = ownerOf(tokenId);
        PassData memory data = _passData[tokenId];
        require(data.active, "CommunityPass: already inactive");

        _passData[tokenId].active = false;
        cityPassOf[data.cityId][owner] = 0;

        _burn(tokenId);
        emit PassRevoked(tokenId, owner, data.cityId);
    }

    /**
     * @notice Returns metadata for a given pass.
     */
    function getPassData(uint256 tokenId) external view returns (PassData memory) {
        require(_exists(tokenId), "CommunityPass: nonexistent token");
        return _passData[tokenId];
    }

    function isActive(uint256 tokenId) external view returns (bool) {
        require(_exists(tokenId), "CommunityPass: nonexistent token");
        return _passData[tokenId].active;
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
            revert("CommunityPass: soulbound");
        }
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }

    // ------------ Interface support (dual inheritance fix) ------------

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721Enumerable, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    // ------------ Metadata ------------

    function _baseURI() internal view override returns (string memory) {
        return _baseTokenURI;
    }
}
