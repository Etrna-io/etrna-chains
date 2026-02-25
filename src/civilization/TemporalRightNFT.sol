// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721} from "openzeppelin-contracts/token/ERC721/ERC721.sol";
import {AccessControl} from "openzeppelin-contracts/access/AccessControl.sol";

import {EtrnaErrors} from "../lib/EtrnaErrors.sol";

/**
 * @title TemporalRightNFT
 * @notice Represents a transferable right to a time window.
 *
 * Each token encodes:
 * - start time (unix)
 * - end time (unix)
 * - class (purpose code)
 */
contract TemporalRightNFT is ERC721, AccessControl {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    struct Window {
        uint64 start;
        uint64 end;
        bytes32 classCode;
    }

    uint256 public nextId;
    mapping(uint256 => Window) public windows;

    constructor(address admin) ERC721("TimeOS Temporal Right", "TIME-R") {
        if (admin == address(0)) revert EtrnaErrors.ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE, admin);
    }

    function mint(address to, uint64 start, uint64 end, bytes32 classCode) external onlyRole(MINTER_ROLE) returns (uint256 id) {
        if (to == address(0)) revert EtrnaErrors.ZeroAddress();
        if (start == 0 || end == 0 || end <= start) revert EtrnaErrors.InvalidInput();
        if (classCode == bytes32(0)) revert EtrnaErrors.InvalidInput();

        id = ++nextId;
        windows[id] = Window({start: start, end: end, classCode: classCode});
        _safeMint(to, id);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
