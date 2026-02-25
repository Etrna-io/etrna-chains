// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library TokenEvents {
    event MinterSet(address indexed account, bool enabled);
    event TreasuryMint(address indexed to, uint256 amount);
}
