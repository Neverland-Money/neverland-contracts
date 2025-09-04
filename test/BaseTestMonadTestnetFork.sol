// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {BaseTestLocal} from "./BaseTestLocal.sol";

abstract contract BaseTestMonadTestnetFork is BaseTestLocal {
    string internal MONAD_TESTNET_RPC_URL = "https://testnet-rpc.monad.xyz";

    function _testSetup() internal override {
        // fork current block monad testnet
        uint256 monadTestnetFork = vm.createFork(MONAD_TESTNET_RPC_URL);
        vm.selectFork(monadTestnetFork);

        // deploy contracts
        super._testSetup();
    }
}
