// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {UserSafe} from "../user-safe/UserSafe.sol";

contract UserSafeV2Mock is UserSafe {
    constructor(
        address __cashDataProvider,
        address __etherFiRecoverySigner,
        address __thirdPartyRecoverySigner
    )
        UserSafe(
            __cashDataProvider,
            __etherFiRecoverySigner,
            __thirdPartyRecoverySigner
        )
    {}

    function version() external pure returns (uint256) {
        return 2;
    }
}
