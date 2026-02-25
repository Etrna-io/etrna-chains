// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {IdentityProviderRegistry} from "../src/identity/IdentityProviderRegistry.sol";
import {IdentityGuard} from "../src/identity/IdentityGuard.sol";

contract DeployIdentity is Script {
    function run() external {
        address admin = vm.envAddress("ADMIN");

        vm.startBroadcast();

        IdentityProviderRegistry registry = new IdentityProviderRegistry(admin);
        IdentityGuard guard = new IdentityGuard(address(registry));

        console2.log("IdentityProviderRegistry deployed:", address(registry));
        console2.log("IdentityGuard deployed:", address(guard));
        console2.log("  admin:", admin);

        vm.stopBroadcast();
    }
}
