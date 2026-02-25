// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "openzeppelin-contracts/access/AccessControl.sol";
import {IDestinationSettler} from "./IDestinationSettler.sol";
import {MeshHub} from "../mesh/MeshHub.sol";
import {MeshTypes} from "../mesh/MeshTypes.sol";
import {IMeshAdapter} from "../mesh/IMeshAdapter.sol";

contract EtrnaMeshDestinationSettler is IDestinationSettler, AccessControl {
    bytes32 public constant FILLER_ROLE = keccak256("FILLER_ROLE");

    MeshHub public immutable meshHub;

    event FillExecuted(bytes32 indexed orderId, address indexed filler, bytes originData, bytes fillerData);

    constructor(address _meshHub, address admin) {
        require(_meshHub != address(0), "meshHub=0");
        require(admin != address(0), "admin=0");
        meshHub = MeshHub(_meshHub);
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(FILLER_ROLE, admin);
    }

    function fill(bytes32 orderId, bytes calldata originData, bytes calldata fillerData) external override onlyRole(FILLER_ROLE) {
        (bytes32 intentId, ) = abi.decode(originData, (bytes32, bytes32));
        MeshTypes.Intent memory intent = meshHub.getIntent(intentId);
        require(intent.creator != address(0), "unknown intent");

        bytes4 selector = bytes4(keccak256(abi.encodePacked(uint256(intent.actionType))));
        address adapter = meshHub.adapters(intent.dstChainId, selector);
        require(adapter != address(0), "no adapter");

        IMeshAdapter(adapter).execute(intentId, fillerData);

        emit FillExecuted(orderId, msg.sender, originData, fillerData);
    }
}
