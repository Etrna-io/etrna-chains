// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/etrnapass/EtrnaPass.sol";

/**
 * Usage:
 *  forge script scripts/DeployEtrnaPass.s.sol:DeployEtrnaPass --rpc-url $RPC_URL --broadcast --verify
 */
contract DeployEtrnaPass is Script {
    function run() external returns (EtrnaPass pass) {
        uint256 pk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address admin = vm.envAddress("ETRNAPASS_ADMIN");
        string memory name_ = vm.envOr("ETRNAPASS_NAME", string("EtrnaPass"));
        string memory symbol_ = vm.envOr("ETRNAPASS_SYMBOL", string("ETRNAPASS"));
        string memory baseURI_ = vm.envOr("ETRNAPASS_BASE_URI", string("https://assets.etrna.com/ipfs/REPLACE_WITH_METADATA_CID/"));
        address royaltyReceiver = vm.envOr("ETRNAPASS_ROYALTY_RECEIVER", admin);
        uint96 royaltyBps = uint96(vm.envOr("ETRNAPASS_ROYALTY_BPS", uint256(500))); // 5%

        vm.startBroadcast(pk);
        pass = new EtrnaPass(admin, name_, symbol_, baseURI_, royaltyReceiver, royaltyBps);
        vm.stopBroadcast();
    }
}
