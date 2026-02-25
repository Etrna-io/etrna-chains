// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "../interfaces/IPassBindingRegistry.sol";
import "../interfaces/IEtrnal.sol";

/**
 * @title PassBindingRegistry
 * @notice On-chain binding registry that links EtrnaPass / CommunityPass tokens
 *         to an Etrnal soulbound identity.
 * @dev Binding is required to activate pass privileges.
 */
contract PassBindingRegistry is AccessControl, IPassBindingRegistry {
    bytes32 public constant BINDER_ROLE = keccak256("BINDER_ROLE");

    /// @dev Canonical Etrnal contract used to verify etrnalId existence.
    IEtrnal public immutable etrnal;

    /// @dev keccak256(passType, passContract, tokenId) => Binding
    mapping(bytes32 => Binding) private _bindings;

    constructor(address admin, address etrnalContract) {
        require(admin != address(0), "PassBindingRegistry: admin is zero");
        require(etrnalContract != address(0), "PassBindingRegistry: etrnal is zero");

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(BINDER_ROLE, admin);

        etrnal = IEtrnal(etrnalContract);
    }

    // ------------ Helpers ------------

    function _bindingKey(PassType passType, address passContract, uint256 tokenId) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(uint8(passType), passContract, tokenId));
    }

    // ------------ Core logic ------------

    /// @inheritdoc IPassBindingRegistry
    function bind(PassType passType, address passContract, uint256 tokenId, uint256 etrnalId)
        external
        onlyRole(BINDER_ROLE)
    {
        require(passContract != address(0), "PassBindingRegistry: passContract is zero");

        // Verify the pass token exists (ownerOf will revert for nonexistent tokens)
        IERC721(passContract).ownerOf(tokenId);

        // Verify etrnalId exists (ownerOf will revert for nonexistent tokens)
        etrnal.ownerOf(etrnalId);

        bytes32 key = _bindingKey(passType, passContract, tokenId);
        require(!_bindings[key].active, "PassBindingRegistry: already bound");

        _bindings[key] = Binding({
            passType: passType,
            passContract: passContract,
            tokenId: tokenId,
            etrnalId: etrnalId,
            boundAt: uint64(block.timestamp),
            active: true
        });

        emit PassBound(passType, passContract, tokenId, etrnalId);
    }

    /// @inheritdoc IPassBindingRegistry
    function unbind(PassType passType, address passContract, uint256 tokenId)
        external
        onlyRole(BINDER_ROLE)
    {
        bytes32 key = _bindingKey(passType, passContract, tokenId);
        Binding storage b = _bindings[key];
        require(b.active, "PassBindingRegistry: not bound");

        uint256 etrnalId = b.etrnalId;
        b.active = false;

        emit PassUnbound(passType, passContract, tokenId, etrnalId);
    }

    /// @inheritdoc IPassBindingRegistry
    function getBinding(PassType passType, address passContract, uint256 tokenId)
        external
        view
        returns (Binding memory)
    {
        bytes32 key = _bindingKey(passType, passContract, tokenId);
        return _bindings[key];
    }

    /// @inheritdoc IPassBindingRegistry
    function isBound(PassType passType, address passContract, uint256 tokenId)
        external
        view
        returns (bool)
    {
        bytes32 key = _bindingKey(passType, passContract, tokenId);
        return _bindings[key].active;
    }
}
