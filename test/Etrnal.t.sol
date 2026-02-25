// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/identity/Etrnal.sol";

contract EtrnalTest is Test {
    Etrnal public etrnal;
    address admin = address(1);
    address minter = address(2);
    address user1 = address(3);
    address user2 = address(4);

    bytes32 constant META_HASH = keccak256("metadata-1");
    bytes32 constant META_HASH_2 = keccak256("metadata-2");

    function setUp() public {
        vm.prank(admin);
        etrnal = new Etrnal("Etrnal", "ETRNAL", "https://api.etrna.io/etrnal/", admin);

        vm.startPrank(admin);
        etrnal.grantRole(etrnal.MINTER_ROLE(), minter);
        vm.stopPrank();
    }

    // ─── Minting ─────────────────────────────────────────────

    function test_Mint() public {
        vm.prank(minter);
        uint256 id = etrnal.mint(user1, META_HASH);

        assertEq(id, 1);
        assertEq(etrnal.ownerOf(1), user1);
        assertEq(etrnal.etrnalOf(user1), 1);
        assertEq(etrnal.getMetadataHash(1), META_HASH);
    }

    function test_MintMultipleUsers() public {
        vm.startPrank(minter);
        uint256 id1 = etrnal.mint(user1, META_HASH);
        uint256 id2 = etrnal.mint(user2, META_HASH_2);
        vm.stopPrank();

        assertEq(id1, 1);
        assertEq(id2, 2);
        assertEq(etrnal.ownerOf(1), user1);
        assertEq(etrnal.ownerOf(2), user2);
    }

    function test_RevertDuplicateMint() public {
        vm.startPrank(minter);
        etrnal.mint(user1, META_HASH);
        vm.expectRevert("Etrnal: already has etrnal");
        etrnal.mint(user1, META_HASH_2);
        vm.stopPrank();
    }

    function test_RevertMintToZero() public {
        vm.prank(minter);
        vm.expectRevert("Etrnal: to is zero");
        etrnal.mint(address(0), META_HASH);
    }

    function test_RevertMintUnauthorized() public {
        vm.prank(user1);
        vm.expectRevert();
        etrnal.mint(user1, META_HASH);
    }

    // ─── Soulbound ───────────────────────────────────────────

    function test_RevertTransfer() public {
        vm.prank(minter);
        etrnal.mint(user1, META_HASH);

        vm.prank(user1);
        vm.expectRevert("Etrnal: soulbound");
        etrnal.transferFrom(user1, user2, 1);
    }

    function test_RevertSafeTransfer() public {
        vm.prank(minter);
        etrnal.mint(user1, META_HASH);

        vm.prank(user1);
        vm.expectRevert("Etrnal: soulbound");
        etrnal.safeTransferFrom(user1, user2, 1);
    }

    // ─── Suspension ──────────────────────────────────────────

    function test_Suspend() public {
        vm.prank(minter);
        etrnal.mint(user1, META_HASH);

        assertFalse(etrnal.isSuspended(1));

        vm.prank(admin);
        etrnal.setSuspended(1, true, "violation");

        assertTrue(etrnal.isSuspended(1));
    }

    function test_Unsuspend() public {
        vm.prank(minter);
        etrnal.mint(user1, META_HASH);

        vm.startPrank(admin);
        etrnal.setSuspended(1, true, "violation");
        etrnal.setSuspended(1, false, "cleared");
        vm.stopPrank();

        assertFalse(etrnal.isSuspended(1));
    }

    function test_RevertSuspendUnauthorized() public {
        vm.prank(minter);
        etrnal.mint(user1, META_HASH);

        vm.prank(user1);
        vm.expectRevert();
        etrnal.setSuspended(1, true, "violation");
    }

    function test_RevertSuspendNonexistent() public {
        vm.prank(admin);
        vm.expectRevert("Etrnal: nonexistent token");
        etrnal.setSuspended(999, true, "violation");
    }

    // ─── Metadata ────────────────────────────────────────────

    function test_TokenURI() public {
        vm.prank(minter);
        etrnal.mint(user1, META_HASH);

        string memory uri = etrnal.tokenURI(1);
        assertEq(uri, "https://api.etrna.io/etrnal/1");
    }

    function test_UpdateMetadata() public {
        vm.prank(minter);
        etrnal.mint(user1, META_HASH);

        vm.prank(admin);
        etrnal.updateMetadata(1, META_HASH_2);

        assertEq(etrnal.getMetadataHash(1), META_HASH_2);
    }
}
