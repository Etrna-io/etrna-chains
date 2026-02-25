// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/etrnapass/EtrnaPass.sol";

contract EtrnaPassTest is Test {
    EtrnaPass public pass;

    address admin = address(0xA);
    address minter = address(0xB);
    address metadataAdmin = address(0xC);
    address user1 = address(0xD);
    address user2 = address(0xE);
    address royaltyReceiver = address(0xF);

    string constant BASE_URI = "https://assets.etrna.com/ipfs/QmTEST/";
    uint96 constant DEFAULT_ROYALTY_BPS = 500; // 5%

    function setUp() public {
        vm.prank(admin);
        pass = new EtrnaPass(admin, "EtrnaPass", "EPASS", BASE_URI, royaltyReceiver, DEFAULT_ROYALTY_BPS);

        vm.startPrank(admin);
        pass.grantRole(pass.MINTER_ROLE(), minter);
        pass.grantRole(pass.METADATA_ADMIN_ROLE(), metadataAdmin);
        vm.stopPrank();
    }

    // ─── Constructor ─────────────────────────────────────────

    function test_ConstructorSetsNameAndSymbol() public view {
        assertEq(pass.name(), "EtrnaPass");
        assertEq(pass.symbol(), "EPASS");
    }

    function test_ConstructorAssignsRoles() public view {
        assertTrue(pass.hasRole(pass.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(pass.hasRole(pass.MINTER_ROLE(), admin));
        assertTrue(pass.hasRole(pass.METADATA_ADMIN_ROLE(), admin));
    }

    function test_ConstructorSetsDefaultRoyalty() public view {
        // Royalty on a hypothetical 10000 wei sale
        (address receiver, uint256 amount) = pass.royaltyInfo(1, 10000);
        assertEq(receiver, royaltyReceiver);
        assertEq(amount, 500); // 5%
    }

    function test_ConstructorNoRoyaltyWhenZeroReceiver() public {
        vm.prank(admin);
        EtrnaPass noRoyalty = new EtrnaPass(admin, "NR", "NR", BASE_URI, address(0), 500);
        // default royalty should not be set, OZ returns (address(0), 0)
        (address receiver, uint256 amount) = noRoyalty.royaltyInfo(1, 10000);
        assertEq(receiver, address(0));
        assertEq(amount, 0);
    }

    function test_ConstructorNoRoyaltyWhenZeroBps() public {
        vm.prank(admin);
        EtrnaPass noRoyalty = new EtrnaPass(admin, "NR", "NR", BASE_URI, royaltyReceiver, 0);
        (address receiver, uint256 amount) = noRoyalty.royaltyInfo(1, 10000);
        assertEq(receiver, address(0));
        assertEq(amount, 0);
    }

    function test_NextTokenIdStartsAt1() public view {
        assertEq(pass.nextTokenId(), 1);
    }

    // ─── Minting ─────────────────────────────────────────────

    function test_MintCoreStandard() public {
        vm.prank(minter);
        uint256 tokenId = pass.mint(user1, EtrnaPass.Tier.CORE, EtrnaPass.Edition.STANDARD);

        assertEq(tokenId, 1);
        assertEq(pass.ownerOf(1), user1);
        assertEq(pass.nextTokenId(), 2);
    }

    function test_MintEmitsEvent() public {
        vm.expectEmit(true, true, false, true);
        emit EtrnaPass.PassMinted(user1, 1, EtrnaPass.Tier.PRIME, EtrnaPass.Edition.FOIL);

        vm.prank(minter);
        pass.mint(user1, EtrnaPass.Tier.PRIME, EtrnaPass.Edition.FOIL);
    }

    function test_MintAllTierEditionCombinations() public {
        uint256 expectedId = 1;
        for (uint8 t = 0; t < 4; t++) {
            for (uint8 e = 0; e < 3; e++) {
                vm.prank(minter);
                uint256 tokenId = pass.mint(user1, EtrnaPass.Tier(t), EtrnaPass.Edition(e));
                assertEq(tokenId, expectedId);
                expectedId++;
            }
        }
        // 12 total mints
        assertEq(pass.nextTokenId(), 13);
        assertEq(pass.balanceOf(user1), 12);
    }

    function test_MintRevertNonMinter() public {
        vm.prank(user1);
        vm.expectRevert();
        pass.mint(user1, EtrnaPass.Tier.CORE, EtrnaPass.Edition.STANDARD);
    }

    function test_MintRevertMetadataAdminCannotMint() public {
        vm.prank(metadataAdmin);
        vm.expectRevert();
        pass.mint(user1, EtrnaPass.Tier.CORE, EtrnaPass.Edition.STANDARD);
    }

    function test_MintIncrements() public {
        vm.startPrank(minter);
        uint256 id1 = pass.mint(user1, EtrnaPass.Tier.CORE, EtrnaPass.Edition.STANDARD);
        uint256 id2 = pass.mint(user1, EtrnaPass.Tier.PRIME, EtrnaPass.Edition.FOIL);
        uint256 id3 = pass.mint(user2, EtrnaPass.Tier.ORIGIN, EtrnaPass.Edition.LE01);
        vm.stopPrank();

        assertEq(id1, 1);
        assertEq(id2, 2);
        assertEq(id3, 3);
    }

    // ─── Batch Minting ───────────────────────────────────────

    function test_BatchMint() public {
        vm.prank(minter);
        (uint256 first, uint256 last) = pass.batchMint(user1, EtrnaPass.Tier.ASCENDANT, EtrnaPass.Edition.LE01, 5);

        assertEq(first, 1);
        assertEq(last, 5);
        assertEq(pass.balanceOf(user1), 5);
        assertEq(pass.nextTokenId(), 6);

        for (uint256 i = first; i <= last; i++) {
            assertEq(pass.ownerOf(i), user1);
        }
    }

    function test_BatchMintRevertZeroQuantity() public {
        vm.prank(minter);
        vm.expectRevert("quantity=0");
        pass.batchMint(user1, EtrnaPass.Tier.CORE, EtrnaPass.Edition.STANDARD, 0);
    }

    function test_BatchMintRevertNonMinter() public {
        vm.prank(user1);
        vm.expectRevert();
        pass.batchMint(user1, EtrnaPass.Tier.CORE, EtrnaPass.Edition.STANDARD, 3);
    }

    // ─── Tier / Edition Getters ──────────────────────────────

    function test_TokenTier() public {
        vm.prank(minter);
        uint256 id = pass.mint(user1, EtrnaPass.Tier.ASCENDANT, EtrnaPass.Edition.STANDARD);

        assertEq(uint8(pass.tokenTier(id)), uint8(EtrnaPass.Tier.ASCENDANT));
    }

    function test_TokenEdition() public {
        vm.prank(minter);
        uint256 id = pass.mint(user1, EtrnaPass.Tier.CORE, EtrnaPass.Edition.FOIL);

        assertEq(uint8(pass.tokenEdition(id)), uint8(EtrnaPass.Edition.FOIL));
    }

    function test_TokenPassInfo() public {
        vm.prank(minter);
        uint256 id = pass.mint(user1, EtrnaPass.Tier.ORIGIN, EtrnaPass.Edition.LE01);

        (EtrnaPass.Tier tier, EtrnaPass.Edition edition) = pass.tokenPassInfo(id);
        assertEq(uint8(tier), uint8(EtrnaPass.Tier.ORIGIN));
        assertEq(uint8(edition), uint8(EtrnaPass.Edition.LE01));
    }

    function test_TokenTierRevertNonexistent() public {
        vm.expectRevert("ERC721: invalid token ID");
        pass.tokenTier(999);
    }

    function test_TokenEditionRevertNonexistent() public {
        vm.expectRevert("ERC721: invalid token ID");
        pass.tokenEdition(999);
    }

    function test_TokenPassInfoRevertNonexistent() public {
        vm.expectRevert("ERC721: invalid token ID");
        pass.tokenPassInfo(999);
    }

    // ─── Metadata / tokenURI ─────────────────────────────────

    function test_TokenURICoreStandard() public {
        vm.prank(minter);
        uint256 id = pass.mint(user1, EtrnaPass.Tier.CORE, EtrnaPass.Edition.STANDARD);

        string memory expected = string.concat(BASE_URI, "etrnapass_core_standard.json");
        assertEq(pass.tokenURI(id), expected);
    }

    function test_TokenURIPrimeFoil() public {
        vm.prank(minter);
        uint256 id = pass.mint(user1, EtrnaPass.Tier.PRIME, EtrnaPass.Edition.FOIL);

        string memory expected = string.concat(BASE_URI, "etrnapass_prime_foil.json");
        assertEq(pass.tokenURI(id), expected);
    }

    function test_TokenURIAscendantLE01() public {
        vm.prank(minter);
        uint256 id = pass.mint(user1, EtrnaPass.Tier.ASCENDANT, EtrnaPass.Edition.LE01);

        string memory expected = string.concat(BASE_URI, "etrnapass_ascendant_le01.json");
        assertEq(pass.tokenURI(id), expected);
    }

    function test_TokenURIOriginStandard() public {
        vm.prank(minter);
        uint256 id = pass.mint(user1, EtrnaPass.Tier.ORIGIN, EtrnaPass.Edition.STANDARD);

        string memory expected = string.concat(BASE_URI, "etrnapass_origin_standard.json");
        assertEq(pass.tokenURI(id), expected);
    }

    function test_TokenURITemplateMatchesTokenURI() public {
        vm.prank(minter);
        uint256 id = pass.mint(user1, EtrnaPass.Tier.PRIME, EtrnaPass.Edition.LE01);

        string memory template = pass.tokenURITemplate(id);
        assertEq(template, "etrnapass_prime_le01.json");

        string memory fullURI = pass.tokenURI(id);
        assertEq(fullURI, string.concat(BASE_URI, template));
    }

    function test_TokenURIRevertNonexistent() public {
        vm.expectRevert("ERC721: invalid token ID");
        pass.tokenURI(999);
    }

    function test_TokenURITemplateRevertNonexistent() public {
        vm.expectRevert("ERC721: invalid token ID");
        pass.tokenURITemplate(999);
    }

    // ─── All 12 URI templates ────────────────────────────────

    function test_All12TokenURITemplates() public {
        string[4] memory tierNames = ["core", "prime", "ascendant", "origin"];
        string[3] memory edNames = ["standard", "foil", "le01"];

        uint256 id;
        for (uint8 t = 0; t < 4; t++) {
            for (uint8 e = 0; e < 3; e++) {
                vm.prank(minter);
                id = pass.mint(user1, EtrnaPass.Tier(t), EtrnaPass.Edition(e));

                string memory expected = string.concat("etrnapass_", tierNames[t], "_", edNames[e], ".json");
                assertEq(pass.tokenURITemplate(id), expected);
            }
        }
    }

    // ─── setBaseURI ──────────────────────────────────────────

    function test_SetBaseURI() public {
        string memory newURI = "https://new.etrna.com/";

        vm.prank(metadataAdmin);
        pass.setBaseURI(newURI);

        vm.prank(minter);
        uint256 id = pass.mint(user1, EtrnaPass.Tier.CORE, EtrnaPass.Edition.STANDARD);

        assertEq(pass.tokenURI(id), string.concat(newURI, "etrnapass_core_standard.json"));
    }

    function test_SetBaseURIEmitsEvent() public {
        vm.expectEmit(false, false, false, true);
        emit EtrnaPass.BaseURISet("https://new.etrna.com/");

        vm.prank(metadataAdmin);
        pass.setBaseURI("https://new.etrna.com/");
    }

    function test_SetBaseURIRevertNonAdmin() public {
        vm.prank(user1);
        vm.expectRevert();
        pass.setBaseURI("https://evil.com/");
    }

    function test_SetBaseURIRevertMinterCannotSetURI() public {
        vm.prank(minter);
        vm.expectRevert();
        pass.setBaseURI("https://evil.com/");
    }

    // ─── Royalties ───────────────────────────────────────────

    function test_RoyaltyInfo() public view {
        (address receiver, uint256 amount) = pass.royaltyInfo(1, 1 ether);
        assertEq(receiver, royaltyReceiver);
        assertEq(amount, 0.05 ether); // 500 bps = 5%
    }

    function test_SetDefaultRoyalty() public {
        address newReceiver = address(0x99);
        vm.prank(admin);
        pass.setDefaultRoyalty(newReceiver, 1000); // 10%

        vm.prank(minter);
        uint256 id = pass.mint(user1, EtrnaPass.Tier.CORE, EtrnaPass.Edition.STANDARD);

        (address receiver, uint256 amount) = pass.royaltyInfo(id, 1 ether);
        assertEq(receiver, newReceiver);
        assertEq(amount, 0.1 ether);
    }

    function test_SetDefaultRoyaltyRevertNonAdmin() public {
        vm.prank(user1);
        vm.expectRevert();
        pass.setDefaultRoyalty(user1, 1000);
    }

    function test_DeleteDefaultRoyalty() public {
        vm.prank(admin);
        pass.deleteDefaultRoyalty();

        (address receiver, uint256 amount) = pass.royaltyInfo(1, 1 ether);
        assertEq(receiver, address(0));
        assertEq(amount, 0);
    }

    function test_DeleteDefaultRoyaltyRevertNonAdmin() public {
        vm.prank(user1);
        vm.expectRevert();
        pass.deleteDefaultRoyalty();
    }

    // ─── Enumeration ─────────────────────────────────────────

    function test_TotalSupply() public {
        assertEq(pass.totalSupply(), 0);

        vm.startPrank(minter);
        pass.mint(user1, EtrnaPass.Tier.CORE, EtrnaPass.Edition.STANDARD);
        pass.mint(user2, EtrnaPass.Tier.PRIME, EtrnaPass.Edition.FOIL);
        vm.stopPrank();

        assertEq(pass.totalSupply(), 2);
    }

    function test_TokenByIndex() public {
        vm.startPrank(minter);
        pass.mint(user1, EtrnaPass.Tier.CORE, EtrnaPass.Edition.STANDARD);
        pass.mint(user2, EtrnaPass.Tier.PRIME, EtrnaPass.Edition.FOIL);
        vm.stopPrank();

        assertEq(pass.tokenByIndex(0), 1);
        assertEq(pass.tokenByIndex(1), 2);
    }

    function test_TokenOfOwnerByIndex() public {
        vm.startPrank(minter);
        pass.mint(user1, EtrnaPass.Tier.CORE, EtrnaPass.Edition.STANDARD);
        pass.mint(user1, EtrnaPass.Tier.PRIME, EtrnaPass.Edition.FOIL);
        pass.mint(user2, EtrnaPass.Tier.ORIGIN, EtrnaPass.Edition.LE01);
        vm.stopPrank();

        assertEq(pass.tokenOfOwnerByIndex(user1, 0), 1);
        assertEq(pass.tokenOfOwnerByIndex(user1, 1), 2);
        assertEq(pass.tokenOfOwnerByIndex(user2, 0), 3);
    }

    // ─── supportsInterface ───────────────────────────────────

    function test_SupportsERC721() public view {
        // ERC721 interfaceId = 0x80ac58cd
        assertTrue(pass.supportsInterface(0x80ac58cd));
    }

    function test_SupportsERC721Enumerable() public view {
        // ERC721Enumerable interfaceId = 0x780e9d63
        assertTrue(pass.supportsInterface(0x780e9d63));
    }

    function test_SupportsERC2981() public view {
        // ERC2981 interfaceId = 0x2a55205a
        assertTrue(pass.supportsInterface(0x2a55205a));
    }

    function test_SupportsAccessControl() public view {
        // IAccessControl interfaceId = 0x7965db0b
        assertTrue(pass.supportsInterface(0x7965db0b));
    }

    function test_SupportsERC165() public view {
        // ERC165 interfaceId = 0x01ffc9a7
        assertTrue(pass.supportsInterface(0x01ffc9a7));
    }

    function test_DoesNotSupportRandomInterface() public view {
        assertFalse(pass.supportsInterface(0xdeadbeef));
    }

    // ─── Access Control ──────────────────────────────────────

    function test_AdminCanGrantMinterRole() public {
        address newMinter = address(0x77);
        vm.prank(admin);
        pass.grantRole(pass.MINTER_ROLE(), newMinter);
        assertTrue(pass.hasRole(pass.MINTER_ROLE(), newMinter));

        vm.prank(newMinter);
        uint256 id = pass.mint(user1, EtrnaPass.Tier.CORE, EtrnaPass.Edition.STANDARD);
        assertEq(id, 1);
    }

    function test_AdminCanRevokeMinterRole() public {
        vm.prank(admin);
        pass.revokeRole(pass.MINTER_ROLE(), minter);

        vm.prank(minter);
        vm.expectRevert();
        pass.mint(user1, EtrnaPass.Tier.CORE, EtrnaPass.Edition.STANDARD);
    }

    function test_NonAdminCannotGrantRoles() public {
        vm.prank(user1);
        vm.expectRevert();
        pass.grantRole(pass.MINTER_ROLE(), user1);
    }

    // ─── Transfer ────────────────────────────────────────────

    function test_TransferUpdatesEnumeration() public {
        vm.prank(minter);
        pass.mint(user1, EtrnaPass.Tier.CORE, EtrnaPass.Edition.STANDARD);

        assertEq(pass.balanceOf(user1), 1);
        assertEq(pass.balanceOf(user2), 0);

        vm.prank(user1);
        pass.transferFrom(user1, user2, 1);

        assertEq(pass.balanceOf(user1), 0);
        assertEq(pass.balanceOf(user2), 1);
        assertEq(pass.ownerOf(1), user2);
        assertEq(pass.tokenOfOwnerByIndex(user2, 0), 1);
    }

    // ─── Edge Cases ──────────────────────────────────────────

    function test_MintToZeroAddressReverts() public {
        vm.prank(minter);
        vm.expectRevert();
        pass.mint(address(0), EtrnaPass.Tier.CORE, EtrnaPass.Edition.STANDARD);
    }

    function test_AdminMintDirectly() public {
        // admin also has MINTER_ROLE from constructor
        vm.prank(admin);
        uint256 id = pass.mint(user1, EtrnaPass.Tier.ORIGIN, EtrnaPass.Edition.LE01);
        assertEq(id, 1);
    }
}
