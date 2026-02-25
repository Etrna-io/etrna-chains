// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "openzeppelin-contracts/access/AccessControl.sol";

import {IEtrnaERC20} from "../interfaces/IEtrnaERC20.sol";
import {EtrnaErrors} from "../lib/EtrnaErrors.sol";

/**
 * @title VenueProgramRegistry
 * @notice Registry for venues participating in EtrnaMusic.
 *
 * v1 posture:
 * - venues are created/managed by VENUE_ADMIN_ROLE
 * - verified by VENUE_VERIFIER_ROLE
 * - optional $ETR stake deposits can be slashed by SLASHER_ROLE for abuse
 */
contract VenueProgramRegistry is AccessControl {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant VENUE_ADMIN_ROLE = keccak256("VENUE_ADMIN_ROLE");
    bytes32 public constant VENUE_VERIFIER_ROLE = keccak256("VENUE_VERIFIER_ROLE");
    bytes32 public constant SLASHER_ROLE = keccak256("SLASHER_ROLE");

    struct Venue {
        address owner;
        address payoutAddress;
        bytes32 metadataHash;
        bool active;
        bool verified;
        uint256 etrStake;
    }

    IEtrnaERC20 public immutable etr;

    mapping(bytes32 => Venue) public venues; // venueId => venue

    event VenueCreated(bytes32 indexed venueId, address indexed owner, address indexed payoutAddress, bytes32 metadataHash);
    event VenueStatusChanged(bytes32 indexed venueId, bool active);
    event VenueVerificationChanged(bytes32 indexed venueId, bool verified);
    event VenuePayoutChanged(bytes32 indexed venueId, address indexed payoutAddress);
    event VenueMetadataChanged(bytes32 indexed venueId, bytes32 indexed metadataHash);
    event VenueStakeDeposited(bytes32 indexed venueId, uint256 amount);
    event VenueStakeWithdrawn(bytes32 indexed venueId, uint256 amount);
    event VenueStakeSlashed(bytes32 indexed venueId, uint256 amount, bytes32 reason);

    constructor(address admin, address etrToken) {
        if (admin == address(0) || etrToken == address(0)) revert EtrnaErrors.ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
        _grantRole(VENUE_ADMIN_ROLE, admin);
        _grantRole(VENUE_VERIFIER_ROLE, admin);
        _grantRole(SLASHER_ROLE, admin);

        etr = IEtrnaERC20(etrToken);
    }

    /// @notice Deterministic venue id derivation.
    function deriveVenueId(address owner, bytes32 salt) public view returns (bytes32) {
        return keccak256(abi.encodePacked(block.chainid, owner, salt));
    }

    function createVenue(address owner, address payoutAddress, bytes32 metadataHash, bytes32 salt)
        external
        onlyRole(VENUE_ADMIN_ROLE)
        returns (bytes32 venueId)
    {
        if (owner == address(0) || payoutAddress == address(0)) revert EtrnaErrors.ZeroAddress();
        if (metadataHash == bytes32(0) || salt == bytes32(0)) revert EtrnaErrors.InvalidInput();

        venueId = deriveVenueId(owner, salt);
        if (venues[venueId].owner != address(0)) revert EtrnaErrors.AlreadyExists();

        venues[venueId] = Venue({
            owner: owner,
            payoutAddress: payoutAddress,
            metadataHash: metadataHash,
            active: false,
            verified: false,
            etrStake: 0
        });

        emit VenueCreated(venueId, owner, payoutAddress, metadataHash);
    }

    function setVenueStatus(bytes32 venueId, bool active) external onlyRole(VENUE_ADMIN_ROLE) {
        Venue storage v = venues[venueId];
        if (v.owner == address(0)) revert EtrnaErrors.NotFound();
        v.active = active;
        emit VenueStatusChanged(venueId, active);
    }

    function setVenueVerification(bytes32 venueId, bool verified) external onlyRole(VENUE_VERIFIER_ROLE) {
        Venue storage v = venues[venueId];
        if (v.owner == address(0)) revert EtrnaErrors.NotFound();
        v.verified = verified;
        emit VenueVerificationChanged(venueId, verified);
    }

    function setVenuePayoutAddress(bytes32 venueId, address payoutAddress) external {
        if (payoutAddress == address(0)) revert EtrnaErrors.ZeroAddress();
        Venue storage v = venues[venueId];
        if (v.owner == address(0)) revert EtrnaErrors.NotFound();
        if (msg.sender != v.owner && !hasRole(VENUE_ADMIN_ROLE, msg.sender)) revert EtrnaErrors.Unauthorized();
        v.payoutAddress = payoutAddress;
        emit VenuePayoutChanged(venueId, payoutAddress);
    }

    function setVenueMetadataHash(bytes32 venueId, bytes32 metadataHash) external {
        if (metadataHash == bytes32(0)) revert EtrnaErrors.InvalidInput();
        Venue storage v = venues[venueId];
        if (v.owner == address(0)) revert EtrnaErrors.NotFound();
        if (msg.sender != v.owner && !hasRole(VENUE_ADMIN_ROLE, msg.sender)) revert EtrnaErrors.Unauthorized();
        v.metadataHash = metadataHash;
        emit VenueMetadataChanged(venueId, metadataHash);
    }

    function depositStake(bytes32 venueId, uint256 amount) external {
        if (amount == 0) revert EtrnaErrors.InvalidInput();
        Venue storage v = venues[venueId];
        if (v.owner == address(0)) revert EtrnaErrors.NotFound();
        if (msg.sender != v.owner) revert EtrnaErrors.Unauthorized();
        bool ok = etr.transferFrom(msg.sender, address(this), amount);
        if (!ok) revert EtrnaErrors.InvalidState();
        v.etrStake += amount;
        emit VenueStakeDeposited(venueId, amount);
    }

    /// @notice Stake withdrawals are restricted to inactive venues in v1.
    function withdrawStake(bytes32 venueId, uint256 amount) external {
        if (amount == 0) revert EtrnaErrors.InvalidInput();
        Venue storage v = venues[venueId];
        if (v.owner == address(0)) revert EtrnaErrors.NotFound();
        if (msg.sender != v.owner) revert EtrnaErrors.Unauthorized();
        if (v.active) revert EtrnaErrors.InvalidState();
        if (v.etrStake < amount) revert EtrnaErrors.InsufficientStake();

        v.etrStake -= amount;
        bool ok = etr.transfer(msg.sender, amount);
        if (!ok) revert EtrnaErrors.InvalidState();
        emit VenueStakeWithdrawn(venueId, amount);
    }

    /// @notice Slash stake for abuse. Slashed stake remains in-contract for treasury routing in v1.
    function slashStake(bytes32 venueId, uint256 amount, bytes32 reason) external onlyRole(SLASHER_ROLE) {
        if (amount == 0) revert EtrnaErrors.InvalidInput();
        Venue storage v = venues[venueId];
        if (v.owner == address(0)) revert EtrnaErrors.NotFound();
        if (v.etrStake < amount) revert EtrnaErrors.InsufficientStake();

        v.etrStake -= amount;
        emit VenueStakeSlashed(venueId, amount, reason);
    }

    // ---------------------------
    // View helpers
    // ---------------------------

    function payoutAddressOf(bytes32 venueId) external view returns (address) {
        Venue storage v = venues[venueId];
        if (v.owner == address(0)) revert EtrnaErrors.NotFound();
        return v.payoutAddress;
    }

    function isActive(bytes32 venueId) external view returns (bool) {
        Venue storage v = venues[venueId];
        if (v.owner == address(0)) revert EtrnaErrors.NotFound();
        return v.active;
    }

    function isVerified(bytes32 venueId) external view returns (bool) {
        Venue storage v = venues[venueId];
        if (v.owner == address(0)) revert EtrnaErrors.NotFound();
        return v.verified;
    }
}
