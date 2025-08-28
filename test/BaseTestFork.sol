// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {BaseTest} from "./BaseTest.sol";

abstract contract BaseTestFork is BaseTest {
    string internal MONAD_TESTNET_RPC_URL = "https://testnet-rpc.monad.xyz";
}
