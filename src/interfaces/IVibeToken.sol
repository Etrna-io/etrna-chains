// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IVibeToken
/// @notice Rewards and cultural token for Etrna.
/// @dev Canonical invariants:
/// - Max supply: 100,000,000,000 (hard cap)
/// - Minting is MINTER_ROLE gated and MUST enforce max supply
interface IVibeToken {
    event MinterUpdated(address indexed minter, bool enabled);
    event Paused(address indexed account);
    event Unpaused(address indexed account);

    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);

    function totalSupply() external view returns (uint256);
    function maxSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);

    function mint(address to, uint256 amount) external;
    function pause() external;
    function unpause() external;
}
