// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title  VibeCheckRegistry
 * @author ETRNA Technologies Inc.
 * @notice On-chain ledger for VibeCheck check-ins, presence receipts,
 *         and music ratings.  Designed as a UUPS-upgradeable singleton
 *         deployed behind an ERC-1967 proxy.
 *
 *         All string IDs are keccak256-hashed off-chain before submission.
 */
contract VibeCheckRegistry is Initializable, UUPSUpgradeable, Ownable {
    // ─── Types ──────────────────────────────────────────────────────────
    enum VerifyStatus {
        Unverified,   // 0
        Verified,     // 1
        Flagged,      // 2
        Rejected      // 3
    }

    struct CheckIn {
        address  user;
        bytes32  venueId;
        bytes32  proofHash;
        uint256  timestamp;
        VerifyStatus status;
        string   receiptUri;
    }

    struct MusicRating {
        bytes32  checkInId;
        address  user;
        uint8    rating;        // 1-5
        bytes32  nowPlayingHash;
        uint256  timestamp;
    }

    // ─── Storage ────────────────────────────────────────────────────────
    mapping(bytes32 => CheckIn)      private _checkIns;
    mapping(address => bytes32[])    private _userCheckIns;
    mapping(bytes32 => bytes32[])    private _venueCheckIns;

    mapping(bytes32 => MusicRating)  private _musicRatings;

    uint256 public totalCheckIns;
    uint256 public totalMusicRatings;

    // ─── Events ─────────────────────────────────────────────────────────
    event CheckInCommitted(
        bytes32 indexed checkInId,
        address indexed user,
        bytes32 indexed venueId,
        bytes32 proofHash,
        uint256 timestamp
    );

    event CheckInVerified(
        bytes32 indexed checkInId,
        uint8   status
    );

    event PresenceReceiptAnchored(
        bytes32 indexed checkInId,
        string  receiptUri
    );

    event MusicRatingCommitted(
        bytes32 indexed ratingId,
        bytes32 indexed checkInId,
        address indexed user,
        uint8   rating,
        bytes32 nowPlayingHash
    );

    // ─── Initializer ───────────────────────────────────────────────────
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() external initializer {
        _transferOwnership(msg.sender);
    }

    // ─── Check-In Operations ────────────────────────────────────────────
    /**
     * @notice Commit a new check-in proof on-chain.
     * @param  checkInId   Keccak-256 of the off-chain check-in ID.
     * @param  venueId     Keccak-256 of the venue identifier.
     * @param  proofHash   Keccak-256 of the proof payload (photo, GPS, etc.).
     */
    function commitCheckIn(
        bytes32 checkInId,
        bytes32 venueId,
        bytes32 proofHash
    ) external {
        require(_checkIns[checkInId].timestamp == 0, "VC: duplicate check-in");

        _checkIns[checkInId] = CheckIn({
            user:       msg.sender,
            venueId:    venueId,
            proofHash:  proofHash,
            timestamp:  block.timestamp,
            status:     VerifyStatus.Unverified,
            receiptUri: ""
        });

        _userCheckIns[msg.sender].push(checkInId);
        _venueCheckIns[venueId].push(checkInId);
        totalCheckIns++;

        emit CheckInCommitted(checkInId, msg.sender, venueId, proofHash, block.timestamp);
    }

    /**
     * @notice Update the verification status of a check-in (owner only).
     * @param  checkInId  The check-in to update.
     * @param  status     New status (0-3).
     */
    function verifyCheckIn(bytes32 checkInId, uint8 status) external onlyOwner {
        require(_checkIns[checkInId].timestamp != 0, "VC: unknown check-in");
        require(status <= uint8(VerifyStatus.Rejected), "VC: invalid status");

        _checkIns[checkInId].status = VerifyStatus(status);
        emit CheckInVerified(checkInId, status);
    }

    /**
     * @notice Attach a presence receipt URI (IPFS or HTTPS) to a check-in.
     * @param  checkInId   The check-in to annotate.
     * @param  receiptUri  URI for the receipt artifact.
     */
    function anchorPresenceReceipt(
        bytes32 checkInId,
        string calldata receiptUri
    ) external onlyOwner {
        require(_checkIns[checkInId].timestamp != 0, "VC: unknown check-in");
        _checkIns[checkInId].receiptUri = receiptUri;
        emit PresenceReceiptAnchored(checkInId, receiptUri);
    }

    // ─── Music Rating ───────────────────────────────────────────────────
    /**
     * @notice Anchor a music rating on-chain.
     * @param  ratingId       Keccak-256 of the off-chain rating ID.
     * @param  checkInId      The parent check-in this rating belongs to.
     * @param  rating         Score 1-5.
     * @param  nowPlayingHash Keccak-256 of the now-playing metadata.
     */
    function commitMusicRating(
        bytes32 ratingId,
        bytes32 checkInId,
        uint8   rating,
        bytes32 nowPlayingHash
    ) external {
        require(rating >= 1 && rating <= 5, "VC: rating 1-5");
        require(_musicRatings[ratingId].timestamp == 0, "VC: duplicate rating");

        _musicRatings[ratingId] = MusicRating({
            checkInId:      checkInId,
            user:           msg.sender,
            rating:         rating,
            nowPlayingHash: nowPlayingHash,
            timestamp:      block.timestamp
        });

        totalMusicRatings++;

        emit MusicRatingCommitted(ratingId, checkInId, msg.sender, rating, nowPlayingHash);
    }

    // ─── View Functions ─────────────────────────────────────────────────
    function getCheckIn(bytes32 checkInId)
        external
        view
        returns (
            address user,
            bytes32 venueId,
            bytes32 proofHash,
            uint256 timestamp,
            uint8   status,
            string memory receiptUri
        )
    {
        CheckIn storage ci = _checkIns[checkInId];
        return (ci.user, ci.venueId, ci.proofHash, ci.timestamp, uint8(ci.status), ci.receiptUri);
    }

    function getUserCheckIns(address user) external view returns (bytes32[] memory) {
        return _userCheckIns[user];
    }

    function getVenueCheckIns(bytes32 venueId) external view returns (bytes32[] memory) {
        return _venueCheckIns[venueId];
    }

    function getMusicRating(bytes32 ratingId)
        external
        view
        returns (
            bytes32 checkInId,
            address user,
            uint8   rating,
            bytes32 nowPlayingHash,
            uint256 timestamp
        )
    {
        MusicRating storage mr = _musicRatings[ratingId];
        return (mr.checkInId, mr.user, mr.rating, mr.nowPlayingHash, mr.timestamp);
    }

    // ─── UUPS Upgrade Auth ──────────────────────────────────────────────
    function _authorizeUpgrade(address) internal override onlyOwner {}
}
