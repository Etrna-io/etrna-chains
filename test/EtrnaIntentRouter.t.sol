// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/intents/EtrnaIntentRouter.sol";

// ── Mock MeshHub for testing intent creation ──────────────────
contract MockMeshHub {
    uint256 public callCount;
    bytes32 public lastReturn;

    // Matches the IMeshHub interface from EtrnaIntentRouter:
    // createIntent(uint8, uint256, address, uint256, bytes32) → bytes32
    function createIntent(
        uint8 /* actionType */,
        uint256 /* dstChainId */,
        address /* asset */,
        uint256 /* amount */,
        bytes32 /* paramsHash */
    ) external payable returns (bytes32) {
        callCount++;
        lastReturn = keccak256(abi.encodePacked(callCount, block.timestamp));
        return lastReturn;
    }
}

// ── Mock IdentityGuard ────────────────────────────────────────
contract MockIdentityGuard {
    bool public returnValue = true;

    function setReturn(bool v) external {
        returnValue = v;
    }

    function check(
        bytes32 /* policyId */,
        address /* account */,
        bytes calldata /* proof */
    ) external view returns (bool) {
        return returnValue;
    }
}

contract EtrnaIntentRouterTest is Test {
    EtrnaIntentRouter public routerContract;
    MockMeshHub public mockHub;
    MockIdentityGuard public mockGuard;

    address owner = address(this);
    address alice = address(0xA11CE);
    address bob = address(0xB0B);

    bytes32 constant POLICY_ID = keccak256("kyc-policy");
    bytes32 constant REQUEST_ID_1 = keccak256("req-1");
    bytes32 constant REQUEST_ID_2 = keccak256("req-2");

    function setUp() public {
        mockHub = new MockMeshHub();
        mockGuard = new MockIdentityGuard();
        routerContract = new EtrnaIntentRouter(address(mockHub), address(mockGuard));
    }

    // ─── Constructor ──────────────────────────────────────────

    function test_Constructor() public view {
        assertEq(routerContract.meshHub(), address(mockHub));
        assertEq(routerContract.identityGuard(), address(mockGuard));
    }

    function test_RevertConstructor_ZeroMeshHub() public {
        vm.expectRevert("EtrnaIntentRouter: meshHub=0");
        new EtrnaIntentRouter(address(0), address(mockGuard));
    }

    function test_Constructor_ZeroGuardAllowed() public {
        // identityGuard = 0 is permitted (no policy enforcement)
        EtrnaIntentRouter r = new EtrnaIntentRouter(address(mockHub), address(0));
        assertEq(r.identityGuard(), address(0));
    }

    // ─── setMeshHub ───────────────────────────────────────────

    function test_SetMeshHub() public {
        address newHub = address(0x1234);
        vm.expectEmit(true, false, false, false);
        emit EtrnaIntentRouter.MeshHubSet(newHub);
        routerContract.setMeshHub(newHub);
        assertEq(routerContract.meshHub(), newHub);
    }

    function test_RevertSetMeshHub_Zero() public {
        vm.expectRevert("EtrnaIntentRouter: meshHub=0");
        routerContract.setMeshHub(address(0));
    }

    function test_RevertSetMeshHub_NotOwner() public {
        vm.prank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        routerContract.setMeshHub(address(0x1234));
    }

    // ─── setIdentityGuard ─────────────────────────────────────

    function test_SetIdentityGuard() public {
        address newGuard = address(0x5678);
        vm.expectEmit(true, false, false, false);
        emit EtrnaIntentRouter.IdentityGuardSet(newGuard);
        routerContract.setIdentityGuard(newGuard);
        assertEq(routerContract.identityGuard(), newGuard);
    }

    function test_RevertSetIdentityGuard_NotOwner() public {
        vm.prank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        routerContract.setIdentityGuard(address(0x5678));
    }

    // ─── setPolicy ────────────────────────────────────────────

    function test_SetPolicy() public {
        vm.expectEmit(true, false, false, true);
        emit EtrnaIntentRouter.PolicySet(POLICY_ID, true);
        routerContract.setPolicy(POLICY_ID, true);
        assertTrue(routerContract.policyEnabled(POLICY_ID));
    }

    function test_SetPolicy_Disable() public {
        routerContract.setPolicy(POLICY_ID, true);
        routerContract.setPolicy(POLICY_ID, false);
        assertFalse(routerContract.policyEnabled(POLICY_ID));
    }

    function test_RevertSetPolicy_NotOwner() public {
        vm.prank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        routerContract.setPolicy(POLICY_ID, true);
    }

    // ─── createRoutedIntent — no policy ───────────────────────

    function test_CreateRoutedIntent_NoPolicy() public {
        vm.prank(alice);
        bytes32 intentId = routerContract.createRoutedIntent(
            REQUEST_ID_1,
            bytes32(0), // no policy
            hex"",      // no proof
            1,          // MINT_NFT
            42,
            address(0),
            100,
            keccak256("params")
        );

        assertTrue(intentId != bytes32(0));
        assertTrue(routerContract.consumedClientRequest(REQUEST_ID_1));
        assertEq(mockHub.callCount(), 1);
    }

    function test_CreateRoutedIntent_EmitsEvents() public {
        vm.prank(alice);

        vm.expectEmit(true, true, false, false);
        emit EtrnaIntentRouter.ClientRequestConsumed(REQUEST_ID_1, alice);
        routerContract.createRoutedIntent(
            REQUEST_ID_1, bytes32(0), hex"", 1, 42, address(0), 100, bytes32(0)
        );
    }

    function test_CreateRoutedIntent_ForwardsValue() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        routerContract.createRoutedIntent{value: 0.5 ether}(
            REQUEST_ID_1, bytes32(0), hex"", 1, 42, address(0), 100, bytes32(0)
        );
        assertEq(address(mockHub).balance, 0.5 ether);
    }

    // ─── createRoutedIntent — with policy ─────────────────────

    function test_CreateRoutedIntent_WithPolicy_Passes() public {
        routerContract.setPolicy(POLICY_ID, true);
        mockGuard.setReturn(true);

        vm.prank(alice);
        bytes32 intentId = routerContract.createRoutedIntent(
            REQUEST_ID_1, POLICY_ID, abi.encode("proof-data"), 1, 42, address(0), 100, bytes32(0)
        );
        assertTrue(intentId != bytes32(0));
    }

    function test_CreateRoutedIntent_WithPolicy_Fails() public {
        routerContract.setPolicy(POLICY_ID, true);
        mockGuard.setReturn(false);

        vm.prank(alice);
        vm.expectRevert("EtrnaIntentRouter: policy failed");
        routerContract.createRoutedIntent(
            REQUEST_ID_1, POLICY_ID, hex"", 1, 42, address(0), 100, bytes32(0)
        );
    }

    function test_CreateRoutedIntent_PolicyEnabled_NoGuard() public {
        // set guard to zero, enable policy
        routerContract.setIdentityGuard(address(0));
        routerContract.setPolicy(POLICY_ID, true);

        vm.prank(alice);
        vm.expectRevert("EtrnaIntentRouter: guard not set");
        routerContract.createRoutedIntent(
            REQUEST_ID_1, POLICY_ID, hex"", 1, 42, address(0), 100, bytes32(0)
        );
    }

    function test_CreateRoutedIntent_PolicyDisabled_SkipsCheck() public {
        // policyId is non-zero but not enabled → no check
        mockGuard.setReturn(false);

        vm.prank(alice);
        bytes32 intentId = routerContract.createRoutedIntent(
            REQUEST_ID_1, POLICY_ID, hex"", 1, 42, address(0), 100, bytes32(0)
        );
        assertTrue(intentId != bytes32(0));
    }

    // ─── Replay protection ────────────────────────────────────

    function test_RevertReplay() public {
        vm.startPrank(alice);
        routerContract.createRoutedIntent(
            REQUEST_ID_1, bytes32(0), hex"", 1, 42, address(0), 100, bytes32(0)
        );
        vm.expectRevert("EtrnaIntentRouter: replay");
        routerContract.createRoutedIntent(
            REQUEST_ID_1, bytes32(0), hex"", 1, 42, address(0), 100, bytes32(0)
        );
        vm.stopPrank();
    }

    function test_RevertZeroRequestId() public {
        vm.prank(alice);
        vm.expectRevert("EtrnaIntentRouter: requestId=0");
        routerContract.createRoutedIntent(
            bytes32(0), bytes32(0), hex"", 1, 42, address(0), 100, bytes32(0)
        );
    }

    function test_DifferentRequestIds_DifferentCallers() public {
        vm.prank(alice);
        routerContract.createRoutedIntent(
            REQUEST_ID_1, bytes32(0), hex"", 1, 42, address(0), 100, bytes32(0)
        );

        vm.prank(bob);
        routerContract.createRoutedIntent(
            REQUEST_ID_2, bytes32(0), hex"", 1, 42, address(0), 100, bytes32(0)
        );

        assertTrue(routerContract.consumedClientRequest(REQUEST_ID_1));
        assertTrue(routerContract.consumedClientRequest(REQUEST_ID_2));
    }

    // Same requestId from different callers should also revert (global replay)
    function test_RevertSameRequestId_DifferentCallers() public {
        vm.prank(alice);
        routerContract.createRoutedIntent(
            REQUEST_ID_1, bytes32(0), hex"", 1, 42, address(0), 100, bytes32(0)
        );

        vm.prank(bob);
        vm.expectRevert("EtrnaIntentRouter: replay");
        routerContract.createRoutedIntent(
            REQUEST_ID_1, bytes32(0), hex"", 1, 42, address(0), 100, bytes32(0)
        );
    }
}
