// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/governance/GovernanceHybrid.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";

/// @dev Mock ERC20Votes token with balanceOf and getPastVotes
contract MockERC20Votes is IERC20VotesLike {
    mapping(address => uint256) public override balanceOf;
    mapping(address => mapping(uint256 => uint256)) private _pastVotes;
    mapping(address => uint256) private _currentVotes;

    function setBalance(address a, uint256 amount) external {
        balanceOf[a] = amount;
        _currentVotes[a] = amount;
    }

    /// @dev Snapshot current votes at this block number
    function snapshot(address a, uint256 blockNum) external {
        _pastVotes[a][blockNum] = _currentVotes[a];
    }

    /// @dev IVotes.getPastVotes called by GovernanceHybrid
    function getPastVotes(address account, uint256 blockNumber) external view returns (uint256) {
        return _pastVotes[account][blockNumber];
    }

    // Unused IVotes stubs (needed for interface cast but not called by contract)
    function getVotes(address) external pure returns (uint256) { return 0; }
    function delegates(address) external pure returns (address) { return address(0); }
    function delegate(address) external pure {}
    function delegateBySig(address, uint256, uint256, uint8, bytes32, bytes32) external pure {}
}

/// @dev Mock reputation oracle
contract MockReputationOracle is IReputationOracle {
    mapping(address => uint256) public override reputationOf;

    function setReputation(address a, uint256 score) external {
        reputationOf[a] = score;
    }
}

contract GovernanceHybridTest is Test {
    GovernanceHybrid public gov;
    MockERC20Votes public token;
    MockReputationOracle public oracle;

    address owner = address(this);
    address voter1 = address(0xA);
    address voter2 = address(0xB);
    address nonOwner = address(0xC);

    function setUp() public {
        token = new MockERC20Votes();
        oracle = new MockReputationOracle();
        gov = new GovernanceHybrid(address(token), address(oracle));
    }

    // ─── Constructor ─────────────────────────────────────────

    function test_ConstructorSetsEtr() public view {
        assertEq(address(gov.etr()), address(token));
    }

    function test_ConstructorSetsOracle() public view {
        assertEq(address(gov.repOracle()), address(oracle));
    }

    function test_ConstructorSetsOwner() public view {
        assertEq(gov.owner(), owner);
    }

    function test_ConstructorDefaultParams() public view {
        assertEq(gov.tokenWeightBps(), 8000);
        assertEq(gov.repWeightBps(), 2000);
        assertEq(gov.repCapBps(), 5000);
    }

    function test_ConstructorRevertZeroToken() public {
        vm.expectRevert("GovernanceHybrid: etr=0");
        new GovernanceHybrid(address(0), address(oracle));
    }

    // ─── proposeOracle / acceptOracle (timelocked) ──────────

    function test_ProposeAndAcceptOracle() public {
        MockReputationOracle newOracle = new MockReputationOracle();
        gov.proposeOracle(address(newOracle));
        assertEq(gov.pendingOracle(), address(newOracle));

        // Fast-forward past the 2-day delay
        vm.warp(block.timestamp + 2 days);
        gov.acceptOracle();
        assertEq(address(gov.repOracle()), address(newOracle));
        assertEq(gov.pendingOracle(), address(0));
    }

    function test_AcceptOracleRevertBeforeDelay() public {
        MockReputationOracle newOracle = new MockReputationOracle();
        gov.proposeOracle(address(newOracle));

        vm.expectRevert("GH: delay not elapsed");
        gov.acceptOracle();
    }

    function test_ProposeOracleRevertZeroAddress() public {
        vm.expectRevert("GH: oracle=0");
        gov.proposeOracle(address(0));
    }

    function test_ProposeOracleRevertNonOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert("Ownable: caller is not the owner");
        gov.proposeOracle(address(0x99));
    }

    // ─── setParams ───────────────────────────────────────────

    function test_SetParams() public {
        gov.setParams(6000, 4000, 3000);
        assertEq(gov.tokenWeightBps(), 6000);
        assertEq(gov.repWeightBps(), 4000);
        assertEq(gov.repCapBps(), 3000);
    }

    function test_SetParamsEmitsEvent() public {
        vm.expectEmit(false, false, false, true);
        emit GovernanceHybrid.ParamsSet(7000, 3000, 4000);

        gov.setParams(7000, 3000, 4000);
    }

    function test_SetParamsRevertWeightsMustSum10000() public {
        vm.expectRevert("GovernanceHybrid: weights");
        gov.setParams(5000, 4000, 3000); // sums to 9000
    }

    function test_SetParamsRevertNonOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert("Ownable: caller is not the owner");
        gov.setParams(8000, 2000, 5000);
    }

    function test_SetParamsAllToken() public {
        gov.setParams(10000, 0, 100);
        assertEq(gov.tokenWeightBps(), 10000);
        assertEq(gov.repWeightBps(), 0);
    }

    function test_SetParamsAllReputation() public {
        gov.setParams(0, 10000, 10000);
        assertEq(gov.tokenWeightBps(), 0);
        assertEq(gov.repWeightBps(), 10000);
    }

    function test_SetParamsRevertCapOutOfRange() public {
        vm.expectRevert("GH: cap out of range");
        gov.setParams(8000, 2000, 0); // repCapBps below minimum (100)
    }

    // ─── voteWeight (now uses getPastVotes + blockNumber) ───

    /// Helper: set balance, snapshot at given block, then roll forward
    function _setupVoter(address v, uint256 bal, uint256 rep, uint256 snapBlock) internal {
        token.setBalance(v, bal);
        oracle.setReputation(v, rep);
        token.snapshot(v, snapBlock);
    }

    function test_VoteWeightDefaultParams() public {
        _setupVoter(voter1, 1000, 500, block.number);
        vm.roll(block.number + 1);

        // tokenPart = 1000 * 8000 / 10000 = 800
        // repPartRaw = 500 * 2000 / 10000 = 100
        // repCap = 800 * 5000 / 10000 = 400
        // repPart = min(100, 400) = 100
        // total = 800 + 100 = 900
        assertEq(gov.voteWeight(voter1, block.number - 1), 900);
    }

    function test_VoteWeightRepCapped() public {
        _setupVoter(voter1, 1000, 100_000, block.number);
        vm.roll(block.number + 1);

        assertEq(gov.voteWeight(voter1, block.number - 1), 1200);
    }

    function test_VoteWeightZeroTokens() public {
        _setupVoter(voter1, 0, 500, block.number);
        vm.roll(block.number + 1);

        assertEq(gov.voteWeight(voter1, block.number - 1), 0);
    }

    function test_VoteWeightZeroReputation() public {
        _setupVoter(voter1, 1000, 0, block.number);
        vm.roll(block.number + 1);

        assertEq(gov.voteWeight(voter1, block.number - 1), 800);
    }

    function test_VoteWeightZeroBoth() public {
        token.snapshot(voter1, block.number); // 0 balance snapshotted
        vm.roll(block.number + 1);

        assertEq(gov.voteWeight(voter1, block.number - 1), 0);
    }

    function test_VoteWeightNoOracle() public {
        // Propose zero oracle and warp past delay
        // Directly set oracle to 0 via a new deploy for simplicity
        GovernanceHybrid gov2 = new GovernanceHybrid(address(token), address(0));
        token.setBalance(voter1, 1000);
        token.snapshot(voter1, block.number);
        vm.roll(block.number + 1);

        assertEq(gov2.voteWeight(voter1, block.number - 1), 800);
    }

    function test_VoteWeightCustomParams5050() public {
        gov.setParams(5000, 5000, 10000);
        _setupVoter(voter1, 1000, 1000, block.number);
        vm.roll(block.number + 1);

        assertEq(gov.voteWeight(voter1, block.number - 1), 1000);
    }

    function test_VoteWeightAllTokenWeight() public {
        gov.setParams(10000, 0, 100);
        _setupVoter(voter1, 1000, 999, block.number);
        vm.roll(block.number + 1);

        assertEq(gov.voteWeight(voter1, block.number - 1), 1000);
    }

    function test_VoteWeightLargeValues() public {
        _setupVoter(voter1, 1_000_000 ether, 500_000 ether, block.number);
        vm.roll(block.number + 1);

        assertEq(gov.voteWeight(voter1, block.number - 1), 900_000 ether);
    }

    function test_VoteWeightMultipleVoters() public {
        _setupVoter(voter1, 1000, 200, block.number);
        vm.roll(block.number + 1);
        assertEq(gov.voteWeight(voter1, block.number - 1), 840);

        _setupVoter(voter2, 5000, 3000, block.number);
        vm.roll(block.number + 1);
        assertEq(gov.voteWeight(voter2, block.number - 1), 4600);
    }

    function test_VoteWeightRepPartExactlyCap() public {
        _setupVoter(voter1, 1000, 2000, block.number);
        vm.roll(block.number + 1);

        assertEq(gov.voteWeight(voter1, block.number - 1), 1200);
    }

    function test_VoteWeightRevertFutureBlock() public {
        vm.expectRevert("GH: block not mined");
        gov.voteWeight(voter1, block.number);
    }

    // ─── Ownership ───────────────────────────────────────────

    function test_TransferOwnership() public {
        gov.transferOwnership(nonOwner);
        assertEq(gov.owner(), nonOwner);

        vm.prank(nonOwner);
        gov.setParams(7000, 3000, 2000);
        assertEq(gov.tokenWeightBps(), 7000);
    }

    function test_RenounceOwnership() public {
        gov.renounceOwnership();
        assertEq(gov.owner(), address(0));

        vm.expectRevert("Ownable: caller is not the owner");
        gov.proposeOracle(address(0x99));
    }
}
