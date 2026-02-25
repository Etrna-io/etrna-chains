// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IVenueRegistry
/// @notice Registry of venues for CityOS / VibeCheck / EtrnaMusic pilots.
interface IVenueRegistry {
    event VenueRegistered(bytes32 indexed venueId, address indexed admin, bytes32 metadataHash);
    event VenueUpdated(bytes32 indexed venueId, bytes32 metadataHash, bool active);

    function registerVenue(bytes32 venueId, address admin, bytes32 metadataHash) external;
    function updateVenue(bytes32 venueId, bytes32 metadataHash, bool active) external;

    function isActive(bytes32 venueId) external view returns (bool);
}
