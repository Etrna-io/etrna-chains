// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Shared, gas-efficient custom errors for Etrna protocol contracts.
library EtrnaErrors {
    error ZeroAddress();
    error Unauthorized();
    error InvalidInput();
    error InvalidState();
    error NotFound();
    error AlreadyExists();
    error Expired();
    error InsufficientStake();
    error NotActive();
    error NotEnabled();
}
