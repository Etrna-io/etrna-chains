// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {EtrnaErrors} from "../lib/EtrnaErrors.sol";

/**
 * @title MilestoneEscrow
 * @notice Holds ERC-20 pledge funds for EtrnaVerse blueprints and releases
 *         them progressively as milestones are approved.
 *
 * Flow:
 *  1. Anyone can pledge funds via `pledge(blueprintId, amount)`
 *  2. Blueprint creator defines milestones via `defineMilestones()`
 *  3. Approvers approve milestones → `approveMilestone()`
 *  4. After approval, milestone funds are released → `releaseMilestone()`
 *  5. If a project is abandoned, pledgers can reclaim via `refund()`
 */
contract MilestoneEscrow is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant APPROVER_ROLE = keccak256("APPROVER_ROLE");

    enum MilestoneStatus { PENDING, APPROVED, RELEASED }
    enum CampaignStatus { ACTIVE, COMPLETED, REFUNDING }

    struct Milestone {
        string label;
        uint256 amount;
        MilestoneStatus status;
    }

    struct Campaign {
        bytes32 blueprintId;
        address payable creator;
        address token;
        uint256 totalPledged;
        uint256 totalReleased;
        CampaignStatus status;
        uint256 milestoneCount;
    }

    struct PledgeRecord {
        address pledger;
        uint256 amount;
        bool refunded;
    }

    uint256 public nextCampaignId;

    mapping(uint256 => Campaign) public campaigns;
    mapping(uint256 => mapping(uint256 => Milestone)) public milestones;
    mapping(uint256 => PledgeRecord[]) public pledges;

    event CampaignCreated(uint256 indexed campaignId, bytes32 indexed blueprintId, address creator, address token);
    event Pledged(uint256 indexed campaignId, address indexed pledger, uint256 amount);
    event MilestonesDefined(uint256 indexed campaignId, uint256 count);
    event MilestoneApproved(uint256 indexed campaignId, uint256 indexed index);
    event MilestoneReleased(uint256 indexed campaignId, uint256 indexed index, uint256 amount);
    event CampaignCompleted(uint256 indexed campaignId);
    event Refunded(uint256 indexed campaignId, address indexed pledger, uint256 amount);

    constructor(address admin) {
        if (admin == address(0)) revert EtrnaErrors.ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(APPROVER_ROLE, admin);
    }

    // ─── Campaign lifecycle ────────────────────────────────────────────

    function createCampaign(
        bytes32 blueprintId,
        address payable creator,
        address token
    ) external returns (uint256 campaignId) {
        if (creator == address(0) || token == address(0)) revert EtrnaErrors.ZeroAddress();
        if (blueprintId == bytes32(0)) revert EtrnaErrors.InvalidInput();

        campaignId = ++nextCampaignId;
        campaigns[campaignId] = Campaign({
            blueprintId: blueprintId,
            creator: creator,
            token: token,
            totalPledged: 0,
            totalReleased: 0,
            status: CampaignStatus.ACTIVE,
            milestoneCount: 0
        });

        emit CampaignCreated(campaignId, blueprintId, creator, token);
    }

    function defineMilestones(
        uint256 campaignId,
        string[] calldata labels,
        uint256[] calldata amounts
    ) external {
        Campaign storage c = campaigns[campaignId];
        if (c.creator == address(0)) revert EtrnaErrors.NotFound();
        if (msg.sender != c.creator && !hasRole(DEFAULT_ADMIN_ROLE, msg.sender))
            revert EtrnaErrors.Unauthorized();
        if (labels.length != amounts.length || labels.length == 0) revert EtrnaErrors.InvalidInput();
        if (c.milestoneCount > 0) revert EtrnaErrors.AlreadyExists();

        for (uint256 i = 0; i < labels.length; i++) {
            milestones[campaignId][i] = Milestone({
                label: labels[i],
                amount: amounts[i],
                status: MilestoneStatus.PENDING
            });
        }
        c.milestoneCount = labels.length;

        emit MilestonesDefined(campaignId, labels.length);
    }

    // ─── Pledging ──────────────────────────────────────────────────────

    function pledge(uint256 campaignId, uint256 amount) external nonReentrant {
        Campaign storage c = campaigns[campaignId];
        if (c.creator == address(0)) revert EtrnaErrors.NotFound();
        if (c.status != CampaignStatus.ACTIVE) revert EtrnaErrors.InvalidState();
        if (amount == 0) revert EtrnaErrors.InvalidInput();

        IERC20(c.token).safeTransferFrom(msg.sender, address(this), amount);
        c.totalPledged += amount;
        pledges[campaignId].push(PledgeRecord({
            pledger: msg.sender,
            amount: amount,
            refunded: false
        }));

        emit Pledged(campaignId, msg.sender, amount);
    }

    // ─── Milestone approval & release ──────────────────────────────────

    function approveMilestone(uint256 campaignId, uint256 index) external onlyRole(APPROVER_ROLE) {
        Campaign storage c = campaigns[campaignId];
        if (c.creator == address(0)) revert EtrnaErrors.NotFound();
        if (index >= c.milestoneCount) revert EtrnaErrors.InvalidInput();

        Milestone storage m = milestones[campaignId][index];
        if (m.status != MilestoneStatus.PENDING) revert EtrnaErrors.InvalidState();

        m.status = MilestoneStatus.APPROVED;
        emit MilestoneApproved(campaignId, index);
    }

    function releaseMilestone(uint256 campaignId, uint256 index) external nonReentrant {
        Campaign storage c = campaigns[campaignId];
        if (c.creator == address(0)) revert EtrnaErrors.NotFound();
        if (index >= c.milestoneCount) revert EtrnaErrors.InvalidInput();

        Milestone storage m = milestones[campaignId][index];
        if (m.status != MilestoneStatus.APPROVED) revert EtrnaErrors.InvalidState();

        uint256 amount = m.amount;
        if (amount > c.totalPledged - c.totalReleased) {
            amount = c.totalPledged - c.totalReleased;
        }

        m.status = MilestoneStatus.RELEASED;
        c.totalReleased += amount;
        IERC20(c.token).safeTransfer(c.creator, amount);

        emit MilestoneReleased(campaignId, index, amount);

        // Check if all milestones released
        bool allReleased = true;
        for (uint256 i = 0; i < c.milestoneCount; i++) {
            if (milestones[campaignId][i].status != MilestoneStatus.RELEASED) {
                allReleased = false;
                break;
            }
        }
        if (allReleased) {
            c.status = CampaignStatus.COMPLETED;
            emit CampaignCompleted(campaignId);
        }
    }

    // ─── Refunding ─────────────────────────────────────────────────────

    function enableRefunds(uint256 campaignId) external onlyRole(DEFAULT_ADMIN_ROLE) {
        Campaign storage c = campaigns[campaignId];
        if (c.creator == address(0)) revert EtrnaErrors.NotFound();
        c.status = CampaignStatus.REFUNDING;
    }

    function refund(uint256 campaignId, uint256 pledgeIndex) external nonReentrant {
        Campaign storage c = campaigns[campaignId];
        if (c.status != CampaignStatus.REFUNDING) revert EtrnaErrors.InvalidState();

        PledgeRecord storage p = pledges[campaignId][pledgeIndex];
        if (p.pledger != msg.sender) revert EtrnaErrors.Unauthorized();
        if (p.refunded) revert EtrnaErrors.AlreadyExists();

        p.refunded = true;
        IERC20(c.token).safeTransfer(msg.sender, p.amount);

        emit Refunded(campaignId, msg.sender, p.amount);
    }

    // ─── Views ─────────────────────────────────────────────────────────

    function getPledgeCount(uint256 campaignId) external view returns (uint256) {
        return pledges[campaignId].length;
    }

    function getMilestone(uint256 campaignId, uint256 index)
        external view returns (string memory label, uint256 amount, MilestoneStatus status)
    {
        Milestone storage m = milestones[campaignId][index];
        return (m.label, m.amount, m.status);
    }
}
