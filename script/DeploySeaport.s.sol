// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";

import {EtrnaZone} from "../src/seaport/EtrnaZone.sol";

/// @title DeploySeaport — EtrnaZone
/// @notice Deploys the Seaport zone with IdentityGuard integration.
///
/// Environment variables required:
///   ADMIN          — ecosystem admin address
///   IDENTITY_GUARD — deployed IdentityGuard address
///
/// Optional:
///   SEAPORT_PROOF_TYPE — proof type for zone validation (defaults to keccak256("ETRNA_SEAPORT"))
///
/// Usage:
///   forge script script/DeploySeaport.s.sol --rpc-url $RPC --broadcast --verify
contract DeploySeaport is Script {
    function run() external {
        address admin = vm.envAddress("ADMIN");
        address identityGuard = vm.envAddress("IDENTITY_GUARD");
        bytes32 proofType = vm.envOr("SEAPORT_PROOF_TYPE", keccak256("ETRNA_SEAPORT"));

        vm.startBroadcast();

        // Deploy EtrnaZone with IdentityGuard and proof type
        EtrnaZone zone = new EtrnaZone(identityGuard, proofType);

        vm.stopBroadcast();

        console2.log("=== SEAPORT DEPLOYMENT ===");
        console2.log("EtrnaZone:", address(zone));
        console2.log("IdentityGuard:", identityGuard);
        console2.log("Admin:", admin);
    }
}
