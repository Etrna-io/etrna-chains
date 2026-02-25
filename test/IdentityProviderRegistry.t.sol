// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/identity/IdentityProviderRegistry.sol";

contract IdentityProviderRegistryTest is Test {
    IdentityProviderRegistry public registry;

    address admin = address(0xA);
    address nonAdmin = address(0xB);
    address verifier1 = address(0xC);
    address verifier2 = address(0xD);
    address verifier3 = address(0xE);

    bytes32 constant NAME_PRIVADO = keccak256("PRIVADO");
    bytes32 constant NAME_BILLIONS = keccak256("BILLIONS");
    bytes32 constant NAME_ZKLOGIN = keccak256("ZKLOGIN");
    bytes32 constant NAME_EUDI = keccak256("EUDI");

    function setUp() public {
        vm.prank(admin);
        registry = new IdentityProviderRegistry(admin);
    }

    // ─── Constructor ─────────────────────────────────────────

    function test_ConstructorGrantsDefaultAdminRole() public view {
        assertTrue(registry.hasRole(registry.DEFAULT_ADMIN_ROLE(), admin));
    }

    function test_ConstructorGrantsAdminRole() public view {
        assertTrue(registry.hasRole(registry.ADMIN_ROLE(), admin));
    }

    function test_AdminRoleConstant() public view {
        assertEq(registry.ADMIN_ROLE(), keccak256("ADMIN_ROLE"));
    }

    // ─── setVerifier ─────────────────────────────────────────

    function test_SetVerifier() public {
        vm.prank(admin);
        registry.setVerifier(NAME_PRIVADO, verifier1);

        assertEq(registry.verifiers(NAME_PRIVADO), verifier1);
    }

    function test_SetVerifierEmitsEvent() public {
        vm.expectEmit(true, true, false, true);
        emit IdentityProviderRegistry.VerifierSet(NAME_PRIVADO, verifier1);

        vm.prank(admin);
        registry.setVerifier(NAME_PRIVADO, verifier1);
    }

    function test_SetVerifierMultipleProviders() public {
        vm.startPrank(admin);
        registry.setVerifier(NAME_PRIVADO, verifier1);
        registry.setVerifier(NAME_BILLIONS, verifier2);
        registry.setVerifier(NAME_ZKLOGIN, verifier3);
        vm.stopPrank();

        assertEq(registry.verifiers(NAME_PRIVADO), verifier1);
        assertEq(registry.verifiers(NAME_BILLIONS), verifier2);
        assertEq(registry.verifiers(NAME_ZKLOGIN), verifier3);
    }

    function test_SetVerifierOverwrite() public {
        vm.startPrank(admin);
        registry.setVerifier(NAME_PRIVADO, verifier1);
        assertEq(registry.verifiers(NAME_PRIVADO), verifier1);

        registry.setVerifier(NAME_PRIVADO, verifier2);
        assertEq(registry.verifiers(NAME_PRIVADO), verifier2);
        vm.stopPrank();
    }

    function test_SetVerifierToZeroAddress() public {
        vm.startPrank(admin);
        registry.setVerifier(NAME_PRIVADO, verifier1);
        registry.setVerifier(NAME_PRIVADO, address(0));
        vm.stopPrank();

        assertEq(registry.verifiers(NAME_PRIVADO), address(0));
    }

    // ─── Access Control ──────────────────────────────────────

    function test_SetVerifierRevertNonAdmin() public {
        vm.prank(nonAdmin);
        vm.expectRevert();
        registry.setVerifier(NAME_PRIVADO, verifier1);
    }

    function test_GrantAdminRoleAllowsSetVerifier() public {
        vm.prank(admin);
        registry.grantRole(registry.ADMIN_ROLE(), nonAdmin);

        vm.prank(nonAdmin);
        registry.setVerifier(NAME_PRIVADO, verifier1);

        assertEq(registry.verifiers(NAME_PRIVADO), verifier1);
    }

    function test_RevokeAdminRolePreventsSetVerifier() public {
        vm.startPrank(admin);
        registry.grantRole(registry.ADMIN_ROLE(), nonAdmin);
        registry.revokeRole(registry.ADMIN_ROLE(), nonAdmin);
        vm.stopPrank();

        vm.prank(nonAdmin);
        vm.expectRevert();
        registry.setVerifier(NAME_PRIVADO, verifier1);
    }

    function test_DefaultAdminCanGrantAdminRole() public {
        vm.prank(admin);
        registry.grantRole(registry.ADMIN_ROLE(), nonAdmin);
        assertTrue(registry.hasRole(registry.ADMIN_ROLE(), nonAdmin));
    }

    function test_NonDefaultAdminCannotGrantAdminRole() public {
        // Give ADMIN_ROLE but not DEFAULT_ADMIN_ROLE
        vm.prank(admin);
        registry.grantRole(registry.ADMIN_ROLE(), nonAdmin);

        // nonAdmin has ADMIN_ROLE but can't grant to others
        // (DEFAULT_ADMIN_ROLE is admin of ADMIN_ROLE by default)
        address other = address(0xF1);
        vm.prank(nonAdmin);
        vm.expectRevert();
        registry.grantRole(registry.ADMIN_ROLE(), other);
    }

    // ─── Verifier getter (default values) ────────────────────

    function test_VerifierReturnsZeroForUnsetName() public view {
        assertEq(registry.verifiers(NAME_EUDI), address(0));
        assertEq(registry.verifiers(bytes32(0)), address(0));
        assertEq(registry.verifiers(keccak256("NONEXISTENT")), address(0));
    }

    // ─── supportsInterface ───────────────────────────────────

    function test_SupportsAccessControl() public view {
        // IAccessControl interfaceId = 0x7965db0b
        assertTrue(registry.supportsInterface(0x7965db0b));
    }

    function test_SupportsERC165() public view {
        assertTrue(registry.supportsInterface(0x01ffc9a7));
    }

    function test_DoesNotSupportRandomInterface() public view {
        assertFalse(registry.supportsInterface(0xdeadbeef));
    }

    // ─── Edge cases ──────────────────────────────────────────

    function test_SetVerifierEmitsEventOnOverwrite() public {
        vm.startPrank(admin);
        registry.setVerifier(NAME_PRIVADO, verifier1);

        vm.expectEmit(true, true, false, true);
        emit IdentityProviderRegistry.VerifierSet(NAME_PRIVADO, verifier2);
        registry.setVerifier(NAME_PRIVADO, verifier2);
        vm.stopPrank();
    }

    function test_MultipleNamesIndependent() public {
        vm.startPrank(admin);
        registry.setVerifier(NAME_PRIVADO, verifier1);
        registry.setVerifier(NAME_BILLIONS, verifier2);

        // Overwrite one doesn't affect the other
        registry.setVerifier(NAME_PRIVADO, verifier3);
        vm.stopPrank();

        assertEq(registry.verifiers(NAME_PRIVADO), verifier3);
        assertEq(registry.verifiers(NAME_BILLIONS), verifier2);
    }
}
