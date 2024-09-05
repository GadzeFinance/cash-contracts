// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "../../src/preorder/Order.sol";

struct Proxy {
    address admin;
    address implementation;
    address proxy;
}

contract DeployOrder is Script {
    // Storages the addresses for the proxy deploy of the PreOrder contract
    Proxy OrderAddresses;

    // TODO: This is the mainnet contract controller gnosis. Be sure to change to the pre-order gnosis  address
    address GnosisSafe;
    address weEthToken = 0x07aCE651BA09318C6DfEeFc56066585780f62F18;

    string baseURI =
        "https://etherfi-membership-metadata.s3.ap-southeast-1.amazonaws.com/cash-metadata/";

    function run() public {
        // Pulling deployer info from the environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);

        GnosisSafe = deployerAddress;
        // Start broadcast with deployer as the signer
        vm.startBroadcast(deployerPrivateKey);

        // Deploy the implementation contract

        uint32 MILLION = 1_000_000;

        // Configuring the tiers
        Order.TierConfig memory whales = Order.TierConfig({
            costWei: 10 ether,
            maxSupply: MILLION
        });
        Order.TierConfig memory chads = Order.TierConfig({
            costWei: 1 ether,
            maxSupply: MILLION
        });
        Order.TierConfig memory wojak = Order.TierConfig({
            costWei: 0.1 ether,
            maxSupply: MILLION
        });
        Order.TierConfig memory pepe = Order.TierConfig({
            costWei: 0.01 ether,
            maxSupply: MILLION
        });

        // TODO: Add more tiers when the tiers are offically set
        Order.TierConfig[] memory tiers = new Order.TierConfig[](4);
        tiers[0] = whales;
        tiers[1] = chads;
        tiers[2] = wojak;
        tiers[3] = pepe;

        // Deploy the implementation contract
        OrderAddresses.implementation = address(new Order());
        OrderAddresses.proxy = address(
            new ERC1967Proxy(OrderAddresses.implementation, "")
        );

        Order order = Order(payable(OrderAddresses.proxy));
        order.initialize(
            deployerAddress,
            GnosisSafe,
            deployerAddress,
            weEthToken,
            baseURI,
            tiers
        );
        vm.stopBroadcast();

        console.log(
            "Order implementation deployed at: ",
            OrderAddresses.implementation
        );
        console.log("Order proxy deployed at: ", OrderAddresses.proxy);
        console.log("Order owner: ", deployerAddress);
    }
}
