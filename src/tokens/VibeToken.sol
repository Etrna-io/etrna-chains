// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "openzeppelin-contracts/token/ERC20/extensions/ERC20Permit.sol";
import {AccessControl} from "openzeppelin-contracts/access/AccessControl.sol";
import {Pausable} from "openzeppelin-contracts/security/Pausable.sol";

import {TokenErrors} from "./TokenErrors.sol";
import {TokenEvents} from "./TokenEvents.sol";

/**
 * @title VibeToken ($VIBE)
 * @notice Capped cultural/rewards token for Etrna.
 *
 * Canonical v1:
 * - Max supply: 100,000,000,000 VIBE (18 decimals)
 * - Mintable only by authorized MINTER_ROLE (RewardsEngine / RewardDistributor)
 * - Transfer pause switch for incident response
 */
contract VibeToken is ERC20, ERC20Permit, AccessControl, Pausable {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    uint256 public constant MAX_SUPPLY = 100_000_000_000 ether;

    constructor(string memory name_, string memory symbol_, address admin)
        ERC20(name_, symbol_) ERC20Permit(name_)
    {
        if (admin == address(0)) revert TokenErrors.ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);
        // MINTER_ROLE intentionally unassigned by default.
    }

    function setMinter(address account, bool enabled) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (account == address(0)) revert TokenErrors.ZeroAddress();
        if (enabled) _grantRole(MINTER_ROLE, account);
        else _revokeRole(MINTER_ROLE, account);
        emit TokenEvents.MinterSet(account, enabled);
    }

    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        if (to == address(0)) revert TokenErrors.ZeroAddress();
        if (amount == 0) revert TokenErrors.ZeroAmount();
        uint256 newSupply = totalSupply() + amount;
        if (newSupply > MAX_SUPPLY) revert TokenErrors.ExceedsMaxSupply();
        _mint(to, amount);
        emit TokenEvents.TreasuryMint(to, amount);
    }

    function pause() external onlyRole(PAUSER_ROLE) { _pause(); }
    function unpause() external onlyRole(PAUSER_ROLE) { _unpause(); }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override {
        if (paused()) revert TokenErrors.TransfersPaused();
        super._beforeTokenTransfer(from, to, amount);
    }
}
