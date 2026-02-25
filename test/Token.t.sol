// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {EtrnaToken} from "../src/tokens/EtrnaToken.sol";
import {VibeToken} from "../src/tokens/VibeToken.sol";
import {TokenErrors} from "../src/tokens/TokenErrors.sol";

contract TokenTests is Test {
    function testEtrCapEnforced() public {
        address admin = address(0xA11CE);
        address[] memory r = new address[](1);
        uint256[] memory a = new uint256[](1);
        r[0] = address(this);
        a[0] = 1_000_000_000 ether + 1; // MAX_SUPPLY + 1

        vm.expectRevert(TokenErrors.ExceedsMaxSupply.selector);
        new EtrnaToken("Etrna", "ETR", admin, r, a);
    }

    function testVibeMinterRequired() public {
        address admin = address(0xA11CE);
        VibeToken vibe = new VibeToken("Vibe", "VIBE", admin);
        vm.expectRevert();
        vibe.mint(address(this), 1e18);
    }

    function testVibeCapEnforced() public {
        address admin = address(0xA11CE);
        VibeToken vibe = new VibeToken("Vibe", "VIBE", admin);
        vm.prank(admin);
        vibe.setMinter(address(this), true);

        vibe.mint(address(this), 100_000_000_000 ether); // MAX_SUPPLY
        vm.expectRevert(TokenErrors.ExceedsMaxSupply.selector);
        vibe.mint(address(this), 1);
    }
}
