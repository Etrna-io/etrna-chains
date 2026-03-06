// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

/**
 * @title EtrnaTestBase
 * @notice Shared test utilities and constants for all ETRNA contract tests.
 *         Provides common setup for deployers, users, and helper assertions.
 */
abstract contract EtrnaTestBase is Test {
    // Standard test accounts
    address internal deployer = makeAddr("deployer");
    address internal admin = makeAddr("admin");
    address internal user1 = makeAddr("user1");
    address internal user2 = makeAddr("user2");
    address internal user3 = makeAddr("user3");
    address internal treasury = makeAddr("treasury");

    // Token supply invariants — NEVER change these
    uint256 internal constant ETR_MAX_SUPPLY = 1_000_000_000 ether;  // 1B $ETR
    uint256 internal constant VIBE_MAX_SUPPLY = 100_000_000_000 ether; // 100B $VIBE

    // Common labels for trace readability
    function setUp() public virtual {
        vm.label(deployer, "Deployer");
        vm.label(admin, "Admin");
        vm.label(user1, "User1");
        vm.label(user2, "User2");
        vm.label(user3, "User3");
        vm.label(treasury, "Treasury");

        vm.deal(deployer, 100 ether);
        vm.deal(user1, 10 ether);
        vm.deal(user2, 10 ether);
        vm.deal(user3, 10 ether);
    }

    /// @dev Assert that a value is within a percentage tolerance of expected
    function assertApproxEq(uint256 actual, uint256 expected, uint256 toleranceBps) internal pure {
        uint256 delta = expected * toleranceBps / 10_000;
        require(
            actual >= expected - delta && actual <= expected + delta,
            "Value not within tolerance"
        );
    }

    /// @dev Fast-forward block.timestamp
    function skipTime(uint256 seconds_) internal {
        vm.warp(block.timestamp + seconds_);
    }

    /// @dev Fast-forward block.number
    function skipBlocks(uint256 blocks) internal {
        vm.roll(block.number + blocks);
    }
}
