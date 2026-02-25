// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library TokenErrors {
    error ZeroAddress();
    error ZeroAmount();
    error LengthMismatch();
    error ExceedsMaxSupply();
    error TransfersPaused();
}
