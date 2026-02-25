// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "openzeppelin-contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ERC20Votes} from "openzeppelin-contracts/token/ERC20/extensions/ERC20Votes.sol";
import {AccessControl} from "openzeppelin-contracts/access/AccessControl.sol";
import {Pausable} from "openzeppelin-contracts/security/Pausable.sol";

import {TokenErrors} from "./TokenErrors.sol";

/**
 * @title EtrnaToken ($ETR)
 * @notice Fixed-supply governance and alignment token for the Etrna protocol.
 *
 * Canonical v1:
 * - Max supply: 1,000,000,000 ETR (18 decimals)
 * - ERC20Votes-enabled
 * - No inflation: minting occurs once at deployment based on an allocation list
 * - Transfer pause switch for incident response (governance/multisig controlled)
 */
contract EtrnaToken is ERC20, ERC20Permit, ERC20Votes, AccessControl, Pausable {
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    uint256 public constant MAX_SUPPLY = 1_000_000_000 ether;

    constructor(
        string memory name_,
        string memory symbol_,
        address admin,
        address[] memory recipients,
        uint256[] memory amounts
    ) ERC20(name_, symbol_) ERC20Permit(name_) {
        if (admin == address(0)) revert TokenErrors.ZeroAddress();
        if (recipients.length != amounts.length) revert TokenErrors.LengthMismatch();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);

        uint256 total;
        for (uint256 i = 0; i < recipients.length; i++) {
            if (recipients[i] == address(0)) revert TokenErrors.ZeroAddress();
            if (amounts[i] == 0) revert TokenErrors.ZeroAmount();
            total += amounts[i];
        }
        if (total > MAX_SUPPLY) revert TokenErrors.ExceedsMaxSupply();

        for (uint256 i = 0; i < recipients.length; i++) {
            _mint(recipients[i], amounts[i]);
        }
        // Intentionally no mint function after deployment.
    }

    function pause() external onlyRole(PAUSER_ROLE) { _pause(); }
    function unpause() external onlyRole(PAUSER_ROLE) { _unpause(); }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override {
        if (paused()) revert TokenErrors.TransfersPaused();
        super._beforeTokenTransfer(from, to, amount);
    }

    function _afterTokenTransfer(address from, address to, uint256 amount) internal override(ERC20, ERC20Votes) {
        super._afterTokenTransfer(from, to, amount);
    }

    function _mint(address account, uint256 amount) internal override(ERC20, ERC20Votes) {
        super._mint(account, amount);
    }

    function _burn(address account, uint256 amount) internal override(ERC20, ERC20Votes) {
        super._burn(account, amount);
    }

    function nonces(address owner) public view override(ERC20Permit) returns (uint256) {
        return super.nonces(owner);
    }
}
