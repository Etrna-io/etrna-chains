// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @notice PQ-ID: Post-quantum public key registry.
/// Use as a forward-compatibility anchor; verification can be offchain initially.
contract PQKeyRegistry is Ownable {
    event PQKeyRegistered(address indexed account, bytes32 indexed scheme, bytes key);
    event PQKeyRevoked(address indexed account, bytes32 indexed scheme);

    mapping(address => mapping(bytes32 => bytes)) private _keys;

    function register(bytes32 scheme, bytes calldata key) external {
        require(key.length > 0, "PQKeyRegistry: empty");
        _keys[msg.sender][scheme] = key;
        emit PQKeyRegistered(msg.sender, scheme, key);
    }

    function revoke(bytes32 scheme) external {
        delete _keys[msg.sender][scheme];
        emit PQKeyRevoked(msg.sender, scheme);
    }

    function keyOf(address account, bytes32 scheme) external view returns (bytes memory) {
        return _keys[account][scheme];
    }
}
