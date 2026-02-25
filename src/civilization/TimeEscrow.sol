// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "openzeppelin-contracts/access/AccessControl.sol";

import {IEtrnaERC20} from "../interfaces/IEtrnaERC20.sol";
import {TemporalRightNFT} from "./TemporalRightNFT.sol";
import {EtrnaErrors} from "../lib/EtrnaErrors.sol";

/**
 * @title TimeEscrow
 * @notice Escrows $ETR to mint TemporalRightNFTs representing reserved time.
 *
 * v0 logic:
 * - User escrows stake and mints a Time Window NFT.
 * - Optionally redeem after end time to reclaim stake (if not slashed by higher-layer policies).
 */
contract TimeEscrow is AccessControl {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant SLASHER_ROLE = keccak256("SLASHER_ROLE");

    event Escrowed(uint256 indexed tokenId, address indexed owner, uint256 stake);
    event Redeemed(uint256 indexed tokenId, address indexed owner, uint256 stake);
    event Slashed(uint256 indexed tokenId, address indexed owner, uint256 amount, bytes32 reason);

    IEtrnaERC20 public immutable etr;
    TemporalRightNFT public immutable rights;

    mapping(uint256 => uint256) public stakeOf; // tokenId => stake
    mapping(uint256 => bool) public redeemed;

    constructor(address admin, address etrToken, address rightsNft) {
        if (admin == address(0) || etrToken == address(0) || rightsNft == address(0)) revert EtrnaErrors.ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
        _grantRole(SLASHER_ROLE, admin);

        etr = IEtrnaERC20(etrToken);
        rights = TemporalRightNFT(rightsNft);
    }

    function mintWithEscrow(
        uint64 start,
        uint64 end,
        bytes32 classCode,
        uint256 stake
    ) external returns (uint256 tokenId) {
        if (stake == 0) revert EtrnaErrors.InvalidInput();
        bool ok = etr.transferFrom(msg.sender, address(this), stake);
        if (!ok) revert EtrnaErrors.InvalidState();

        tokenId = rights.mint(msg.sender, start, end, classCode);
        stakeOf[tokenId] = stake;
        emit Escrowed(tokenId, msg.sender, stake);
    }

    function redeem(uint256 tokenId) external {
        if (redeemed[tokenId]) revert EtrnaErrors.InvalidState();
        if (rights.ownerOf(tokenId) != msg.sender) revert EtrnaErrors.Unauthorized();

        (uint64 start, uint64 end, ) = rights.windows(tokenId);
        if (block.timestamp < end) revert EtrnaErrors.Expired(); // using Expired error as "too early" sentinel in v0

        redeemed[tokenId] = true;
        uint256 stake = stakeOf[tokenId];
        stakeOf[tokenId] = 0;

        bool ok = etr.transfer(msg.sender, stake);
        if (!ok) revert EtrnaErrors.InvalidState();
        emit Redeemed(tokenId, msg.sender, stake);
    }

    function slash(uint256 tokenId, uint256 amount, bytes32 reason) external onlyRole(SLASHER_ROLE) {
        if (amount == 0) revert EtrnaErrors.InvalidInput();
        uint256 st = stakeOf[tokenId];
        if (st < amount) revert EtrnaErrors.InsufficientStake();

        stakeOf[tokenId] = st - amount;
        // In v0 we retain slashed stake in-contract for treasury routing by an off-chain operator.
        address owner = rights.ownerOf(tokenId);
        emit Slashed(tokenId, owner, amount, reason);
    }
}
