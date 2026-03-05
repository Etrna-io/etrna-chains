// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/guardian/FeeVault.sol";
import "../src/guardian/InsurancePool.sol";

// ── Helper: contract that can receive ETH ─────────────────────
contract Receiver {
    receive() external payable {}
}

// ── Helper: contract that rejects ETH ─────────────────────────
contract RejectingReceiver {
    receive() external payable {
        revert("no thanks");
    }
}

// ═══════════════════════════════════════════════════════════════
//  FeeVault Tests
// ═══════════════════════════════════════════════════════════════

contract FeeVaultTest is Test {
    FeeVault public vault;

    address admin = address(0xAD);
    address operator1 = address(0x0001);
    address operator2 = address(0x0002);
    address alice = address(0xA11CE);

    function setUp() public {
        vault = new FeeVault(admin);
    }

    // ─── Constructor ──────────────────────────────────────────

    function test_Constructor() public view {
        assertEq(vault.owner(), admin);
    }

    function test_RevertConstructor_ZeroOwner() public {
        vm.expectRevert(bytes("BAD_OWNER"));
        new FeeVault(address(0));
    }

    // ─── transferOwnership / acceptOwnership ─────────────────

    function test_TransferOwnership() public {
        vm.prank(admin);
        vm.expectEmit(true, true, false, false);
        emit FeeVault.OwnershipTransferStarted(admin, alice);
        vault.transferOwnership(alice);

        // Owner hasn't changed yet
        assertEq(vault.owner(), admin);
        assertEq(vault.pendingOwner(), alice);

        // Alice accepts
        vm.prank(alice);
        vm.expectEmit(true, false, false, false);
        emit FeeVault.OwnerUpdated(alice);
        vault.acceptOwnership();
        assertEq(vault.owner(), alice);
        assertEq(vault.pendingOwner(), address(0));
    }

    function test_RevertTransferOwnership_NotOwner() public {
        vm.prank(alice);
        vm.expectRevert(bytes("NOT_OWNER"));
        vault.transferOwnership(alice);
    }

    function test_RevertTransferOwnership_Zero() public {
        vm.prank(admin);
        vm.expectRevert(bytes("BAD_OWNER"));
        vault.transferOwnership(address(0));
    }

    function test_RevertAcceptOwnership_NotPending() public {
        vm.prank(admin);
        vault.transferOwnership(alice);

        vm.prank(operator1); // wrong address
        vm.expectRevert(bytes("NOT_PENDING_OWNER"));
        vault.acceptOwnership();
    }

    // ─── setOperator ──────────────────────────────────────────

    function test_SetOperator() public {
        vm.prank(admin);
        vm.expectEmit(true, false, false, true);
        emit FeeVault.OperatorUpdated(operator1, true);
        vault.setOperator(operator1, true);
        assertTrue(vault.operators(operator1));
    }

    function test_SetOperator_Remove() public {
        vm.startPrank(admin);
        vault.setOperator(operator1, true);
        vault.setOperator(operator1, false);
        vm.stopPrank();
        assertFalse(vault.operators(operator1));
    }

    function test_RevertSetOperator_NotOwner() public {
        vm.prank(alice);
        vm.expectRevert(bytes("NOT_OWNER"));
        vault.setOperator(operator1, true);
    }

    // ─── receive ──────────────────────────────────────────────

    function test_ReceiveEth() public {
        vm.deal(alice, 5 ether);
        vm.prank(alice);
        (bool ok,) = address(vault).call{value: 2 ether}("");
        assertTrue(ok);
        assertEq(address(vault).balance, 2 ether);
    }

    // ─── withdraw ─────────────────────────────────────────────

    function test_Withdraw_ByOwner() public {
        vm.deal(address(vault), 10 ether);
        Receiver recv = new Receiver();

        vm.prank(admin);
        vm.expectEmit(true, false, false, true);
        emit FeeVault.Withdraw(address(recv), 3 ether);
        vault.withdraw(payable(address(recv)), 3 ether);

        assertEq(address(recv).balance, 3 ether);
        assertEq(address(vault).balance, 7 ether);
    }

    function test_Withdraw_ByOperator() public {
        vm.deal(address(vault), 10 ether);
        Receiver recv = new Receiver();

        vm.prank(admin);
        vault.setOperator(operator1, true);

        vm.prank(operator1);
        vault.withdraw(payable(address(recv)), 5 ether);

        assertEq(address(recv).balance, 5 ether);
    }

    function test_Withdraw_FullBalance() public {
        vm.deal(address(vault), 1 ether);
        Receiver recv = new Receiver();

        vm.prank(admin);
        vault.withdraw(payable(address(recv)), 1 ether);

        assertEq(address(vault).balance, 0);
        assertEq(address(recv).balance, 1 ether);
    }

    function test_RevertWithdraw_NotOperator() public {
        vm.deal(address(vault), 1 ether);

        vm.prank(alice);
        vm.expectRevert(bytes("NOT_OPERATOR"));
        vault.withdraw(payable(alice), 1 ether);
    }

    function test_RevertWithdraw_ZeroAddress() public {
        vm.deal(address(vault), 1 ether);

        vm.prank(admin);
        vm.expectRevert(bytes("BAD_TO"));
        vault.withdraw(payable(address(0)), 1 ether);
    }

    function test_RevertWithdraw_Insufficient() public {
        vm.deal(address(vault), 1 ether);

        vm.prank(admin);
        vm.expectRevert(bytes("INSUFFICIENT"));
        vault.withdraw(payable(alice), 2 ether);
    }

    function test_RevertWithdraw_TransferFails() public {
        vm.deal(address(vault), 1 ether);
        RejectingReceiver bad = new RejectingReceiver();

        vm.prank(admin);
        vm.expectRevert(bytes("WITHDRAW_FAIL"));
        vault.withdraw(payable(address(bad)), 1 ether);
    }

    // ─── Multiple operators ───────────────────────────────────

    function test_MultipleOperators() public {
        vm.deal(address(vault), 10 ether);
        Receiver recv = new Receiver();

        vm.startPrank(admin);
        vault.setOperator(operator1, true);
        vault.setOperator(operator2, true);
        vm.stopPrank();

        vm.prank(operator1);
        vault.withdraw(payable(address(recv)), 3 ether);

        vm.prank(operator2);
        vault.withdraw(payable(address(recv)), 4 ether);

        assertEq(address(recv).balance, 7 ether);
        assertEq(address(vault).balance, 3 ether);
    }
}

// ═══════════════════════════════════════════════════════════════
//  InsurancePool Tests
// ═══════════════════════════════════════════════════════════════

contract InsurancePoolTest is Test {
    InsurancePool public pool;

    address admin = address(0xAD);
    address alice = address(0xA11CE);
    address bob = address(0xB0B);

    function setUp() public {
        pool = new InsurancePool(admin);
    }

    // ─── Constructor ──────────────────────────────────────────

    function test_Constructor() public view {
        assertEq(pool.owner(), admin);
    }

    function test_RevertConstructor_ZeroOwner() public {
        vm.expectRevert(bytes("BAD_OWNER"));
        new InsurancePool(address(0));
    }

    // ─── setOwner ─────────────────────────────────────────────

    function test_SetOwner() public {
        vm.prank(admin);
        vm.expectEmit(true, false, false, false);
        emit InsurancePool.OwnerUpdated(alice);
        pool.setOwner(alice);
        assertEq(pool.owner(), alice);
    }

    function test_RevertSetOwner_NotOwner() public {
        vm.prank(alice);
        vm.expectRevert(bytes("NOT_OWNER"));
        pool.setOwner(alice);
    }

    function test_RevertSetOwner_Zero() public {
        vm.prank(admin);
        vm.expectRevert(bytes("BAD_OWNER"));
        pool.setOwner(address(0));
    }

    // ─── deposit ──────────────────────────────────────────────

    function test_Deposit() public {
        vm.deal(alice, 5 ether);
        vm.prank(alice);
        vm.expectEmit(true, false, false, true);
        emit InsurancePool.Deposit(alice, 2 ether);
        pool.deposit{value: 2 ether}();

        assertEq(pool.balanceOf(alice), 2 ether);
        assertEq(address(pool).balance, 2 ether);
    }

    function test_Deposit_Multiple() public {
        vm.deal(alice, 10 ether);
        vm.startPrank(alice);
        pool.deposit{value: 1 ether}();
        pool.deposit{value: 3 ether}();
        vm.stopPrank();

        assertEq(pool.balanceOf(alice), 4 ether);
    }

    function test_Deposit_MultipleUsers() public {
        vm.deal(alice, 5 ether);
        vm.deal(bob, 5 ether);

        vm.prank(alice);
        pool.deposit{value: 2 ether}();

        vm.prank(bob);
        pool.deposit{value: 3 ether}();

        assertEq(pool.balanceOf(alice), 2 ether);
        assertEq(pool.balanceOf(bob), 3 ether);
        assertEq(address(pool).balance, 5 ether);
    }

    function test_RevertDeposit_Zero() public {
        vm.prank(alice);
        vm.expectRevert(bytes("ZERO"));
        pool.deposit{value: 0}();
    }

    // ─── receive() → deposit() ────────────────────────────────

    function test_ReceiveFallback() public {
        vm.deal(alice, 5 ether);
        vm.prank(alice);
        (bool ok,) = address(pool).call{value: 1 ether}("");
        assertTrue(ok);
        assertEq(pool.balanceOf(alice), 1 ether);
    }

    // ─── withdraw ─────────────────────────────────────────────

    function test_Withdraw() public {
        vm.deal(alice, 5 ether);
        vm.startPrank(alice);
        pool.deposit{value: 3 ether}();

        vm.expectEmit(true, false, false, true);
        emit InsurancePool.Withdraw(alice, 1 ether);
        pool.withdraw(1 ether);
        vm.stopPrank();

        assertEq(pool.balanceOf(alice), 2 ether);
        assertEq(alice.balance, 3 ether); // 5 - 3 deposited + 1 withdrawn
    }

    function test_Withdraw_FullBalance() public {
        vm.deal(alice, 5 ether);
        vm.startPrank(alice);
        pool.deposit{value: 2 ether}();
        pool.withdraw(2 ether);
        vm.stopPrank();

        assertEq(pool.balanceOf(alice), 0);
    }

    function test_RevertWithdraw_Zero() public {
        vm.deal(alice, 1 ether);
        vm.startPrank(alice);
        pool.deposit{value: 1 ether}();
        vm.expectRevert(bytes("ZERO"));
        pool.withdraw(0);
        vm.stopPrank();
    }

    function test_RevertWithdraw_Insufficient() public {
        vm.deal(alice, 1 ether);
        vm.startPrank(alice);
        pool.deposit{value: 1 ether}();
        vm.expectRevert(bytes("INSUFFICIENT"));
        pool.withdraw(2 ether);
        vm.stopPrank();
    }

    function test_RevertWithdraw_NothingDeposited() public {
        vm.prank(alice);
        vm.expectRevert(bytes("INSUFFICIENT"));
        pool.withdraw(1);
    }

    // ─── Isolation: one user can't withdraw another's ─────────

    function test_WithdrawIsolation() public {
        vm.deal(alice, 5 ether);
        vm.deal(bob, 5 ether);

        vm.prank(alice);
        pool.deposit{value: 3 ether}();

        vm.prank(bob);
        pool.deposit{value: 2 ether}();

        // alice withdraws her amount
        vm.prank(alice);
        pool.withdraw(3 ether);
        assertEq(pool.balanceOf(alice), 0);

        // bob's balance unchanged
        assertEq(pool.balanceOf(bob), 2 ether);

        // bob can't withdraw more than his
        vm.prank(bob);
        vm.expectRevert(bytes("INSUFFICIENT"));
        pool.withdraw(3 ether);
    }
}
