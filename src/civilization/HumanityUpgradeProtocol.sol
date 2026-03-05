// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "openzeppelin-contracts/access/AccessControl.sol";

import {IEtrnaERC20} from "../interfaces/IEtrnaERC20.sol";
import {EtrnaErrors} from "../lib/EtrnaErrors.sol";

/**
 * @title HumanityUpgradeProtocol (HUP)
 * @notice Core on-chain commitments for skills and ethics.
 *
 * v0 provides:
 * - Register skill versions (hashes)
 * - Register ethics commitments (hashes)
 * - Optional staking + slashing for breached commitments
 */
contract HumanityUpgradeProtocol is AccessControl {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant ATTESTER_ROLE = keccak256("ATTESTER_ROLE");
    bytes32 public constant SLASHER_ROLE = keccak256("SLASHER_ROLE");

    event SkillVersionSet(address indexed user, bytes32 indexed skillCode, uint32 version, bytes32 proofHash);
    event EthicsCommitmentSet(address indexed user, bytes32 indexed commitmentCode, bytes32 proofHash, uint256 stake);
    event CommitmentSlashed(address indexed user, bytes32 indexed commitmentCode, uint256 amount, bytes32 reason);

    struct Commitment {
        bytes32 proofHash;
        uint256 stake;
        bool active;
    }

    IEtrnaERC20 public immutable etr;

    // user => skill => version => proofHash
    mapping(address => mapping(bytes32 => mapping(uint32 => bytes32))) public skillProofs;
    // user => skill => current version
    mapping(address => mapping(bytes32 => uint32)) public currentSkillVersion;

    // user => commitmentCode => Commitment
    mapping(address => mapping(bytes32 => Commitment)) public commitments;

    constructor(address admin, address etrToken) {
        if (admin == address(0) || etrToken == address(0)) revert EtrnaErrors.ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
        _grantRole(ATTESTER_ROLE, admin);
        _grantRole(SLASHER_ROLE, admin);
        etr = IEtrnaERC20(etrToken);
    }

    function setSkillVersion(address user, bytes32 skillCode, uint32 version, bytes32 proofHash) external onlyRole(ATTESTER_ROLE) {
        if (user == address(0)) revert EtrnaErrors.ZeroAddress();
        if (skillCode == bytes32(0) || version == 0 || proofHash == bytes32(0)) revert EtrnaErrors.InvalidInput();

        skillProofs[user][skillCode][version] = proofHash;
        if (version > currentSkillVersion[user][skillCode]) {
            currentSkillVersion[user][skillCode] = version;
        }
        emit SkillVersionSet(user, skillCode, version, proofHash);
    }

    function setEthicsCommitment(bytes32 commitmentCode, bytes32 proofHash, uint256 stake) external {
        if (commitmentCode == bytes32(0) || proofHash == bytes32(0)) revert EtrnaErrors.InvalidInput();

        Commitment storage c = commitments[msg.sender][commitmentCode];
        if (c.active) revert EtrnaErrors.AlreadyExists();

        if (stake > 0) {
            bool ok = etr.transferFrom(msg.sender, address(this), stake);
            if (!ok) revert EtrnaErrors.InvalidState();
        }

        commitments[msg.sender][commitmentCode] = Commitment({proofHash: proofHash, stake: stake, active: true});
        emit EthicsCommitmentSet(msg.sender, commitmentCode, proofHash, stake);
    }

    function slashCommitment(address user, bytes32 commitmentCode, uint256 amount, bytes32 reason) external onlyRole(SLASHER_ROLE) {
        Commitment storage c = commitments[user][commitmentCode];
        if (!c.active) revert EtrnaErrors.NotActive();
        if (amount == 0 || amount > c.stake) revert EtrnaErrors.InvalidInput();

        c.stake -= amount;
        emit CommitmentSlashed(user, commitmentCode, amount, reason);
        // v0: retain slashed stake for treasury routing; later route via governance.
    }

    function closeCommitment(bytes32 commitmentCode) external {
        Commitment storage c = commitments[msg.sender][commitmentCode];
        if (!c.active) revert EtrnaErrors.NotActive();

        c.active = false;
        uint256 stake = c.stake;
        c.stake = 0;
        if (stake > 0) {
            bool ok = etr.transfer(msg.sender, stake);
            if (!ok) revert EtrnaErrors.InvalidState();
        }
    }
}
