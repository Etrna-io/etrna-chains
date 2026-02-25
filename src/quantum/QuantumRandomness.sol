// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title QuantumRandomness
/// @notice Multi-entropy randomness request/fulfillment registry.
/// @dev v1 supports authorized fulfillers (off-chain relay). entropySourceMask documents which entropy sources contributed.
contract QuantumRandomness is Ownable {
    struct Request {
        address consumer;
        uint256 chainId;
        uint64 createdAt;
        bool fulfilled;
        uint256 randomValue;
        uint32 entropySourceMask;
    }

    event RandomnessRequested(bytes32 indexed requestId, address indexed consumer, uint256 chainId);
    event RandomnessFulfilled(bytes32 indexed requestId, address indexed fulfiller, uint256 randomValue, uint32 entropySourceMask);

    mapping(bytes32 => Request) public requests;
    mapping(address => bool) public authorizedFulfillers;

    constructor(address initialFulfiller) Ownable() {
        if (initialFulfiller != address(0)) {
            authorizedFulfillers[initialFulfiller] = true;
        }
    }

    modifier onlyFulfiller() {
        require(authorizedFulfillers[msg.sender], "QuantumRandomness: not fulfiller");
        _;
    }

    function setFulfiller(address fulfiller, bool allowed) external onlyOwner {
        authorizedFulfillers[fulfiller] = allowed;
    }

    function requestRandomness() external returns (bytes32) {
        uint256 chainId;
        assembly {
            chainId := chainid()
        }

        bytes32 requestId = keccak256(abi.encodePacked(msg.sender, block.timestamp, chainId));
        require(requests[requestId].consumer == address(0), "QuantumRandomness: duplicate");

        requests[requestId] = Request({
            consumer: msg.sender,
            chainId: chainId,
            createdAt: uint64(block.timestamp),
            fulfilled: false,
            randomValue: 0,
            entropySourceMask: 0
        });

        emit RandomnessRequested(requestId, msg.sender, chainId);
        return requestId;
    }

    function fulfillRandomness(bytes32 requestId, uint256 randomValue, uint32 entropySourceMask) external onlyFulfiller {
        Request storage req = requests[requestId];
        require(req.consumer != address(0), "QuantumRandomness: unknown request");
        require(!req.fulfilled, "QuantumRandomness: already fulfilled");

        req.fulfilled = true;
        req.randomValue = randomValue;
        req.entropySourceMask = entropySourceMask;

        emit RandomnessFulfilled(requestId, msg.sender, randomValue, entropySourceMask);
    }

    function readRandomness(bytes32 requestId) external view returns (Request memory) {
        return requests[requestId];
    }
}
