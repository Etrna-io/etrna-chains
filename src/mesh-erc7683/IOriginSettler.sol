// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {ERC7683Types} from "./ERC7683Types.sol";

interface IOriginSettler {
    event Open(bytes32 indexed orderId, ERC7683Types.ResolvedCrossChainOrder resolvedOrder);
    function open(ERC7683Types.OnchainCrossChainOrder calldata order) external;
    function resolve(ERC7683Types.OnchainCrossChainOrder calldata order)
        external view returns (ERC7683Types.ResolvedCrossChainOrder memory);
}
