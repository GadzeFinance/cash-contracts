// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {TopUpWalletFactory, TopUpWallet} from "../../src/top-up/TopUpWalletFactory.sol";
import {UUPSProxy} from "../../src/UUPSProxy.sol";

contract DeployTopupWallet is Script {
    address weth  = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    uint32 scrollDestEid = 30214;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        address walletImpl = address(new TopUpWallet(weth));
        address factoryImpl = address(new TopUpWalletFactory(scrollDestEid));

        TopUpWalletFactory factory = TopUpWalletFactory(
            address(new UUPSProxy(
                factoryImpl, 
                abi.encodeWithSelector(
                    TopUpWalletFactory.initialize.selector, 
                    100,
                    walletImpl
                ))
            )
        );

        vm.stopBroadcast();
    }
}