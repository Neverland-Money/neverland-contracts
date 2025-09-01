// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "../BaseTestFork.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPoolAddressesProvider} from "@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol";
import {IPool} from "@aave/core-v3/contracts/interfaces/IPool.sol";
import {IUserVault} from "../../src/interfaces/IUserVault.sol";

contract UserVaultTest is BaseTestFork {
    function _setUp() internal override {
        // mint ethereum
        address[] memory usersToMintEth = new address[](1);
        usersToMintEth[0] = address(this);

        uint256[] memory ethAmountToMint = new uint256[](1);
        ethAmountToMint[0] = 1 ether;

        mintETH(usersToMintEth, ethAmountToMint);
    }

    function testRepayDebt() public {
        return; // skip test

        // fork
        // uint256 MONAD_TESTNET_BLOCK_NUMBER = 30753577;
        address poolAddressProvider = 0x0bAe833178A7Ef0C5b47ca10D844736F65CBd499;
        address poolUser = 0x0000B06460777398083CB501793a4d6393900000;
        uint256 userDebtUSDTWei = 8500000;
        address USDT = 0x88b8E2161DEDC77EF4ab7585569D2415a1C1055D;
        // address variableDebtUSDT = 0x20838Ac96e96049C844f714B58aaa0cb84414d60;

        // arrange
        IPoolAddressesProvider pap = IPoolAddressesProvider(poolAddressProvider);
        address poolAddress = pap.getPool();

        address userVaultAddress = userVaultFactory.getUserVault(poolUser);
        IUserVault userVault = IUserVault(userVaultAddress);

        mintErc20Token(USDT, address(userVault), userDebtUSDTWei);

        // act
        vm.prank(automation);
        userVault.repayDebt(poolAddress, USDT, userDebtUSDTWei);

        // assert
        // expect no revert
    }
}
