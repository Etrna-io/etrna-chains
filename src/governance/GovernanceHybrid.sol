// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

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

    constructor(address etrToken, address repOracle_) {
        require(etrToken != address(0), "GovernanceHybrid: etr=0");
        etr = IERC20VotesLike(etrToken);
        repOracle = IReputationOracle(repOracle_);
    }

    function setOracle(address repOracle_) external onlyOwner {
        repOracle = IReputationOracle(repOracle_);
    }

    function setParams(uint32 tokenBps, uint32 repBps, uint32 repCapBps_) external onlyOwner {
        require(tokenBps + repBps == 10000, "GovernanceHybrid: weights");
        tokenWeightBps = tokenBps;
        repWeightBps = repBps;
        repCapBps = repCapBps_;
        emit ParamsSet(tokenBps, repBps, repCapBps_);
    }

    function voteWeight(address voter) external view returns (uint256) {
        uint256 t = etr.balanceOf(voter);
        uint256 r = address(repOracle) == address(0) ? 0 : repOracle.reputationOf(voter);

        uint256 tokenPart = (t * tokenWeightBps) / 10000;
        uint256 repPartRaw = (r * repWeightBps) / 10000;

        uint256 repCap = (tokenPart * repCapBps) / 10000;
        uint256 repPart = repPartRaw > repCap ? repCap : repPartRaw;

        return tokenPart + repPart;
    }
}
