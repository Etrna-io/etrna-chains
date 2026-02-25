// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/identity/IssuerRegistry.sol";

contract IssuerRegistryTest is Test {
    IssuerRegistry public registry;
    address admin = address(1);
    address user1 = address(2);
    address issuerAdmin = address(3);

    bytes32 constant ISSUER_ID = keccak256("city-nyc");
    bytes32 constant ISSUER_ID_2 = keccak256("org-etrna");
    bytes32 constant META_HASH = keccak256("ipfs://metadata");
    bytes32 constant META_HASH_2 = keccak256("ipfs://metadata-v2");

    function setUp() public {
        vm.prank(admin);
        registry = new IssuerRegistry(admin);
    }

    // ─── Register ────────────────────────────────────────────

    function test_RegisterIssuer() public {
        vm.prank(admin);
        registry.registerIssuer(
            ISSUER_ID,
            IIssuerRegistry.IssuerType.City,
            issuerAdmin,
            10_000,
            META_HASH
        );

        assertTrue(registry.isActive(ISSUER_ID));

        IIssuerRegistry.Issuer memory issuer = registry.getIssuer(ISSUER_ID);
        assertEq(uint8(issuer.issuerType), uint8(IIssuerRegistry.IssuerType.City));
        assertEq(issuer.admin, issuerAdmin);
        assertTrue(issuer.active);
        assertEq(issuer.maxSupply, 10_000);
        assertEq(issuer.metadataHash, META_HASH);
    }

    function test_RegisterMultipleIssuers() public {
        vm.startPrank(admin);
        registry.registerIssuer(ISSUER_ID, IIssuerRegistry.IssuerType.City, issuerAdmin, 10_000, META_HASH);
        registry.registerIssuer(ISSUER_ID_2, IIssuerRegistry.IssuerType.Organization, issuerAdmin, 5_000, META_HASH_2);
        vm.stopPrank();

        assertTrue(registry.isActive(ISSUER_ID));
        assertTrue(registry.isActive(ISSUER_ID_2));
    }

    function test_RevertRegisterDuplicate() public {
        vm.startPrank(admin);
        registry.registerIssuer(ISSUER_ID, IIssuerRegistry.IssuerType.City, issuerAdmin, 10_000, META_HASH);

        vm.expectRevert("IssuerRegistry: already registered");
        registry.registerIssuer(ISSUER_ID, IIssuerRegistry.IssuerType.City, issuerAdmin, 10_000, META_HASH);
        vm.stopPrank();
    }

    function test_RevertRegisterEmptyId() public {
        vm.prank(admin);
        vm.expectRevert("IssuerRegistry: empty issuerId");
        registry.registerIssuer(bytes32(0), IIssuerRegistry.IssuerType.City, issuerAdmin, 10_000, META_HASH);
    }

    function test_RevertRegisterZeroAdmin() public {
        vm.prank(admin);
        vm.expectRevert("IssuerRegistry: admin is zero");
        registry.registerIssuer(ISSUER_ID, IIssuerRegistry.IssuerType.City, address(0), 10_000, META_HASH);
    }

    function test_RevertRegisterUnauthorized() public {
        vm.prank(user1);
        vm.expectRevert();
        registry.registerIssuer(ISSUER_ID, IIssuerRegistry.IssuerType.City, issuerAdmin, 10_000, META_HASH);
    }

    // ─── Update ──────────────────────────────────────────────

    function test_UpdateIssuer() public {
        vm.startPrank(admin);
        registry.registerIssuer(ISSUER_ID, IIssuerRegistry.IssuerType.City, issuerAdmin, 10_000, META_HASH);

        registry.updateIssuer(ISSUER_ID, true, 20_000, META_HASH_2);
        vm.stopPrank();

        IIssuerRegistry.Issuer memory issuer = registry.getIssuer(ISSUER_ID);
        assertEq(issuer.maxSupply, 20_000);
        assertEq(issuer.metadataHash, META_HASH_2);
        assertTrue(issuer.active);
    }

    function test_DeactivateIssuer() public {
        vm.startPrank(admin);
        registry.registerIssuer(ISSUER_ID, IIssuerRegistry.IssuerType.City, issuerAdmin, 10_000, META_HASH);

        registry.updateIssuer(ISSUER_ID, false, 10_000, META_HASH);
        vm.stopPrank();

        assertFalse(registry.isActive(ISSUER_ID));
    }

    function test_ReactivateIssuer() public {
        vm.startPrank(admin);
        registry.registerIssuer(ISSUER_ID, IIssuerRegistry.IssuerType.City, issuerAdmin, 10_000, META_HASH);
        registry.updateIssuer(ISSUER_ID, false, 10_000, META_HASH);
        assertFalse(registry.isActive(ISSUER_ID));

        registry.updateIssuer(ISSUER_ID, true, 10_000, META_HASH);
        vm.stopPrank();

        assertTrue(registry.isActive(ISSUER_ID));
    }

    function test_RevertUpdateNotRegistered() public {
        vm.prank(admin);
        vm.expectRevert("IssuerRegistry: not registered");
        registry.updateIssuer(ISSUER_ID, true, 10_000, META_HASH);
    }

    function test_RevertUpdateUnauthorized() public {
        vm.prank(admin);
        registry.registerIssuer(ISSUER_ID, IIssuerRegistry.IssuerType.City, issuerAdmin, 10_000, META_HASH);

        vm.prank(user1);
        vm.expectRevert();
        registry.updateIssuer(ISSUER_ID, false, 10_000, META_HASH);
    }

    // ─── Getters ─────────────────────────────────────────────

    function test_RevertGetIssuerNotRegistered() public {
        vm.expectRevert("IssuerRegistry: not registered");
        registry.getIssuer(ISSUER_ID);
    }

    function test_IsActiveReturnsFalseForUnknown() public view {
        assertFalse(registry.isActive(ISSUER_ID));
    }
}
