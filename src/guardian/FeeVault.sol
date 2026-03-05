// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract FeeVault is ReentrancyGuard {
    address public owner;
    address public pendingOwner;
    mapping(address => bool) public operators;

    event OwnerUpdated(address indexed owner);
    event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);
    event OperatorUpdated(address indexed operator, bool allowed);
    event Withdraw(address indexed to, uint256 amount);
    event Received(address indexed from, uint256 amount);

    modifier onlyOwner() { require(msg.sender == owner, "NOT_OWNER"); _; }
    modifier onlyOperator() { require(msg.sender == owner || operators[msg.sender], "NOT_OPERATOR"); _; }

    constructor(address _owner) {
        require(_owner != address(0), "BAD_OWNER");
        owner = _owner;
        emit OwnerUpdated(_owner);
    }

    function transferOwnership(address _owner) external onlyOwner {
        require(_owner != address(0), "BAD_OWNER");
        pendingOwner = _owner;
        emit OwnershipTransferStarted(owner, _owner);
    }

    function acceptOwnership() external {
        require(msg.sender == pendingOwner, "NOT_PENDING_OWNER");
        owner = pendingOwner;
        pendingOwner = address(0);
        emit OwnerUpdated(msg.sender);
    }

    function setOperator(address op, bool allowed) external onlyOwner {
        operators[op] = allowed;
        emit OperatorUpdated(op, allowed);
    }

    receive() external payable {
        emit Received(msg.sender, msg.value);
    }

    function withdraw(address payable to, uint256 amount) external onlyOperator nonReentrant {
        require(to != address(0), "BAD_TO");
        require(amount <= address(this).balance, "INSUFFICIENT");
        emit Withdraw(to, amount);
        (bool ok,) = to.call{value: amount}("");
        require(ok, "WITHDRAW_FAIL");
    }
}
