// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IEtrnaToken
/// @notice Governance and alignment token for Etrna.
/// @dev Canonical invariants:
/// - Max supply: 1,000,000,000 (fixed; no post-deploy mint)
/// - ERC20Votes + Permit semantics in implementation
interface IEtrnaToken {
    event GenesisMint(address indexed to, uint256 amount);

    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);

    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);

    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);

    // Permit (EIP-2612)
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    // Votes (ERC20Votes)
    function getVotes(address account) external view returns (uint256);
    function delegate(address delegatee) external;
}
