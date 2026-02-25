// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract RandomnessRouter is Ownable {
    struct Request {
        address requester;
        uint64 createdAt;
        bool fulfilled;
        uint256 value;
        uint32 sourceMask;
    }

    event Requested(bytes32 indexed requestId, address indexed requester);
    event Fulfilled(bytes32 indexed requestId, address indexed fulfiller, uint256 value, uint32 sourceMask);

    mapping(bytes32 => Request) public requests;
    mapping(address => uint256) public nonces;
    mapping(address => bool) public fulfillers;

    function setFulfiller(address f, bool ok) external onlyOwner {
        fulfillers[f] = ok;
    }

    /// @notice create a request with explicit idempotency.
    /// @param clientRequestId caller-controlled id used for replay protection.
    function request(bytes32 clientRequestId) external returns (bytes32) {
        require(clientRequestId != bytes32(0), "RandomnessRouter: requestId=0");
        uint256 n = nonces[msg.sender]++;
        bytes32 id = keccak256(abi.encodePacked(block.chainid, msg.sender, clientRequestId, n));
        require(requests[id].requester == address(0), "RandomnessRouter: dup");
        requests[id] = Request({ requester: msg.sender, createdAt: uint64(block.timestamp), fulfilled: false, value: 0, sourceMask: 0 });
        emit Requested(id, msg.sender);
        return id;
    }

    modifier onlyFulfiller() {
        require(fulfillers[msg.sender], "RandomnessRouter: not fulfiller");
        _;
    }

    function fulfill(bytes32 requestId, uint256 value, uint32 sourceMask) external onlyFulfiller {
        Request storage r = requests[requestId];
        require(r.requester != address(0), "RandomnessRouter: unknown");
        require(!r.fulfilled, "RandomnessRouter: done");
        r.fulfilled = true;
        r.value = value;
        r.sourceMask = sourceMask;
        emit Fulfilled(requestId, msg.sender, value, sourceMask);
    }
}
