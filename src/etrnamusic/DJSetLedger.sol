// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "openzeppelin-contracts/access/AccessControl.sol";

import {IEtrnaPass} from "../interfaces/IEtrnaPass.sol";
import {EtrnaErrors} from "../lib/EtrnaErrors.sol";
import {VenueProgramRegistry} from "./VenueProgramRegistry.sol";

/**
 * @title DJSetLedger
 * @notice On-chain anchor for DJ set lifecycles in EtrnaMusic.
 *
 * v1 posture:
 * - DJs can create/end their sets if they hold EtrnaPass
 * - Venue must exist and be active to create a set
 * - Settlement contracts (SETTLEMENT_ROLE) can mark sets as settled
 */
contract DJSetLedger is AccessControl {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant SET_MANAGER_ROLE = keccak256("SET_MANAGER_ROLE");
    bytes32 public constant SETTLEMENT_ROLE = keccak256("SETTLEMENT_ROLE");

    enum SetStatus {
        Created,
        Active,
        Ended,
        Settled,
        Cancelled
    }

    struct Set {
        address dj;
        bytes32 venueId;
        uint64 startTime;
        uint64 expectedEndTime;
        uint64 endTime;
        bytes32 setHash;
        bytes32 finalSetHash;
        SetStatus status;
    }

    IEtrnaPass public immutable etrnaPass;
    VenueProgramRegistry public immutable venues;

    uint256 public nextSetId;
    mapping(uint256 => Set) public sets;

    event SetCreated(
        uint256 indexed setId,
        address indexed dj,
        bytes32 indexed venueId,
        uint64 startTime,
        uint64 expectedEndTime,
        bytes32 setHash
    );

    event SetEnded(uint256 indexed setId, uint64 endTime, bytes32 finalSetHash);
    event SetCancelled(uint256 indexed setId, bytes32 reason);
    event SetStatusChanged(uint256 indexed setId, SetStatus status);

    constructor(address admin, address etrnaPass_, address venueRegistry) {
        if (admin == address(0) || etrnaPass_ == address(0) || venueRegistry == address(0)) revert EtrnaErrors.ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
        _grantRole(SET_MANAGER_ROLE, admin);
        _grantRole(SETTLEMENT_ROLE, admin);

        etrnaPass = IEtrnaPass(etrnaPass_);
        venues = VenueProgramRegistry(venueRegistry);
    }

    function createSet(bytes32 venueId, uint64 startTime, uint64 expectedEndTime, bytes32 setHash)
        external
        returns (uint256 setId)
    {
        if (venueId == bytes32(0) || setHash == bytes32(0)) revert EtrnaErrors.InvalidInput();
        if (etrnaPass.balanceOf(msg.sender) == 0) revert EtrnaErrors.Unauthorized();

        // venue must exist and be active
        if (!venues.isActive(venueId)) revert EtrnaErrors.NotEnabled();

        if (startTime == 0) startTime = uint64(block.timestamp);
        if (expectedEndTime != 0 && expectedEndTime <= startTime) revert EtrnaErrors.InvalidInput();

        setId = ++nextSetId;
        sets[setId] = Set({
            dj: msg.sender,
            venueId: venueId,
            startTime: startTime,
            expectedEndTime: expectedEndTime,
            endTime: 0,
            setHash: setHash,
            finalSetHash: bytes32(0),
            status: SetStatus.Active
        });

        emit SetCreated(setId, msg.sender, venueId, startTime, expectedEndTime, setHash);
        emit SetStatusChanged(setId, SetStatus.Active);
    }

    function endSet(uint256 setId, uint64 endTime, bytes32 finalSetHash) external {
        Set storage s = sets[setId];
        if (s.dj == address(0)) revert EtrnaErrors.NotFound();
        if (msg.sender != s.dj) revert EtrnaErrors.Unauthorized();
        if (s.status != SetStatus.Active) revert EtrnaErrors.InvalidState();
        if (finalSetHash == bytes32(0)) revert EtrnaErrors.InvalidInput();

        if (endTime == 0) endTime = uint64(block.timestamp);
        if (endTime <= s.startTime) revert EtrnaErrors.InvalidInput();

        s.endTime = endTime;
        s.finalSetHash = finalSetHash;
        s.status = SetStatus.Ended;

        emit SetEnded(setId, endTime, finalSetHash);
        emit SetStatusChanged(setId, SetStatus.Ended);
    }

    function cancelSet(uint256 setId, bytes32 reason) external {
        Set storage s = sets[setId];
        if (s.dj == address(0)) revert EtrnaErrors.NotFound();

        bool can = (msg.sender == s.dj) || hasRole(SET_MANAGER_ROLE, msg.sender);
        if (!can) revert EtrnaErrors.Unauthorized();
        if (s.status == SetStatus.Settled || s.status == SetStatus.Cancelled) revert EtrnaErrors.InvalidState();

        s.status = SetStatus.Cancelled;
        emit SetCancelled(setId, reason);
        emit SetStatusChanged(setId, SetStatus.Cancelled);
    }

    function markSettled(uint256 setId) external onlyRole(SETTLEMENT_ROLE) {
        Set storage s = sets[setId];
        if (s.dj == address(0)) revert EtrnaErrors.NotFound();
        if (s.status != SetStatus.Ended) revert EtrnaErrors.InvalidState();
        s.status = SetStatus.Settled;
        emit SetStatusChanged(setId, SetStatus.Settled);
    }
}
