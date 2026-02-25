// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import {RealityLedger} from "../src/civilization/RealityLedger.sol";
import {MockETR} from "./Mocks.sol";

contract RealityLedgerTest is Test {
    MockETR etr;
    RealityLedger ledger;

    address admin = address(0xA11CE);
    address alice = address(0xB0B);
    address bob = address(0xC0C0);

    function setUp() public {
        etr = new MockETR();
        ledger = new RealityLedger(admin, address(etr), 1 ether);

        etr.mint(alice, 10 ether);
        etr.mint(bob, 10 ether);

        vm.prank(alice);
        etr.approve(address(ledger), type(uint256).max);

        vm.prank(bob);
        etr.approve(address(ledger), type(uint256).max);
    }

    function test_submitChallengeResolveTrue() public {
        bytes32 topic = keccak256("CITY:TORONTO");
        bytes32 schema = keccak256("WEATHER-OBS");
        bytes32 contentHash = keccak256("payload");

        vm.prank(alice);
        uint256 aid = ledger.submitAssertion(topic, schema, contentHash, 1 ether);

        vm.prank(bob);
        ledger.challengeAssertion(aid, 1 ether);

        vm.prank(admin);
        ledger.resolveAssertion(aid, true);

        // Alice should receive both stakes (2 ether)
        assertEq(etr.balanceOf(alice), 11 ether);
        assertEq(etr.balanceOf(bob), 9 ether);
    }
}
