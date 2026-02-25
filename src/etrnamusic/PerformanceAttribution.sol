// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "openzeppelin-contracts/access/AccessControl.sol";

import {EtrnaErrors} from "../lib/EtrnaErrors.sol";
import {EtrnaMusicTypes} from "./EtrnaMusicTypes.sol";
import {DJSetLedger} from "./DJSetLedger.sol";
import {VenueProgramRegistry} from "./VenueProgramRegistry.sol";
import {CulturalSignalRegistry} from "./CulturalSignalRegistry.sol";

/**
 * @title PerformanceAttribution
 * @notice Settlement output contract for EtrnaMusic.
 *
 * Critical invariants:
 * - This contract DOES NOT mint $VIBE.
 * - It emits auditable reward unit assignments consumed by the Rewards Engine.
 *
 * v1 posture:
 * - SETTLEMENT_ROLE finalizes set attribution (conservative).
 * - Parameters (splits, community pool) are admin-governed.
 */
contract PerformanceAttribution is AccessControl {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant SETTLEMENT_ROLE = keccak256("SETTLEMENT_ROLE");

    bytes32 public constant PRODUCT_CODE = keccak256("ETRNAMUSIC");

    struct Settlement {
        bool exists;
        uint32 units;
        int16 meaningBps;
        uint256 signalBatchId;
        bytes32 attributionHash;
    }

    DJSetLedger public immutable djSetLedger;
    VenueProgramRegistry public immutable venueRegistry;
    CulturalSignalRegistry public immutable signalRegistry;

    address public communityPool;

    // Role split bps (sum must be 10000)
    uint16 public artistSplitBps = 4500;
    uint16 public djSplitBps = 2500;
    uint16 public venueSplitBps = 2000;
    uint16 public communitySplitBps = 1000;

    mapping(uint256 => mapping(uint64 => Settlement)) public settlements; // setId => epoch => Settlement

    event CommunityPoolSet(address indexed newCommunityPool);
    event RoleSplitsSet(uint16 artistBps, uint16 djBps, uint16 venueBps, uint16 communityBps);

    event SetAttributed(
        uint256 indexed setId,
        uint64 indexed epoch,
        uint32 units,
        int16 meaningBps,
        uint256 signalBatchId,
        bytes32 signalHash,
        bytes32 attributionHash
    );

    event RewardUnitsAssigned(
        bytes32 indexed productCode,
        uint64 indexed epoch,
        address indexed beneficiary,
        uint32 units,
        EtrnaMusicTypes.RewardRole role,
        bytes32 refId
    );

    constructor(
        address admin,
        address djSetLedger_,
        address venueRegistry_,
        address signalRegistry_,
        address communityPool_
    ) {
        if (admin == address(0) || djSetLedger_ == address(0) || venueRegistry_ == address(0) || signalRegistry_ == address(0)) {
            revert EtrnaErrors.ZeroAddress();
        }
        if (communityPool_ == address(0)) revert EtrnaErrors.ZeroAddress();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
        _grantRole(SETTLEMENT_ROLE, admin);

        djSetLedger = DJSetLedger(djSetLedger_);
        venueRegistry = VenueProgramRegistry(venueRegistry_);
        signalRegistry = CulturalSignalRegistry(signalRegistry_);

        communityPool = communityPool_;
    }

    // ---------------------------
    // Admin
    // ---------------------------

    function setCommunityPool(address newCommunityPool) external onlyRole(ADMIN_ROLE) {
        if (newCommunityPool == address(0)) revert EtrnaErrors.ZeroAddress();
        communityPool = newCommunityPool;
        emit CommunityPoolSet(newCommunityPool);
    }

    function setRoleSplits(uint16 artistBps, uint16 djBps, uint16 venueBps, uint16 communityBps) external onlyRole(ADMIN_ROLE) {
        uint256 sum = uint256(artistBps) + uint256(djBps) + uint256(venueBps) + uint256(communityBps);
        if (sum != EtrnaMusicTypes.MAX_BPS) revert EtrnaErrors.InvalidInput();
        artistSplitBps = artistBps;
        djSplitBps = djBps;
        venueSplitBps = venueBps;
        communitySplitBps = communityBps;
        emit RoleSplitsSet(artistBps, djBps, venueBps, communityBps);
    }

    // ---------------------------
    // Settlement
    // ---------------------------

    /// @notice Finalize a set attribution for an epoch.
    /// @param setId DJ set id
    /// @param epoch protocol epoch
    /// @param units normalized reward units for this set within the epoch policy
    /// @param meaningBps optional meaning score (transparency only)
    /// @param attributionHash keccak256 hash of canonical off-chain attribution payload (tracks, weights, raw signals)
    /// @param artistPayees beneficiary list for artist bucket (already normalized and capped)
    /// @param artistBps distribution within the artist bucket (sum=10000)
    function finalizeSetAttribution(
        uint256 setId,
        uint64 epoch,
        uint32 units,
        int16 meaningBps,
        bytes32 attributionHash,
        address[] calldata artistPayees,
        uint16[] calldata artistBps
    ) external onlyRole(SETTLEMENT_ROLE) {
        if (setId == 0 || epoch == 0 || units == 0) revert EtrnaErrors.InvalidInput();
        if (attributionHash == bytes32(0)) revert EtrnaErrors.InvalidInput();
        if (settlements[setId][epoch].exists) revert EtrnaErrors.AlreadyExists();

        // Require signal batch existence (anchored)
        uint256 batchId = signalRegistry.batchIdOf(setId, epoch);
        if (batchId == 0) revert EtrnaErrors.NotFound();
        (, , bytes32 signalHash, ) = signalRegistry.batches(batchId);

        // Pull set data
        (address dj, bytes32 venueId, , , , , , DJSetLedger.SetStatus status) = djSetLedger.sets(setId);
        if (dj == address(0)) revert EtrnaErrors.NotFound();
        if (status != DJSetLedger.SetStatus.Ended) revert EtrnaErrors.InvalidState();

        // Venue must be active + verified for settlement eligibility in v1.
        if (!venueRegistry.isActive(venueId)) revert EtrnaErrors.NotEnabled();
        if (!venueRegistry.isVerified(venueId)) revert EtrnaErrors.NotEnabled();

        address venuePayout = venueRegistry.payoutAddressOf(venueId);

        // Validate artist distribution
        uint256 n = artistPayees.length;
        if (n == 0 || n != artistBps.length) revert EtrnaErrors.InvalidInput();
        if (n > 32) revert EtrnaErrors.InvalidInput(); // safety cap

        uint256 sum;
        for (uint256 i = 0; i < n; i++) {
            if (artistPayees[i] == address(0)) revert EtrnaErrors.ZeroAddress();
            sum += artistBps[i];
        }
        if (sum != EtrnaMusicTypes.MAX_BPS) revert EtrnaErrors.InvalidInput();

        // Compute role buckets (units)
        uint256 total = units;
        uint256 artistUnits = (total * artistSplitBps) / EtrnaMusicTypes.MAX_BPS;
        uint256 djUnits = (total * djSplitBps) / EtrnaMusicTypes.MAX_BPS;
        uint256 venueUnits = (total * venueSplitBps) / EtrnaMusicTypes.MAX_BPS;
        uint256 communityUnits = total - artistUnits - djUnits - venueUnits; // remainder

        bytes32 refId = bytes32(setId);

        // Emit artist unit assignments (remainder to final payee)
        uint256 remaining = artistUnits;
        for (uint256 i = 0; i < n; i++) {
            uint256 u = (i == n - 1) ? remaining : (artistUnits * artistBps[i]) / EtrnaMusicTypes.MAX_BPS;
            if (u > remaining) u = remaining;
            remaining -= u;
            emit RewardUnitsAssigned(PRODUCT_CODE, epoch, artistPayees[i], uint32(u), EtrnaMusicTypes.RewardRole.ARTIST, refId);
        }

        // Emit DJ / Venue / Community unit assignments
        if (djUnits > 0) {
            emit RewardUnitsAssigned(PRODUCT_CODE, epoch, dj, uint32(djUnits), EtrnaMusicTypes.RewardRole.DJ, refId);
        }
        if (venueUnits > 0) {
            emit RewardUnitsAssigned(PRODUCT_CODE, epoch, venuePayout, uint32(venueUnits), EtrnaMusicTypes.RewardRole.VENUE, refId);
        }
        if (communityUnits > 0) {
            emit RewardUnitsAssigned(PRODUCT_CODE, epoch, communityPool, uint32(communityUnits), EtrnaMusicTypes.RewardRole.COMMUNITY, refId);
        }

        settlements[setId][epoch] = Settlement({
            exists: true,
            units: units,
            meaningBps: meaningBps,
            signalBatchId: batchId,
            attributionHash: attributionHash
        });

        emit SetAttributed(setId, epoch, units, meaningBps, batchId, signalHash, attributionHash);

        // Mark set settled in ledger (requires SETTLEMENT_ROLE granted to this contract)
        djSetLedger.markSettled(setId);
    }
}
