// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/governance/GovernanceHybrid.sol";

/// @dev Mock ERC20 with balanceOf
contract MockERC20Votes is IERC20VotesLike {
    mapping(address => uint256) public override balanceOf;

    function setBalance(address a, uint256 amount) external {
        balanceOf[a] = amount;
    }
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

    // ─── setOracle ───────────────────────────────────────────

    function test_SetOracle() public {
        MockReputationOracle newOracle = new MockReputationOracle();
        gov.setOracle(address(newOracle));
        assertEq(address(gov.repOracle()), address(newOracle));
    }

    function test_SetOracleToZero() public {
        gov.setOracle(address(0));
        assertEq(address(gov.repOracle()), address(0));
    }

    function test_SetOracleRevertNonOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert("Ownable: caller is not the owner");
        gov.setOracle(address(0x99));
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
        gov.setParams(10000, 0, 0);
        assertEq(gov.tokenWeightBps(), 10000);
        assertEq(gov.repWeightBps(), 0);
    }

    function test_SetParamsAllReputation() public {
        gov.setParams(0, 10000, 10000);
        assertEq(gov.tokenWeightBps(), 0);
        assertEq(gov.repWeightBps(), 10000);
    }

    // ─── voteWeight ──────────────────────────────────────────

    function test_VoteWeightDefaultParams() public {
        // tokenWeightBps=8000, repWeightBps=2000, repCapBps=5000
        // voter1 has 1000 tokens, 500 rep
        token.setBalance(voter1, 1000);
        oracle.setReputation(voter1, 500);

        // tokenPart = 1000 * 8000 / 10000 = 800
        // repPartRaw = 500 * 2000 / 10000 = 100
        // repCap = 800 * 5000 / 10000 = 400
        // repPart = min(100, 400) = 100
        // total = 800 + 100 = 900
        assertEq(gov.voteWeight(voter1), 900);
    }

    function test_VoteWeightRepCapped() public {
        // Large reputation that exceeds cap
        token.setBalance(voter1, 1000);
        oracle.setReputation(voter1, 100_000);

        // tokenPart = 1000 * 8000 / 10000 = 800
        // repPartRaw = 100000 * 2000 / 10000 = 20000
        // repCap = 800 * 5000 / 10000 = 400
        // repPart = min(20000, 400) = 400 (capped)
        // total = 800 + 400 = 1200
        assertEq(gov.voteWeight(voter1), 1200);
    }

    function test_VoteWeightZeroTokens() public {
        token.setBalance(voter1, 0);
        oracle.setReputation(voter1, 500);

        // tokenPart = 0
        // repPartRaw = 500 * 2000 / 10000 = 100
        // repCap = 0 * 5000 / 10000 = 0
        // repPart = min(100, 0) = 0 (capped at 0 since no tokens)
        // total = 0
        assertEq(gov.voteWeight(voter1), 0);
    }

    function test_VoteWeightZeroReputation() public {
        token.setBalance(voter1, 1000);
        oracle.setReputation(voter1, 0);

        // tokenPart = 800, repPart = 0, total = 800
        assertEq(gov.voteWeight(voter1), 800);
    }

    function test_VoteWeightZeroBoth() public view {
        assertEq(gov.voteWeight(voter1), 0);
    }

    function test_VoteWeightNoOracle() public {
        gov.setOracle(address(0));
        token.setBalance(voter1, 1000);

        // reputation = 0 when oracle is address(0)
        // tokenPart = 800, repPart = 0, total = 800
        assertEq(gov.voteWeight(voter1), 800);
    }

    function test_VoteWeightCustomParams5050() public {
        gov.setParams(5000, 5000, 10000);
        token.setBalance(voter1, 1000);
        oracle.setReputation(voter1, 1000);

        // tokenPart = 1000 * 5000 / 10000 = 500
        // repPartRaw = 1000 * 5000 / 10000 = 500
        // repCap = 500 * 10000 / 10000 = 500
        // repPart = min(500, 500) = 500
        // total = 500 + 500 = 1000
        assertEq(gov.voteWeight(voter1), 1000);
    }

    function test_VoteWeightAllTokenWeight() public {
        gov.setParams(10000, 0, 0);
        token.setBalance(voter1, 1000);
        oracle.setReputation(voter1, 999);

        // tokenPart = 1000 * 10000 / 10000 = 1000
        // repPartRaw = 999 * 0 / 10000 = 0
        // total = 1000
        assertEq(gov.voteWeight(voter1), 1000);
    }

    function test_VoteWeightLargeValues() public {
        token.setBalance(voter1, 1_000_000 ether);
        oracle.setReputation(voter1, 500_000 ether);

        // tokenPart = 1_000_000e18 * 8000 / 10000 = 800_000e18
        // repPartRaw = 500_000e18 * 2000 / 10000 = 100_000e18
        // repCap = 800_000e18 * 5000 / 10000 = 400_000e18
        // repPart = min(100_000e18, 400_000e18) = 100_000e18
        // total = 900_000e18
        assertEq(gov.voteWeight(voter1), 900_000 ether);
    }

    function test_VoteWeightMultipleVoters() public {
        token.setBalance(voter1, 1000);
        oracle.setReputation(voter1, 200);

        token.setBalance(voter2, 5000);
        oracle.setReputation(voter2, 3000);

        // voter1: tokenPart=800, repRaw=40, repCap=400, repPart=40 => 840
        assertEq(gov.voteWeight(voter1), 840);

        // voter2: tokenPart=4000, repRaw=600, repCap=2000, repPart=600 => 4600
        assertEq(gov.voteWeight(voter2), 4600);
    }

    function test_VoteWeightRepPartExactlyCap() public {
        // Set so repPartRaw == repCap exactly
        token.setBalance(voter1, 1000);
        // tokenPart = 800
        // repCap = 800 * 5000 / 10000 = 400
        // repPartRaw = r * 2000 / 10000 = r/5
        // we need r/5 = 400 => r = 2000
        oracle.setReputation(voter1, 2000);

        // repPartRaw = 2000 * 2000 / 10000 = 400
        // repCap = 400
        // repPart = 400, total = 800 + 400 = 1200
        assertEq(gov.voteWeight(voter1), 1200);
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
        gov.setOracle(address(0x99));
    }
}
