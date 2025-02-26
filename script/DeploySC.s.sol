// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {StableCoin} from "src/StableCoin.sol";
import {SCEngine} from "src/SCEngine.sol";

contract DeploySC is Script {
    function run() external returns (StableCoin, SCEngine) {
        vm.startBroadcast();
        StableCoin coin = new StableCoin();
        // SCEngine engine = new SCEngine();
        vm.stopBroadcast();
    }
}
