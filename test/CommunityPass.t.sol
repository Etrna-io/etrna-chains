// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/CommunityPass.sol";

contract CommunityPassTest is Test {
    CommunityPass public pass;
    address admin = address(1);
    address registrar = address(2);
    address cityAdmin = address(3);
    address resident1 = address(4);
    address resident2 = address(5);

    function setUp() public {
        vm.prank(admin);
        pass = new CommunityPass("ETRNA Community Pass", "ECP", "https://api.etrna.io/pass/", admin);

        vm.startPrank(admin);
        pass.grantCityAdmin(cityAdmin);
        pass.grantRegistrar(registrar);
        vm.stopPrank();
    }

    // ─── Minting ─────────────────────────────────────────────

    function test_IssuePass() public {
        vm.prank(registrar);
        uint256 tokenId = pass.issuePass(resident1, 1);

        assertEq(tokenId, 1);
        assertEq(pass.ownerOf(1), resident1);
        assertEq(pass.cityPassOf(1, resident1), 1);
        assertTrue(pass.isActive(1));

        CommunityPass.PassData memory data = pass.getPassData(1);
        assertEq(data.cityId, 1);
        assertTrue(data.active);
    }

    function test_RevertDuplicatePass() public {
        vm.startPrank(registrar);
        pass.issuePass(resident1, 1);
        vm.expectRevert("CommunityPass: pass exists");
        pass.issuePass(resident1, 1);
        vm.stopPrank();
    }

    function test_MultipleCities() public {
        vm.startPrank(registrar);
        uint256 id1 = pass.issuePass(resident1, 1);
        uint256 id2 = pass.issuePass(resident1, 2);
        vm.stopPrank();

        assertEq(id1, 1);
        assertEq(id2, 2);
        assertEq(pass.cityPassOf(1, resident1), 1);
        assertEq(pass.cityPassOf(2, resident1), 2);
    }

    // ─── Soulbound ───────────────────────────────────────────

    function test_RevertTransfer() public {
        vm.prank(registrar);
        pass.issuePass(resident1, 1);

        vm.prank(resident1);
        vm.expectRevert("CommunityPass: soulbound");
        pass.transferFrom(resident1, resident2, 1);
    }

    // ─── Revocation ──────────────────────────────────────────

    function test_RevokePass() public {
        vm.prank(registrar);
        pass.issuePass(resident1, 1);

        vm.prank(cityAdmin);
        pass.revokePass(1);

        assertEq(pass.cityPassOf(1, resident1), 0);
    }

    function test_RevertRevokeInactive() public {
        vm.prank(registrar);
        pass.issuePass(resident1, 1);

        vm.prank(cityAdmin);
        pass.revokePass(1);

        vm.prank(cityAdmin);
        vm.expectRevert(); // token burned
        pass.revokePass(1);
    }

    // ─── Access control ──────────────────────────────────────

    function test_OnlyRegistrarCanIssue() public {
        vm.prank(resident1);
        vm.expectRevert();
        pass.issuePass(resident2, 1);
    }

    function test_OnlyAdminCanSetBaseURI() public {
        vm.prank(resident1);
        vm.expectRevert();
        pass.setBaseURI("https://evil.com/");
    }

    function test_SetBaseURI() public {
        vm.prank(admin);
        pass.setBaseURI("https://new.etrna.io/pass/");
        // Should not revert
    }

    // ─── Interface support ───────────────────────────────────

    function test_SupportsERC721() public view {
        assertTrue(pass.supportsInterface(0x80ac58cd)); // ERC721
    }

    function test_SupportsAccessControl() public view {
        assertTrue(pass.supportsInterface(0x7965db0b)); // AccessControl
    }

    function test_SupportsERC721Enumerable() public view {
        assertTrue(pass.supportsInterface(0x780e9d63)); // ERC721Enumerable
    }

    // ─── Edge cases ──────────────────────────────────────────

    function test_RevertZeroAddress() public {
        vm.prank(registrar);
        vm.expectRevert("CommunityPass: to is zero");
        pass.issuePass(address(0), 1);
    }

    function test_RevertZeroCityId() public {
        vm.prank(registrar);
        vm.expectRevert("CommunityPass: invalid cityId");
        pass.issuePass(resident1, 0);
    }
}
