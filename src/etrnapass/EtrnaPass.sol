// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title EtrnaPass
 * @notice ERC-721 EtrnaPass with Tier + Edition enums and ERC-2981 royalties.
 *
 * Design notes (canonical):
 * - Four tiers: CORE, PRIME, ASCENDANT, ORIGIN.
 * - Three editions: STANDARD, FOIL, LE01 (LE • 01).
 * - Dynamic supply, no serial-number traits in metadata.
 * - tokenURI resolves to tier+edition template JSON (12 variants total).
 *
 * See: EtrnaPass Unified Product + Metadata Specification.
 */
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";

contract EtrnaPass is ERC721, ERC721Enumerable, AccessControl, ERC2981 {
    using Strings for uint256;

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant METADATA_ADMIN_ROLE = keccak256("METADATA_ADMIN_ROLE");

    /// @dev Tier enum ordering is canonical; keep stable for indexers.
    enum Tier {
        CORE,
        PRIME,
        ASCENDANT,
        ORIGIN
    }

    /// @dev Edition enum ordering is canonical; keep stable for indexers.
    enum Edition {
        STANDARD,
        FOIL,
        LE01
    }

    struct PassInfo {
        Tier tier;
        Edition edition;
    }

    uint256 private _nextId = 1;
    mapping(uint256 => PassInfo) private _passInfo;

    // Recommended base URI pattern:
    // https://assets.etrna.com/ipfs/<METADATA_CID>/
    string private _baseTokenURI;

    event BaseURISet(string newBaseURI);
    event PassMinted(address indexed to, uint256 indexed tokenId, Tier tier, Edition edition);

    constructor(
        address admin,
        string memory name_,
        string memory symbol_,
        string memory baseURI_,
        address royaltyReceiver,
        uint96 royaltyBps
    ) ERC721(name_, symbol_) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE, admin);
        _grantRole(METADATA_ADMIN_ROLE, admin);

        _baseTokenURI = baseURI_;
        if (royaltyReceiver != address(0) && royaltyBps > 0) {
            _setDefaultRoyalty(royaltyReceiver, royaltyBps);
        }
    }

    // ---------------------------
    // Minting
    // ---------------------------

    function mint(address to, Tier tier, Edition edition) external onlyRole(MINTER_ROLE) returns (uint256 tokenId) {
        tokenId = _nextId++;
        _passInfo[tokenId] = PassInfo({tier: tier, edition: edition});
        _safeMint(to, tokenId);
        emit PassMinted(to, tokenId, tier, edition);
    }

    function batchMint(address to, Tier tier, Edition edition, uint256 quantity)
        external
        onlyRole(MINTER_ROLE)
        returns (uint256 firstTokenId, uint256 lastTokenId)
    {
        require(quantity > 0, "quantity=0");
        firstTokenId = _nextId;
        for (uint256 i = 0; i < quantity; i++) {
            uint256 tokenId = _nextId++;
            _passInfo[tokenId] = PassInfo({tier: tier, edition: edition});
            _safeMint(to, tokenId);
            lastTokenId = tokenId;
            emit PassMinted(to, tokenId, tier, edition);
        }
    }

    // ---------------------------
    // Tier / Edition getters
    // ---------------------------

    function tokenTier(uint256 tokenId) external view returns (Tier) {
        require(_exists(tokenId), "ERC721: invalid token ID");
        return _passInfo[tokenId].tier;
    }

    function tokenEdition(uint256 tokenId) external view returns (Edition) {
        require(_exists(tokenId), "ERC721: invalid token ID");
        return _passInfo[tokenId].edition;
    }

    function tokenPassInfo(uint256 tokenId) external view returns (Tier, Edition) {
        require(_exists(tokenId), "ERC721: invalid token ID");
        PassInfo memory info = _passInfo[tokenId];
        return (info.tier, info.edition);
    }

    // ---------------------------
    // Metadata
    // ---------------------------

    function setBaseURI(string calldata newBaseURI) external onlyRole(METADATA_ADMIN_ROLE) {
        _baseTokenURI = newBaseURI;
        emit BaseURISet(newBaseURI);
    }

    function _baseURI() internal view override returns (string memory) {
        return _baseTokenURI;
    }

    /// @notice Returns the canonical template filename for this token (12-variant model).
    function tokenURITemplate(uint256 tokenId) public view returns (string memory) {
        require(_exists(tokenId), "ERC721: invalid token ID");
        PassInfo memory info = _passInfo[tokenId];
        return _templateFilename(info.tier, info.edition);
    }

    function tokenURI(uint256 tokenId) public view override(ERC721) returns (string memory) {
        require(_exists(tokenId), "ERC721: invalid token ID");
        string memory b = _baseURI();
        return string.concat(b, _templateFilename(_passInfo[tokenId].tier, _passInfo[tokenId].edition));
    }

    function _templateFilename(Tier tier, Edition edition) internal pure returns (string memory) {
        string memory tierStr =
            tier == Tier.CORE ? "core" : tier == Tier.PRIME ? "prime" : tier == Tier.ASCENDANT ? "ascendant" : "origin";
        string memory edStr = edition == Edition.STANDARD ? "standard" : edition == Edition.FOIL ? "foil" : "le01";
        return string.concat("etrnapass_", tierStr, "_", edStr, ".json");
    }

    // ---------------------------
    // Royalties
    // ---------------------------

    function setDefaultRoyalty(address receiver, uint96 feeNumerator) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setDefaultRoyalty(receiver, feeNumerator);
    }

    function deleteDefaultRoyalty() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _deleteDefaultRoyalty();
    }

    // ---------------------------
    // Overrides
    // ---------------------------

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable, AccessControl, ERC2981)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function _beforeTokenTransfer(address from, address to, uint256 tokenId, uint256 batchSize)
        internal
        override(ERC721, ERC721Enumerable)
    {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }

    // ---------------------------
    // Admin utilities
    // ---------------------------

    function nextTokenId() external view returns (uint256) {
        return _nextId;
    }
}
