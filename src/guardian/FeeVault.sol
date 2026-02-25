// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract FeeVault {
    address public owner;
    mapping(address => bool) public operators;

    event OwnerUpdated(address indexed owner);
    event OperatorUpdated(address indexed operator, bool allowed);
    event Withdraw(address indexed to, uint256 amount);

    modifier onlyOwner() { require(msg.sender == owner, "NOT_OWNER"); _; }
    modifier onlyOperator() { require(msg.sender == owner || operators[msg.sender], "NOT_OPERATOR"); _; }

    constructor(address _owner) {
        require(_owner != address(0), "BAD_OWNER");
        owner = _owner;
        emit OwnerUpdated(_owner);
    }

    function setOwner(address _owner) external onlyOwner {
        require(_owner != address(0), "BAD_OWNER");
        owner = _owner;
        emit OwnerUpdated(_owner);
    }

    function setOperator(address op, bool allowed) external onlyOwner {
        operators[op] = allowed;
        emit OperatorUpdated(op, allowed);
    }

    receive() external payable {}

    function withdraw(address payable to, uint256 amount) external onlyOperator {
        require(to != address(0), "BAD_TO");
        require(amount <= address(this).balance, "INSUFFICIENT");
        (bool ok,) = to.call{value: amount}("");
        require(ok, "WITHDRAW_FAIL");
        emit Withdraw(to, amount);
    }
}
