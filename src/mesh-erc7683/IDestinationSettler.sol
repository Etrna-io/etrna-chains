// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

interface IDestinationSettler {
    function fill(bytes32 orderId, bytes calldata originData, bytes calldata fillerData) external;
}
