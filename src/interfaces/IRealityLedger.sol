// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IRealityLedger {
    enum AssertionStatus {
        Pending,
        Accepted,
        Rejected
    }

    struct Assertion {
        bytes32 id;
        address asserter;
        uint64 createdAt;
        bytes32 topic;
        bytes32 schema;
        bytes32 dataHash;
        uint256 stake;
        AssertionStatus status;
    }

    event AssertionSubmitted(bytes32 indexed id, bytes32 indexed topic, address indexed asserter, uint256 stake);
    event AssertionChallenged(bytes32 indexed id, address indexed challenger, uint256 stake);
    event AssertionResolved(bytes32 indexed id, AssertionStatus status, address indexed resolver);

    function getAssertion(bytes32 id) external view returns (Assertion memory);
}
