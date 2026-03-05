// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";

interface IERC20VotesLike {
    function balanceOf(address a) external view returns (uint256);
}

interface IReputationOracle {
    function reputationOf(address a) external view returns (uint256);
}

/// @notice GOV-001: Vote weight calculator blending token weight + reputation.
/// Plug into your governance UI / governor logic.
contract GovernanceHybrid is Ownable {
    event ParamsSet(uint32 tokenWeightBps, uint32 repWeightBps, uint32 repCapBps);

    IERC20VotesLike public immutable etr;
    IReputationOracle public repOracle;

    uint32 public tokenWeightBps = 8000;
    uint32 public repWeightBps = 2000;
    uint32 public repCapBps = 5000;

    // --- Timelock for oracle changes ---
    address public pendingOracle;
    uint256 public oracleChangeTime;
    uint256 public constant ORACLE_DELAY = 2 days;

    constructor(address etrToken, address repOracle_) {
        require(etrToken != address(0), "GovernanceHybrid: etr=0");
        etr = IERC20VotesLike(etrToken);
        repOracle = IReputationOracle(repOracle_);
    }

    /// @notice Step 1: propose a new oracle (timelocked)
    function proposeOracle(address newOracle) external onlyOwner {
        require(newOracle != address(0), "GH: oracle=0");
        pendingOracle = newOracle;
        oracleChangeTime = block.timestamp + ORACLE_DELAY;
    }

    /// @notice Step 2: accept the oracle after the delay has elapsed
    function acceptOracle() external onlyOwner {
        require(pendingOracle != address(0), "GH: no pending oracle");
        require(block.timestamp >= oracleChangeTime, "GH: delay not elapsed");
        repOracle = IReputationOracle(pendingOracle);
        pendingOracle = address(0);
        oracleChangeTime = 0;
    }

    function setParams(uint32 tokenBps, uint32 repBps, uint32 repCapBps_) external onlyOwner {
        require(tokenBps + repBps == 10000, "GovernanceHybrid: weights");
        require(repCapBps_ >= 100 && repCapBps_ <= 10000, "GH: cap out of range");
        tokenWeightBps = tokenBps;
        repWeightBps = repBps;
        repCapBps = repCapBps_;
        emit ParamsSet(tokenBps, repBps, repCapBps_);
    }

    function voteWeight(address voter, uint256 blockNumber) external view returns (uint256) {
        require(blockNumber < block.number, "GH: block not mined");
        uint256 t = IVotes(address(etr)).getPastVotes(voter, blockNumber);
        uint256 r = address(repOracle) == address(0) ? 0 : repOracle.reputationOf(voter);

        uint256 tokenPart = (t * tokenWeightBps) / 10000;
        uint256 repPartRaw = (r * repWeightBps) / 10000;

        uint256 repCap = (tokenPart * repCapBps) / 10000;
        uint256 repPart = repPartRaw > repCap ? repCap : repPartRaw;

        return tokenPart + repPart;
    }
}
