// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/CommunityPass.sol";
import "../src/CommunityTaskRegistry.sol";

contract CommunityTaskRegistryTest is Test {
    CommunityPass public pass;
    CommunityTaskRegistry public tasks;

    address admin = address(1);
    address registrar = address(2);
    address business = address(3);
    address resident = address(4);
    address stranger = address(5);

    function setUp() public {
        vm.startPrank(admin);
        pass = new CommunityPass("ETRNA Community Pass", "ECP", "https://api.etrna.io/pass/", admin);
        tasks = new CommunityTaskRegistry(admin, address(pass));

        pass.grantRegistrar(registrar);
        tasks.grantBusiness(business);
        vm.stopPrank();

        // Issue a pass to resident for city 1
        vm.prank(registrar);
        pass.issuePass(resident, 1);
    }

    // ─── Task creation ───────────────────────────────────────

    function test_CreateTask() public {
        vm.prank(business);
        uint256 id = tasks.createTask(1, 100, 0);

        assertEq(id, 1);
        (uint256 taskId, address creator, uint32 cityId,,,uint32 rewardXP, bool active) = tasks.tasks(1);
        assertEq(taskId, 1);
        assertEq(creator, business);
        assertEq(cityId, 1);
        assertEq(rewardXP, 100);
        assertTrue(active);
    }

    function test_RevertNonBusinessCreate() public {
        vm.prank(resident);
        vm.expectRevert();
        tasks.createTask(1, 100, 0);
    }

    // ─── Task completion ─────────────────────────────────────

    function test_CompleteTask() public {
        vm.prank(business);
        tasks.createTask(1, 50, 0);

        vm.prank(resident);
        tasks.completeTask(1);

        assertTrue(tasks.completedBy(1, resident));
    }

    function test_RevertDoubleComplete() public {
        vm.prank(business);
        tasks.createTask(1, 50, 0);

        vm.prank(resident);
        tasks.completeTask(1);

        vm.prank(resident);
        vm.expectRevert("CommunityTaskRegistry: already completed");
        tasks.completeTask(1);
    }

    function test_RevertStrangerComplete() public {
        vm.prank(business);
        tasks.createTask(1, 50, 0);

        // Stranger has no CommunityPass for city 1
        vm.prank(stranger);
        vm.expectRevert("CommunityTaskRegistry: no pass for city");
        tasks.completeTask(1);
    }

    function test_RevertWrongCityPass() public {
        // Resident has pass for city 1, task is for city 2
        vm.prank(business);
        tasks.createTask(2, 50, 0);

        vm.prank(resident);
        vm.expectRevert("CommunityTaskRegistry: no pass for city");
        tasks.completeTask(1); // task 1 is city 2
    }

    // ─── Task deactivation ───────────────────────────────────

    function test_Deactivate() public {
        vm.prank(business);
        tasks.createTask(1, 50, 0);

        vm.prank(business);
        tasks.deactivateTask(1);

        (,,,,,,bool active) = tasks.tasks(1);
        assertFalse(active);
    }

    function test_RevertCompleteInactive() public {
        vm.prank(business);
        tasks.createTask(1, 50, 0);

        vm.prank(business);
        tasks.deactivateTask(1);

        vm.prank(resident);
        vm.expectRevert("CommunityTaskRegistry: inactive");
        tasks.completeTask(1);
    }

    // ─── Expiry ──────────────────────────────────────────────

    function test_RevertExpiredTask() public {
        vm.prank(business);
        tasks.createTask(1, 50, uint64(block.timestamp + 100));

        // Warp past expiry
        vm.warp(block.timestamp + 200);

        vm.prank(resident);
        vm.expectRevert("CommunityTaskRegistry: expired");
        tasks.completeTask(1);
    }

    function test_CompleteAtExactExpiry() public {
        uint64 expiry = uint64(block.timestamp + 100);
        vm.prank(business);
        tasks.createTask(1, 50, expiry);

        vm.warp(expiry); // exactly at boundary
        vm.prank(resident);
        tasks.completeTask(1);
        assertTrue(tasks.completedBy(1, resident));
    }

    function test_NoExpiryTaskStillWorksLater() public {
        vm.prank(business);
        tasks.createTask(1, 50, 0); // expiresAt = 0 → no expiry

        vm.warp(block.timestamp + 365 days);
        vm.prank(resident);
        tasks.completeTask(1);
        assertTrue(tasks.completedBy(1, resident));
    }

    // ─── Constructor validation ──────────────────────────────

    function test_RevertZeroAdmin() public {
        vm.expectRevert("CommunityTaskRegistry: admin is zero");
        new CommunityTaskRegistry(address(0), address(pass));
    }

    function test_RevertZeroPass() public {
        vm.expectRevert("CommunityTaskRegistry: pass is zero");
        new CommunityTaskRegistry(admin, address(0));
    }

    // ─── Role management ─────────────────────────────────────

    function test_GrantCityAdmin() public {
        vm.prank(admin);
        tasks.grantCityAdmin(resident);
        assertTrue(tasks.hasRole(tasks.CITY_ADMIN_ROLE(), resident));
    }

    function test_RevertGrantCityAdminUnauthorized() public {
        vm.prank(business);
        vm.expectRevert();
        tasks.grantCityAdmin(resident);
    }

    function test_RevertGrantBusinessUnauthorized() public {
        vm.prank(resident);
        vm.expectRevert();
        tasks.grantBusiness(stranger);
    }

    function test_CityAdminCanGrantBusiness() public {
        // Grant resident as city admin, then resident grants stranger as business
        vm.prank(admin);
        tasks.grantCityAdmin(resident);

        vm.prank(resident);
        tasks.grantBusiness(stranger);
        assertTrue(tasks.hasRole(tasks.BUSINESS_ROLE(), stranger));
    }

    // ─── createTask validation ───────────────────────────────

    function test_RevertCityIdZero() public {
        vm.prank(business);
        vm.expectRevert("CommunityTaskRegistry: cityId required");
        tasks.createTask(0, 100, 0);
    }

    function test_RevertRewardXPZero() public {
        vm.prank(business);
        vm.expectRevert("CommunityTaskRegistry: rewardXP required");
        tasks.createTask(1, 0, 0);
    }

    function test_NextTaskIdIncrements() public {
        vm.startPrank(business);
        uint256 id1 = tasks.createTask(1, 10, 0);
        uint256 id2 = tasks.createTask(1, 20, 0);
        uint256 id3 = tasks.createTask(1, 30, 0);
        vm.stopPrank();

        assertEq(id1, 1);
        assertEq(id2, 2);
        assertEq(id3, 3);
        assertEq(tasks.nextTaskId(), 4);
    }

    // ─── deactivateTask extended ─────────────────────────────

    function test_AdminCanDeactivate() public {
        vm.prank(business);
        tasks.createTask(1, 50, 0);

        vm.prank(admin); // admin, not creator
        tasks.deactivateTask(1);

        (,,,,,,bool active) = tasks.tasks(1);
        assertFalse(active);
    }

    function test_RevertDeactivateNonExistent() public {
        vm.prank(admin);
        vm.expectRevert("CommunityTaskRegistry: no task");
        tasks.deactivateTask(999);
    }

    function test_RevertDeactivateUnauthorized() public {
        vm.prank(business);
        tasks.createTask(1, 50, 0);

        vm.prank(resident); // not admin, not creator
        vm.expectRevert("CommunityTaskRegistry: not authorized");
        tasks.deactivateTask(1);
    }

    function test_RevertDeactivateAlreadyInactive() public {
        vm.prank(business);
        tasks.createTask(1, 50, 0);

        vm.prank(business);
        tasks.deactivateTask(1);

        vm.prank(business);
        vm.expectRevert("CommunityTaskRegistry: already inactive");
        tasks.deactivateTask(1);
    }

    // ─── completeTask extended ───────────────────────────────

    function test_RevertCompleteNonExistent() public {
        vm.prank(resident);
        vm.expectRevert("CommunityTaskRegistry: no task");
        tasks.completeTask(999);
    }

    function test_RevertCompleteRevokedPass() public {
        vm.prank(business);
        tasks.createTask(1, 50, 0);

        // Revoke resident's pass
        uint256 passId = pass.cityPassOf(1, resident);
        vm.prank(admin);
        pass.revokePass(passId);

        vm.prank(resident);
        vm.expectRevert(); // ownerOf will revert since token is burned
        tasks.completeTask(1);
    }

    // ─── Event emission ──────────────────────────────────────

    function test_EmitTaskCreated() public {
        vm.prank(business);
        vm.expectEmit(true, true, true, true);
        emit CommunityTaskRegistry.TaskCreated(1, business, 1, 100, 0);
        tasks.createTask(1, 100, 0);
    }

    function test_EmitTaskDeactivated() public {
        vm.prank(business);
        tasks.createTask(1, 50, 0);

        vm.prank(business);
        vm.expectEmit(true, false, false, false);
        emit CommunityTaskRegistry.TaskDeactivated(1);
        tasks.deactivateTask(1);
    }

    function test_EmitTaskCompleted() public {
        vm.prank(business);
        tasks.createTask(1, 50, 0);

        vm.prank(resident);
        vm.expectEmit(true, true, true, true);
        emit CommunityTaskRegistry.TaskCompleted(1, resident, 1, 50);
        tasks.completeTask(1);
    }
}
