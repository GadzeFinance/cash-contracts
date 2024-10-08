// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
interface IWETH {
    function deposit() external payable;
}

contract TopUpWallet {
    using SafeERC20 for IERC20;
    address owner;
    address immutable weth;

    error AlreadyInitialized();

    constructor(address _weth) {
        weth = _weth;
    }

    function initialize(address _owner) external {
        if (owner != address(0)) revert AlreadyInitialized();
        owner = _owner;
    }

    function flushTokens(address[] memory tokens) external {        
        for (uint256 i = 0; i < tokens.length; ) {
            uint256 balance = IERC20(tokens[i]).balanceOf(address(this));
            if (balance != 0) IERC20(tokens[i]).safeTransfer(owner, balance);
            unchecked {
                ++i;
            }
        }
    }

    receive() external payable {
        IWETH(weth).deposit{value: msg.value}();
    }
}