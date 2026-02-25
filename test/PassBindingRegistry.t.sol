// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/identity/PassBindingRegistry.sol";
import "../src/identity/Etrnal.sol";
import "../src/CommunityPass.sol";

contract PassBindingRegistryTest is Test {
    PassBindingRegistry public registry;
    Etrnal public etrnal;
    CommunityPass public communityPass;

    address admin = address(1);
    address binder = address(2);
    address user1 = address(3);

    uint256 etrnalId;
    uint256 passTokenId;

    function setUp() public {
        vm.startPrank(admin);

        // Deploy Etrnal
        etrnal = new Etrnal("Etrnal", "ETRNAL", "https://api.etrna.io/etrnal/", admin);

        // Deploy CommunityPass
        communityPass = new CommunityPass("Community Pass", "CP", "https://api.etrna.io/cp/", admin);

        // Deploy PassBindingRegistry
        registry = new PassBindingRegistry(admin, address(etrnal));
        registry.grantRole(registry.BINDER_ROLE(), binder);

        // Mint an Etrnal to user1
        etrnalId = etrnal.mint(user1, keccak256("meta"));

        // Issue a CommunityPass to user1
        communityPass.grantRegistrar(admin);
        passTokenId = communityPass.issuePass(user1, 1);

        vm.stopPrank();
    }

    // ─── Bind ────────────────────────────────────────────────

    function test_Bind() public {
        vm.prank(binder);
        registry.bind(
            IPassBindingRegistry.PassType.CommunityPass,
            address(communityPass),
            passTokenId,
            etrnalId
        );

        assertTrue(
            registry.isBound(
                IPassBindingRegistry.PassType.CommunityPass,
                address(communityPass),
                passTokenId
            )
        );

        IPassBindingRegistry.Binding memory b = registry.getBinding(
            IPassBindingRegistry.PassType.CommunityPass,
            address(communityPass),
            passTokenId
        );
        assertEq(b.etrnalId, etrnalId);
        assertTrue(b.active);
        assertEq(uint8(b.passType), uint8(IPassBindingRegistry.PassType.CommunityPass));
        assertEq(b.passContract, address(communityPass));
        assertEq(b.tokenId, passTokenId);
    }

    function test_RevertBindAlreadyBound() public {
        vm.startPrank(binder);
        registry.bind(
            IPassBindingRegistry.PassType.CommunityPass,
            address(communityPass),
            passTokenId,
            etrnalId
        );

        vm.expectRevert("PassBindingRegistry: already bound");
        registry.bind(
            IPassBindingRegistry.PassType.CommunityPass,
            address(communityPass),
            passTokenId,
            etrnalId
        );
        vm.stopPrank();
    }

    function test_RevertBindUnauthorized() public {
        vm.prank(user1);
        vm.expectRevert();
        registry.bind(
            IPassBindingRegistry.PassType.CommunityPass,
            address(communityPass),
            passTokenId,
            etrnalId
        );
    }

    function test_RevertBindNonexistentEtrnal() public {
        vm.prank(binder);
        vm.expectRevert(); // ownerOf on nonexistent etrnalId reverts
        registry.bind(
            IPassBindingRegistry.PassType.CommunityPass,
            address(communityPass),
            passTokenId,
            999
        );
    }

    // ─── Unbind ──────────────────────────────────────────────

    function test_Unbind() public {
        vm.startPrank(binder);
        registry.bind(
            IPassBindingRegistry.PassType.CommunityPass,
            address(communityPass),
            passTokenId,
            etrnalId
        );

        registry.unbind(
            IPassBindingRegistry.PassType.CommunityPass,
            address(communityPass),
            passTokenId
        );
        vm.stopPrank();

        assertFalse(
            registry.isBound(
                IPassBindingRegistry.PassType.CommunityPass,
                address(communityPass),
                passTokenId
            )
        );
    }

    function test_RevertUnbindNotBound() public {
        vm.prank(binder);
        vm.expectRevert("PassBindingRegistry: not bound");
        registry.unbind(
            IPassBindingRegistry.PassType.CommunityPass,
            address(communityPass),
            passTokenId
        );
    }

    function test_RevertUnbindUnauthorized() public {
        vm.startPrank(binder);
        registry.bind(
            IPassBindingRegistry.PassType.CommunityPass,
            address(communityPass),
            passTokenId,
            etrnalId
        );
        vm.stopPrank();

        vm.prank(user1);
        vm.expectRevert();
        registry.unbind(
            IPassBindingRegistry.PassType.CommunityPass,
            address(communityPass),
            passTokenId
        );
    }

    // ─── GetBinding / IsBound ────────────────────────────────

    function test_GetBindingUnbound() public view {
        IPassBindingRegistry.Binding memory b = registry.getBinding(
            IPassBindingRegistry.PassType.CommunityPass,
            address(communityPass),
            passTokenId
        );
        assertFalse(b.active);
        assertEq(b.etrnalId, 0);
    }

    function test_IsBoundFalseByDefault() public view {
        assertFalse(
            registry.isBound(
                IPassBindingRegistry.PassType.CommunityPass,
                address(communityPass),
                passTokenId
            )
        );
    }
}
