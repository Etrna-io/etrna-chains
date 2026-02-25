// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Minimal EtrnaPass-like contract for unit testing.
contract MockPass {
    mapping(address => uint256) public balanceOf;

    function mint(address to) external {
        balanceOf[to] += 1;
    }
}
