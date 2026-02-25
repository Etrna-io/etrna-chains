// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * FusionRegistry (Etrna Fusion Lab v3)
 * - Challenge rules anchored by uefRulesHash (UEF Vault provenance)
 * - Validator role separated from relayer/admin keys
 * - Minimal on-chain storage; off-chain scoring + audit trails
 */
contract FusionRegistry is AccessControl, ReentrancyGuard {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant RELAYER_ROLE = keccak256("RELAYER_ROLE");
    bytes32 public constant VALIDATOR_ROLE = keccak256("VALIDATOR_ROLE");

    struct Challenge {
        address creator;
        bytes32 uefRulesHash; // UEF hash for rubric/rules/docs
        string metadataURI;   // IPFS/HTTPS pointer for discovery
        uint64 createdAt;
        bool active;
    }

    struct Submission {
        uint256 challengeId;
        address submitter;
        bytes32 uefArtifactHash; // UEF hash for encrypted submission artifact
        bytes32 paramsHash;      // commit for parameters; reveal off-chain
        uint64 createdAt;
        bool verified;
        uint16 scoreBps;         // 0..10000
        bytes32 verifierRef;     // optional external ref (e.g., evaluation batch)
    }

    uint256 public nextChallengeId = 1;
    uint256 public nextSubmissionId = 1;

    mapping(uint256 => Challenge) public challenges;
    mapping(uint256 => Submission) public submissions;

    event ChallengeCreated(
        uint256 indexed challengeId,
        address indexed creator,
        bytes32 indexed uefRulesHash,
        string metadataURI
    );

    event ChallengeStatusUpdated(uint256 indexed challengeId, bool active);

    event SubmissionCreated(
        uint256 indexed submissionId,
        uint256 indexed challengeId,
        address indexed submitter,
        bytes32 uefArtifactHash,
        bytes32 paramsHash
    );

    event SubmissionVerified(
        uint256 indexed submissionId,
        uint256 indexed challengeId,
        address indexed verifier,
        uint16 scoreBps,
        bytes32 verifierRef
    );

    constructor(address admin) {
        require(admin != address(0), "FusionRegistry: admin=0");
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
    }

    function setRoleAdmin(bytes32 role, bytes32 adminRole) external onlyRole(ADMIN_ROLE) {
        _setRoleAdmin(role, adminRole);
    }

    function grantRelayer(address a) external onlyRole(ADMIN_ROLE) { _grantRole(RELAYER_ROLE, a); }
    function revokeRelayer(address a) external onlyRole(ADMIN_ROLE) { _revokeRole(RELAYER_ROLE, a); }
    function grantValidator(address a) external onlyRole(ADMIN_ROLE) { _grantRole(VALIDATOR_ROLE, a); }
    function revokeValidator(address a) external onlyRole(ADMIN_ROLE) { _revokeRole(VALIDATOR_ROLE, a); }

    function createChallenge(bytes32 uefRulesHash, string calldata metadataURI)
        external
        nonReentrant
        returns (uint256 challengeId)
    {
        require(uefRulesHash != bytes32(0), "FusionRegistry: uefRulesHash=0");
        challengeId = nextChallengeId++;
        challenges[challengeId] = Challenge({
            creator: msg.sender,
            uefRulesHash: uefRulesHash,
            metadataURI: metadataURI,
            createdAt: uint64(block.timestamp),
            active: true
        });
        emit ChallengeCreated(challengeId, msg.sender, uefRulesHash, metadataURI);
    }

    function setChallengeActive(uint256 challengeId, bool active) external onlyRole(ADMIN_ROLE) {
        require(challenges[challengeId].creator != address(0), "FusionRegistry: no challenge");
        challenges[challengeId].active = active;
        emit ChallengeStatusUpdated(challengeId, active);
    }

    function submit(
        uint256 challengeId,
        bytes32 uefArtifactHash,
        bytes32 paramsHash
    ) external nonReentrant returns (uint256 submissionId) {
        Challenge memory c = challenges[challengeId];
        require(c.creator != address(0), "FusionRegistry: no challenge");
        require(c.active, "FusionRegistry: inactive challenge");
        require(uefArtifactHash != bytes32(0), "FusionRegistry: uefArtifactHash=0");
        require(paramsHash != bytes32(0), "FusionRegistry: paramsHash=0");

        submissionId = nextSubmissionId++;
        submissions[submissionId] = Submission({
            challengeId: challengeId,
            submitter: msg.sender,
            uefArtifactHash: uefArtifactHash,
            paramsHash: paramsHash,
            createdAt: uint64(block.timestamp),
            verified: false,
            scoreBps: 0,
            verifierRef: bytes32(0)
        });

        emit SubmissionCreated(submissionId, challengeId, msg.sender, uefArtifactHash, paramsHash);
    }

    function verifySubmission(
        uint256 submissionId,
        uint16 scoreBps,
        bytes32 verifierRef
    ) external onlyRole(VALIDATOR_ROLE) nonReentrant {
        Submission storage s = submissions[submissionId];
        require(s.submitter != address(0), "FusionRegistry: no submission");
        require(!s.verified, "FusionRegistry: already verified");
        require(scoreBps <= 10000, "FusionRegistry: scoreBps>10000");

        s.verified = true;
        s.scoreBps = scoreBps;
        s.verifierRef = verifierRef;

        emit SubmissionVerified(submissionId, s.challengeId, msg.sender, scoreBps, verifierRef);
    }
}
