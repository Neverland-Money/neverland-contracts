// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "../BaseTestFork.sol";

contract UserVaultTest is BaseTestFork {
    function _testSetup() internal override {}

    function testRepayDebt() public {
        // chain data
        uint256 MONAD_TESTNET_BLOCK_NUMBER = 30753577;
        address user = 0x0000B06460777398083CB501793a4d6393900000;
        uint256 userDebtUSDTWei = 8500000;
        address USDT = 0x88b8E2161DEDC77EF4ab7585569D2415a1C1055D;
        address variableDebtUSDT = 0x20838Ac96e96049C844f714B58aaa0cb84414d60;

        // fork
        //        uint256 monadTestnetFork = vm.createFork(MONAD_TESTNET_RPC_URL, MONAD_TESTNET_BLOCK_NUMBER);
        //        vm.selectFork(monadTestnetFork);

        // arrange

        // act

        //emit log_named_address("pool address", pool1);
    }
}
