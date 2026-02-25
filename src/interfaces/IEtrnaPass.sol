// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IEtrnaPass
/// @notice Global access passport NFT for Etrna.
/// @dev Canonical policy (v1):
/// - Genesis series hard cap: 10,000
/// - Transferable ONLY when unbound (binding enforced by PassBindingRegistry and resolver)
interface IEtrnaPass {
    event PassMinted(address indexed to, uint256 indexed tokenId, uint256 seriesId);
    event SeriesConfigured(uint256 indexed seriesId, uint256 maxSupply, bool mintingOpen);

    function balanceOf(address owner) external view returns (uint256);
    function seriesIdOf(uint256 tokenId) external view returns (uint256);
    function maxSupplyOfSeries(uint256 seriesId) external view returns (uint256);
    function totalMintedOfSeries(uint256 seriesId) external view returns (uint256);

    function configureSeries(uint256 seriesId, uint256 maxSupply, bool mintingOpen) external;
    function mintTo(address to, uint256 seriesId) external returns (uint256 tokenId);
    function tokenURI(uint256 tokenId) external view returns (string memory);
}
