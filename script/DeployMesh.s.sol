// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";

import {MeshHub} from "../src/mesh/MeshHub.sol";
import {EtrnaMeshOriginSettler} from "../src/mesh-erc7683/EtrnaMeshOriginSettler.sol";
import {EtrnaMeshDestinationSettler} from "../src/mesh-erc7683/EtrnaMeshDestinationSettler.sol";

/// @title DeployMesh — MeshHub + ERC-7683 Settlers
/// @notice Deploys MeshHub, OriginSettler, and DestinationSettler with wiring.
///
/// Environment variables required:
///   ADMIN — ecosystem admin / initial router backend address
///
/// Optional:
///   ROUTER_BACKEND — off-chain router address (defaults to ADMIN)
///
/// Usage:
///   forge script script/DeployMesh.s.sol --rpc-url $RPC --broadcast --verify
contract DeployMesh is Script {
    function run() external {
        address admin = vm.envAddress("ADMIN");
        address routerBackend = vm.envOr("ROUTER_BACKEND", admin);

        vm.startBroadcast();

        // 1. Deploy MeshHub with router backend
        MeshHub meshHub = new MeshHub(routerBackend);

        // 2. Deploy ERC-7683 settlers wired to MeshHub
        EtrnaMeshOriginSettler originSettler = new EtrnaMeshOriginSettler(address(meshHub));
        EtrnaMeshDestinationSettler destinationSettler = new EtrnaMeshDestinationSettler(address(meshHub), admin);

        // 3. Transfer MeshHub ownership to admin (deployer is initial owner)
        meshHub.transferOwnership(admin);

        vm.stopBroadcast();

        console2.log("=== MESH DEPLOYMENT ===");
        console2.log("MeshHub:", address(meshHub));
        console2.log("OriginSettler:", address(originSettler));
        console2.log("DestinationSettler:", address(destinationSettler));
        console2.log("RouterBackend:", routerBackend);
        console2.log("Owner:", admin);
    }
}
