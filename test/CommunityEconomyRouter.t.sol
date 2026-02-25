// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/CommunityEconomyRouter.sol";

contract MockRewardDistributor is IRewardDistributor {
    uint256 public totalDistributed;
    mapping(address => uint256) public rewards;

    function distributeReward(address to, uint256 amount) external override {
        rewards[to] += amount;
        totalDistributed += amount;
    }
}

contract CommunityEconomyRouterTest is Test {
    CommunityEconomyRouter public router;
    MockRewardDistributor public distributor;

    address admin = address(1);
    address operator = address(2);

    function setUp() public {
        distributor = new MockRewardDistributor();
        vm.startPrank(admin);
        router = new CommunityEconomyRouter(admin, address(distributor));
        router.grantRole(router.DISTRIBUTOR_ROLE(), operator);
        vm.stopPrank();
    }

    // ─── Batch distribution ──────────────────────────────────

    function test_DistributeBatch() public {
        address[] memory residents = new address[](3);
        residents[0] = address(10);
        residents[1] = address(11);
        residents[2] = address(12);

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 100 ether;
        amounts[1] = 200 ether;
        amounts[2] = 50 ether;

        vm.prank(operator);
        router.distributeCityRewards(1, 1, residents, amounts);

        assertEq(distributor.rewards(address(10)), 100 ether);
        assertEq(distributor.rewards(address(11)), 200 ether);
        assertEq(distributor.rewards(address(12)), 50 ether);
        assertEq(distributor.totalDistributed(), 350 ether);
    }

    function test_SkipZeroAddress() public {
        address[] memory residents = new address[](2);
        residents[0] = address(0);
        residents[1] = address(10);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 100 ether;
        amounts[1] = 50 ether;

        vm.prank(operator);
        router.distributeCityRewards(1, 1, residents, amounts);

        assertEq(distributor.totalDistributed(), 50 ether);
    }

    function test_SkipZeroAmount() public {
        address[] memory residents = new address[](2);
        residents[0] = address(10);
        residents[1] = address(11);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 0;
        amounts[1] = 100 ether;

        vm.prank(operator);
        router.distributeCityRewards(1, 1, residents, amounts);

        assertEq(distributor.totalDistributed(), 100 ether);
    }

    // ─── Access control ──────────────────────────────────────

    function test_RevertUnauthorized() public {
        address[] memory residents = new address[](1);
        residents[0] = address(10);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100;

        vm.prank(address(99));
        vm.expectRevert();
        router.distributeCityRewards(1, 1, residents, amounts);
    }

    // ─── Batch size limit ────────────────────────────────────

    function test_RevertBatchTooLarge() public {
        address[] memory residents = new address[](201);
        uint256[] memory amounts = new uint256[](201);
        for (uint256 i; i < 201; i++) {
            residents[i] = address(uint160(100 + i));
            amounts[i] = 1 ether;
        }

        vm.prank(operator);
        vm.expectRevert("CommunityEconomyRouter: batch too large");
        router.distributeCityRewards(1, 1, residents, amounts);
    }

    // ─── Length mismatch ─────────────────────────────────────

    function test_RevertLengthMismatch() public {
        address[] memory residents = new address[](2);
        uint256[] memory amounts = new uint256[](1);

        vm.prank(operator);
        vm.expectRevert("CommunityEconomyRouter: length mismatch");
        router.distributeCityRewards(1, 1, residents, amounts);
    }

    // ─── Edge: empty batch ───────────────────────────────────

    function test_EmptyBatch() public {
        address[] memory residents = new address[](0);
        uint256[] memory amounts = new uint256[](0);

        vm.prank(operator);
        router.distributeCityRewards(1, 1, residents, amounts);
        assertEq(distributor.totalDistributed(), 0);
    }
}
