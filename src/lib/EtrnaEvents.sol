// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Shared events for cross-contract observability.
library EtrnaEvents {
    event ProtocolConfigUpdated(bytes32 indexed key, bytes value);
}
