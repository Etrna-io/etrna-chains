// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IDJSetRegistry
/// @notice On-chain attestations of DJ sets and tracklists (optional; v1 may be off-chain).
interface IDJSetRegistry {
    struct DJSet {
        bytes32 venueId;
        address dj;
        uint64 startTime;
        uint64 endTime;
        bytes32 tracklistHash; // hash of canonical tracklist payload
    }

    event DJSetDeclared(bytes32 indexed setId, bytes32 indexed venueId, address indexed dj, uint64 startTime, uint64 endTime);
    event TracklistSubmitted(bytes32 indexed setId, bytes32 tracklistHash);

    function declareSet(bytes32 venueId, uint64 startTime, uint64 endTime) external returns (bytes32 setId);
    function submitTracklist(bytes32 setId, bytes32 tracklistHash) external;

    function getSet(bytes32 setId) external view returns (DJSet memory);
}
