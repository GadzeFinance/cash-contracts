// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Test, console, stdError} from "forge-std/Test.sol";
import {TopUpWalletFactory, TopUpWallet, Ticket, MessagingFee, OFTReceipt, SendParam} from "../../src/top-up/TopUpWalletFactory.sol";
import {UUPSProxy} from "../../src/UUPSProxy.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {UUPSProxy} from "../../src/UUPSProxy.sol";

contract TopUpTest is Test {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant DEFAULT_ADMIN_ROLE = bytes32(0);
    address owner = makeAddr("owner");
    address alice = makeAddr("alice");

    TopUpWalletFactory factory;
    TopUpWallet aliceWallet;
    TopUpWallet bobWallet;

    // Ethereum
    ERC20 usdc = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    ERC20 usdt = ERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7);
    ERC20 weth = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    // https://stargateprotocol.gitbook.io/stargate/v/v2-developer-docs/technical-reference/mainnet-contracts#scroll
    address stargateUsdcPool = 0xc026395860Db2d07ee33e05fE50ed7bD583189C7;
    address stargateUsdtPool = 0x933597a323Eb81cAe705C5bC29985172fd5A3973;
    // https://docs.layerzero.network/v2/developers/evm/technical-reference/deployed-contracts
    uint32 scrollDestEid = 30214;
    uint48 accessControlDelay = 100;

    function setUp() public {
        vm.createSelectFork("https://rpc.ankr.com/eth");

        vm.startPrank(owner);
        address walletImpl = address(new TopUpWallet(address(weth)));
        address factoryImpl = address(new TopUpWalletFactory(scrollDestEid));

        factory = TopUpWalletFactory(
            address(new UUPSProxy(
                factoryImpl, 
                abi.encodeWithSelector(
                    TopUpWalletFactory.initialize.selector, 
                    accessControlDelay,
                    walletImpl
                ))
            )
        );
        
        address[] memory assets = new address[](2);
        assets[0] = address(usdc);
        assets[1] = address(usdt);

        address[] memory pools = new address[](2);
        pools[0] = stargateUsdcPool;
        pools[1] = stargateUsdtPool;

        vm.expectEmit(true, true, true, true);
        emit TopUpWalletFactory.StargatePoolSet(assets, pools);
        factory.setStargatePool(assets, pools);

        factory.deployWallet(keccak256("alice"));
        factory.deployWallet(keccak256("bob"));

        aliceWallet = TopUpWallet(payable(factory.getWalletAddress(keccak256("alice"))));
        bobWallet = TopUpWallet(payable(factory.getWalletAddress(keccak256("bob"))));

        vm.stopPrank();
    }
}