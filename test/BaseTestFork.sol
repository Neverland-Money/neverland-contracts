// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {BaseTest} from "./BaseTest.sol";

abstract contract BaseTestFork is BaseTest {
    string internal MONAD_TESTNET_RPC_URL = "https://testnet-rpc.monad.xyz";
    uint256 internal MONAD_TESTNET_BLOCK_NUMBER = 30_591_458;

    function _testSetup() internal override {
        uint256 monadTestnetFork = vm.createFork(MONAD_TESTNET_RPC_URL, MONAD_TESTNET_BLOCK_NUMBER);
        vm.selectFork(monadTestnetFork);
    }
}
