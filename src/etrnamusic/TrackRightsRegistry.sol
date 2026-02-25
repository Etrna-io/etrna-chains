// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "openzeppelin-contracts/access/AccessControl.sol";

import {EtrnaErrors} from "../lib/EtrnaErrors.sol";
import {EtrnaMusicTypes} from "./EtrnaMusicTypes.sol";

/**
 * @title TrackRightsRegistry
 * @notice Minimal on-chain registry for track rights holders and payout splits.
 *
 * v1 posture:
 * - Role-gated registration/update (TRACK_REGISTRAR_ROLE)
 * - Fixed max payees per track to cap gas and avoid griefing
 *
 * Future posture:
 * - Signature-based self-registration (EIP-712)
 * - Dispute workflows anchored to Reality Ledger
 */
contract TrackRightsRegistry is AccessControl {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant TRACK_REGISTRAR_ROLE = keccak256("TRACK_REGISTRAR_ROLE");

    uint8 public constant MAX_PAYEES = 8;

    struct TrackRights {
        bool exists;
        bytes32 metadataHash;
        uint8 payeeCount;
        address[MAX_PAYEES] payees;
        uint16[MAX_PAYEES] bps;
    }

    mapping(bytes32 => TrackRights) private _tracks;

    event TrackRegistered(bytes32 indexed trackId, bytes32 indexed metadataHash);
    event TrackUpdated(bytes32 indexed trackId, bytes32 indexed metadataHash);

    constructor(address admin) {
        if (admin == address(0)) revert EtrnaErrors.ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
        _grantRole(TRACK_REGISTRAR_ROLE, admin);
    }

    function registerTrack(bytes32 trackId, address[] calldata payees, uint16[] calldata bps, bytes32 metadataHash)
        external
        onlyRole(TRACK_REGISTRAR_ROLE)
    {
        if (trackId == bytes32(0) || metadataHash == bytes32(0)) revert EtrnaErrors.InvalidInput();
        if (_tracks[trackId].exists) revert EtrnaErrors.AlreadyExists();
        _set(trackId, payees, bps, metadataHash, false);
        emit TrackRegistered(trackId, metadataHash);
    }

    function updateTrack(bytes32 trackId, address[] calldata payees, uint16[] calldata bps, bytes32 metadataHash)
        external
        onlyRole(TRACK_REGISTRAR_ROLE)
    {
        if (trackId == bytes32(0) || metadataHash == bytes32(0)) revert EtrnaErrors.InvalidInput();
        if (!_tracks[trackId].exists) revert EtrnaErrors.NotFound();
        _set(trackId, payees, bps, metadataHash, true);
        emit TrackUpdated(trackId, metadataHash);
    }

    function exists(bytes32 trackId) external view returns (bool) {
        return _tracks[trackId].exists;
    }

    function getTrack(bytes32 trackId)
        external
        view
        returns (bytes32 metadataHash, address[] memory payees, uint16[] memory bps)
    {
        TrackRights storage t = _tracks[trackId];
        if (!t.exists) revert EtrnaErrors.NotFound();

        metadataHash = t.metadataHash;
        payees = new address[](t.payeeCount);
        bps = new uint16[](t.payeeCount);
        for (uint256 i = 0; i < t.payeeCount; i++) {
            payees[i] = t.payees[i];
            bps[i] = t.bps[i];
        }
    }

    function getPayeesAndBps(bytes32 trackId) external view returns (address[] memory payees, uint16[] memory bps) {
        TrackRights storage t = _tracks[trackId];
        if (!t.exists) revert EtrnaErrors.NotFound();
        payees = new address[](t.payeeCount);
        bps = new uint16[](t.payeeCount);
        for (uint256 i = 0; i < t.payeeCount; i++) {
            payees[i] = t.payees[i];
            bps[i] = t.bps[i];
        }
    }

    function _set(bytes32 trackId, address[] calldata payees, uint16[] calldata bps, bytes32 metadataHash, bool overwrite)
        internal
    {
        uint256 n = payees.length;
        if (n == 0 || n != bps.length || n > MAX_PAYEES) revert EtrnaErrors.InvalidInput();

        uint256 sum;
        for (uint256 i = 0; i < n; i++) {
            address p = payees[i];
            if (p == address(0)) revert EtrnaErrors.ZeroAddress();
            sum += bps[i];
        }
        if (sum != EtrnaMusicTypes.MAX_BPS) revert EtrnaErrors.InvalidInput();

        TrackRights storage t = _tracks[trackId];
        if (!overwrite) {
            t.exists = true;
        }
        t.metadataHash = metadataHash;
        t.payeeCount = uint8(n);

        // Clear previous fixed slots (overwrite-safe)
        for (uint256 i = 0; i < MAX_PAYEES; i++) {
            t.payees[i] = address(0);
            t.bps[i] = 0;
        }

        for (uint256 i = 0; i < n; i++) {
            t.payees[i] = payees[i];
            t.bps[i] = bps[i];
        }
    }
}
