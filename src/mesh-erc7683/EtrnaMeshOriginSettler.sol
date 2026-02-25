// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IOriginSettler} from "./IOriginSettler.sol";
import {ERC7683Types} from "./ERC7683Types.sol";
import {MeshHub} from "../mesh/MeshHub.sol";
import {MeshTypes} from "../mesh/MeshTypes.sol";

/// @notice Origin settler that converts ERC-7683 onchain orders into MeshHub intents.
/// @dev Settlement economics (escrow/fees) are handled by higher-level modules in Etrna.
contract EtrnaMeshOriginSettler is IOriginSettler {
    MeshHub public immutable meshHub;
    mapping(address => mapping(uint256 => bool)) public usedNonces;

    error InvalidOrder();
    error NonceUsed();
    error DeadlineExpired();

    constructor(address _meshHub) {
        require(_meshHub != address(0), "meshHub=0");
        meshHub = MeshHub(_meshHub);
    }

    function open(ERC7683Types.OnchainCrossChainOrder calldata order) external override {
        if (order.user != msg.sender) revert InvalidOrder();
        if (order.openDeadline != 0 && block.timestamp > order.openDeadline) revert DeadlineExpired();
        if (usedNonces[msg.sender][order.nonce]) revert NonceUsed();
        usedNonces[msg.sender][order.nonce] = true;

        (MeshTypes.ActionType actionType, uint256 dstChainId, address asset, uint256 amount, bytes32 paramsHash) =
            abi.decode(order.orderData, (MeshTypes.ActionType, uint256, address, uint256, bytes32));

        bytes32 intentId = meshHub.createIntent(actionType, dstChainId, asset, amount, paramsHash);

        ERC7683Types.ResolvedCrossChainOrder memory resolved = _buildResolved(order, intentId, dstChainId, paramsHash);
        emit Open(intentId, resolved);
    }

    function resolve(ERC7683Types.OnchainCrossChainOrder calldata order)
        external view override returns (ERC7683Types.ResolvedCrossChainOrder memory)
    {
        bytes32 syntheticId = keccak256(abi.encode(order.originSettler, order.user, order.nonce, order.originChainId));
        (, uint256 dstChainId, , , bytes32 paramsHash) =
            abi.decode(order.orderData, (MeshTypes.ActionType, uint256, address, uint256, bytes32));
        return _buildResolved(order, syntheticId, dstChainId, paramsHash);
    }

    function _buildResolved(
        ERC7683Types.OnchainCrossChainOrder calldata order,
        bytes32 orderId,
        uint256 dstChainId,
        bytes32 paramsHash
    ) internal pure returns (ERC7683Types.ResolvedCrossChainOrder memory resolved) {
        ERC7683Types.Output[] memory maxSpent = new ERC7683Types.Output[](0);
        ERC7683Types.Output[] memory minReceived = new ERC7683Types.Output[](0);

        ERC7683Types.FillInstruction[] memory fills = new ERC7683Types.FillInstruction[](1);
        fills[0] = ERC7683Types.FillInstruction({
            destinationChainId: dstChainId,
            destinationSettler: bytes32(uint256(0)), // set by router/filler
            originData: abi.encode(orderId, paramsHash)
        });

        resolved = ERC7683Types.ResolvedCrossChainOrder({
            user: order.user,
            originChainId: order.originChainId,
            openDeadline: order.openDeadline,
            fillDeadline: order.fillDeadline,
            orderId: orderId,
            maxSpent: maxSpent,
            minReceived: minReceived,
            fillInstructions: fills
        });
    }
}
