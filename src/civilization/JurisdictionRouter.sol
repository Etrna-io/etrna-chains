// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "openzeppelin-contracts/access/AccessControl.sol";

import {EtrnaErrors} from "../lib/EtrnaErrors.sol";

/**
 * @title JurisdictionRouter (PNG-F)
 * @notice Routes authority and dispute resolution to the correct governance layer.
 *
 * v0: static routing table maintained by governance.
 * Future: dynamic routing based on CityOS/GCOS registry proofs.
 */
contract JurisdictionRouter is AccessControl {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    event RouteSet(bytes32 indexed jurisdictionId, address indexed authorityContract);

    mapping(bytes32 => address) public authorityOf; // jurisdictionId => governance authority

    constructor(address admin) {
        if (admin == address(0)) revert EtrnaErrors.ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
    }

    function setRoute(bytes32 jurisdictionId, address authorityContract) external onlyRole(ADMIN_ROLE) {
        if (jurisdictionId == bytes32(0)) revert EtrnaErrors.InvalidInput();
        if (authorityContract == address(0)) revert EtrnaErrors.ZeroAddress();
        authorityOf[jurisdictionId] = authorityContract;
        emit RouteSet(jurisdictionId, authorityContract);
    }

    function resolveAuthority(bytes32 jurisdictionId) external view returns (address) {
        address a = authorityOf[jurisdictionId];
        if (a == address(0)) revert EtrnaErrors.NotFound();
        return a;
    }
}
