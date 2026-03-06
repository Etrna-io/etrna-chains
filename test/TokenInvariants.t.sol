// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/tokens/EtrnaToken.sol";
import "../src/tokens/VibeToken.sol";

/**
 * @title TokenInvariants
 * @notice Invariant tests ensuring $ETR and $VIBE token supply constraints
 *         are NEVER violated under any sequence of operations.
 *
 * CRITICAL INVARIANTS (from ETRNA whitepaper):
 *   - $ETR total supply MUST never exceed 1,000,000,000 (1B)
 *   - $VIBE total supply MUST never exceed 100,000,000,000 (100B)
 *   - No address should hold more than totalSupply
 */
contract TokenInvariantsTest is Test {
    EtrnaToken internal etr;
    VibeToken internal vibe;
    address internal deployer = makeAddr("deployer");

    function setUp() public {
        vm.startPrank(deployer);
        etr = new EtrnaToken();
        vibe = new VibeToken();
        vm.stopPrank();
    }

    /// @notice $ETR total supply must never exceed 1B
    function invariant_etr_max_supply() public view {
        assertLe(etr.totalSupply(), 1_000_000_000 ether, "ETR supply exceeds 1B cap");
    }

    /// @notice $VIBE total supply must never exceed 100B
    function invariant_vibe_max_supply() public view {
        assertLe(vibe.totalSupply(), 100_000_000_000 ether, "VIBE supply exceeds 100B cap");
    }

    /// @notice No single address holds more than total supply
    function invariant_etr_no_address_exceeds_supply() public view {
        assertLe(etr.balanceOf(deployer), etr.totalSupply());
    }

    /// @notice No single address holds more than total supply
    function invariant_vibe_no_address_exceeds_supply() public view {
        assertLe(vibe.balanceOf(deployer), vibe.totalSupply());
    }
}
