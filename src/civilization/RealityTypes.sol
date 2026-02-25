// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library RealityTypes {
    enum AssertionStatus {
        Active,
        Challenged,
        ResolvedTrue,
        ResolvedFalse,
        Cancelled
    }

    struct Assertion {
        address asserter;
        uint64 assertedAt;
        bytes32 schema;
        bytes32 topic;
        bytes32 contentHash; // hash of canonicalized payload off-chain (or ABI-encoded)
        uint256 stake;       // $ETR staked to back the claim
        AssertionStatus status;
        uint256 challengeId; // optional
    }

    struct Challenge {
        address challenger;
        uint64 challengedAt;
        uint256 stake;
        bool resolved;
        bool outcomeTrue;
    }
}
