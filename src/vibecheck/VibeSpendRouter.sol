// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControl} from "openzeppelin-contracts/access/AccessControl.sol";
import {Pausable} from "openzeppelin-contracts/security/Pausable.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/security/ReentrancyGuard.sol";

/**
 * @title VibeSpendRouter
 * @notice On-chain spending gateway for $VIBE.
 *
 * Users approve this router, then call purchase functions to:
 *   - Buy Cribs (bases)
 *   - Upgrade Crib modules
 *   - Boost venues
 *   - Purchase Night Packages
 *
 * $VIBE is transferred to the treasury. A backend indexer listens for
 * events and activates the corresponding off-chain entities.
 *
 * Design rationale:
 *   Day-to-day micro-spending (boosts, small upgrades) stays off-chain.
 *   Only significant purchases (Cribs, premium modules) settle on-chain.
 */
contract VibeSpendRouter is AccessControl, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ─── Roles ──────────────────────────────────────────────────────────
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant PAUSER_ROLE   = keccak256("PAUSER_ROLE");

    // ─── State ──────────────────────────────────────────────────────────
    IERC20 public immutable vibeToken;
    address public treasury;

    uint256 public nextCribId;
    uint256 public totalVibeSpent;

    // Price tiers (can be updated by OPERATOR)
    mapping(string => uint256) public priceTiers;  // e.g. "CRIB_STARTER" => 1000e18

    // ─── Events ─────────────────────────────────────────────────────────
    event CribPurchased(
        address indexed buyer,
        uint256 indexed cribId,
        string tier,
        uint256 vibeSpent,
        string name
    );

    event ModuleUpgraded(
        address indexed owner,
        uint256 indexed cribId,
        string moduleType,
        uint256 newLevel,
        uint256 vibeSpent
    );

    event VenueBoostPurchased(
        address indexed booster,
        string venueId,
        uint256 vibeSpent,
        uint256 boostHours
    );

    event PackagePurchased(
        address indexed buyer,
        string packageId,
        uint256 vibeSpent,
        uint256 partySize
    );

    event PriceTierSet(string tier, uint256 price);
    event TreasuryUpdated(address oldTreasury, address newTreasury);

    // ─── Errors ─────────────────────────────────────────────────────────
    error ZeroAddress();
    error ZeroAmount();
    error InsufficientAllowance();
    error InvalidTier();
    error EmptyName();

    // ─── Constructor ────────────────────────────────────────────────────
    constructor(
        address vibeToken_,
        address treasury_,
        address admin
    ) {
        if (vibeToken_ == address(0) || treasury_ == address(0) || admin == address(0))
            revert ZeroAddress();

        vibeToken = IERC20(vibeToken_);
        treasury = treasury_;

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(OPERATOR_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);

        // Default price tiers (in VIBE with 18 decimals)
        priceTiers["CRIB_STARTER"]   = 500 ether;
        priceTiers["CRIB_UPGRADED"]  = 2_000 ether;
        priceTiers["CRIB_PREMIUM"]   = 10_000 ether;
        priceTiers["CRIB_LEGENDARY"] = 50_000 ether;
        priceTiers["MODULE_UPGRADE"] = 200 ether;   // per level
        priceTiers["VENUE_BOOST_1H"] = 100 ether;
        priceTiers["VENUE_BOOST_6H"] = 500 ether;
        priceTiers["VENUE_BOOST_24H"] = 1_500 ether;
    }

    // ─── Purchase Crib ──────────────────────────────────────────────────

    /**
     * @notice Buy a new Crib (base).
     * @param tier Tier key (e.g., "CRIB_STARTER")
     * @param name Display name for the crib
     */
    function purchaseCrib(
        string calldata tier,
        string calldata name
    ) external whenNotPaused nonReentrant returns (uint256 cribId) {
        uint256 price = priceTiers[tier];
        if (price == 0) revert InvalidTier();
        if (bytes(name).length == 0) revert EmptyName();

        vibeToken.safeTransferFrom(msg.sender, treasury, price);

        cribId = nextCribId++;
        totalVibeSpent += price;

        emit CribPurchased(msg.sender, cribId, tier, price, name);
    }

    // ─── Upgrade Module ─────────────────────────────────────────────────

    /**
     * @notice Upgrade a module in a crib. Cost = MODULE_UPGRADE × newLevel.
     * @param cribId The crib's on-chain ID
     * @param moduleType Type of module being upgraded
     * @param newLevel The level being upgraded TO (2+)
     */
    function upgradeModule(
        uint256 cribId,
        string calldata moduleType,
        uint256 newLevel
    ) external whenNotPaused nonReentrant {
        uint256 basePrice = priceTiers["MODULE_UPGRADE"];
        if (basePrice == 0) revert InvalidTier();

        uint256 cost = basePrice * newLevel;
        vibeToken.safeTransferFrom(msg.sender, treasury, cost);
        totalVibeSpent += cost;

        emit ModuleUpgraded(msg.sender, cribId, moduleType, newLevel, cost);
    }

    // ─── Boost Venue ────────────────────────────────────────────────────

    /**
     * @notice Boost a venue for a specified duration.
     * @param venueId Off-chain venue ID
     * @param boostTier "VENUE_BOOST_1H", "VENUE_BOOST_6H", or "VENUE_BOOST_24H"
     */
    function boostVenue(
        string calldata venueId,
        string calldata boostTier
    ) external whenNotPaused nonReentrant {
        uint256 price = priceTiers[boostTier];
        if (price == 0) revert InvalidTier();

        vibeToken.safeTransferFrom(msg.sender, treasury, price);
        totalVibeSpent += price;

        uint256 hours_;
        if (keccak256(bytes(boostTier)) == keccak256("VENUE_BOOST_1H")) hours_ = 1;
        else if (keccak256(bytes(boostTier)) == keccak256("VENUE_BOOST_6H")) hours_ = 6;
        else hours_ = 24;

        emit VenueBoostPurchased(msg.sender, venueId, price, hours_);
    }

    // ─── Package Purchase ───────────────────────────────────────────────

    /**
     * @notice Purchase a Night Package with $VIBE (full or partial payment).
     * @param packageId Off-chain package ID
     * @param vibeAmount Amount of $VIBE to spend
     * @param partySize Number of people
     */
    function purchasePackage(
        string calldata packageId,
        uint256 vibeAmount,
        uint256 partySize
    ) external whenNotPaused nonReentrant {
        if (vibeAmount == 0) revert ZeroAmount();

        vibeToken.safeTransferFrom(msg.sender, treasury, vibeAmount);
        totalVibeSpent += vibeAmount;

        emit PackagePurchased(msg.sender, packageId, vibeAmount, partySize);
    }

    // ─── Admin ──────────────────────────────────────────────────────────

    function setPriceTier(string calldata tier, uint256 price) external onlyRole(OPERATOR_ROLE) {
        priceTiers[tier] = price;
        emit PriceTierSet(tier, price);
    }

    function setTreasury(address newTreasury) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newTreasury == address(0)) revert ZeroAddress();
        emit TreasuryUpdated(treasury, newTreasury);
        treasury = newTreasury;
    }

    function pause() external onlyRole(PAUSER_ROLE) { _pause(); }
    function unpause() external onlyRole(PAUSER_ROLE) { _unpause(); }
}
