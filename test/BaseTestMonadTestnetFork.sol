// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BaseTest} from "./BaseTest.sol";

abstract contract BaseTestMonadTestnetFork is BaseTest {
    string internal MONAD_TESTNET_RPC_URL = "https://testnet-rpc.monad.xyz";

    function _testSetup() internal virtual override {
        // fork current block monad testnet
        uint256 monadTestnetFork = vm.createFork(MONAD_TESTNET_RPC_URL);
        vm.selectFork(monadTestnetFork);

        // deploy contracts
        super._testSetup();
    }
}
