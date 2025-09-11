// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

import "../BaseTestMonadTestnetFork.sol";
import {HarnessFactory} from "../harness/HarnessFactory.sol";

import {BaseTestLocal} from "../BaseTestLocal.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPoolAddressesProvider} from "@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol";
import {IPoolAddressesProviderRegistry} from "@aave/core-v3/contracts/interfaces/IPoolAddressesProviderRegistry.sol";
import {IPool} from "@aave/core-v3/contracts/interfaces/IPool.sol";

import {UserVaultHarness} from "../harness/UserVaultHarness.sol";
import {UserVaultRegistry} from "../../src/self-repaying-loans/UserVaultRegistry.sol";

contract UserVaultForkTest is BaseTestMonadTestnetFork, BaseTestLocal {
    HarnessFactory harnessFactory;

    // testnet chain data
    address poolAddressesProviderRegistryAddress = 0x2F7ae2EebE5Dd10BfB13f3fB2956C7b7FFD60A5F;
    address poolAddressesProviderAddress = 0x0bAe833178A7Ef0C5b47ca10D844736F65CBd499;

    address USDC = 0xf817257fed379853cDe0fa4F97AB987181B1E5Ea;
    address WETH = 0xB5a30b0FDc5EA94A52fDc42e3E9760Cb8449Fb37;
    address WBTC = 0xcf5a6076cfa32686c0Df13aBaDa2b40dec133F1d;
    address WMON = 0x760AfE86e5de5fa0Ee542fc7B7B713e1c5425701;
    address USDT = 0x88b8E2161DEDC77EF4ab7585569D2415a1C1055D;

    IPoolAddressesProviderRegistry _poolAddressesProviderRegistry;
    IPoolAddressesProvider _poolAddressesProvider;

    function _testSetup() internal override(BaseTestMonadTestnetFork, BaseTestLocal) {
        BaseTestMonadTestnetFork._testSetup();
        BaseTestLocal._testSetup();
    }

    function _setUp() internal override {
        // mint ethereum
        address[] memory usersToMintEth = new address[](1);
        usersToMintEth[0] = address(this);

        uint256[] memory ethAmountToMint = new uint256[](1);
        ethAmountToMint[0] = 1 ether;

        mintETH(usersToMintEth, ethAmountToMint);

        harnessFactory = new HarnessFactory();
        _poolAddressesProviderRegistry = IPoolAddressesProviderRegistry(poolAddressesProviderRegistryAddress);
        _poolAddressesProvider = IPoolAddressesProvider(poolAddressesProviderAddress);
    }

    function testRepayDebt() public {
        vm.skip(true);

        // chain data
        // uint256 MONAD_TESTNET_BLOCK_NUMBER = 30753577;
        address poolUser = 0x0000B06460777398083CB501793a4d6393900000;
        uint256 userDebtUSDTWei = 8500000;
        // address variableDebtUSDT = 0x20838Ac96e96049C844f714B58aaa0cb84414d60;

        // arrange
        (UserVaultHarness _userVault,,,) =
            harnessFactory.createUserVaultHarness(poolUser, revenueReward, _poolAddressesProviderRegistry, automation);

        mintErc20Token(USDT, address(_userVault), userDebtUSDTWei);

        // act
        vm.prank(automation);
        _userVault.repayDebt(poolAddressesProviderAddress, USDT, userDebtUSDTWei);

        // assert
        // expect no revert
    }

    function testAaveOracle() public {
        vm.skip(true);

        // chain data
        address poolUser = 0x0000B06460777398083CB501793a4d6393900000;

        // arrange

        (UserVaultHarness _userVault,,,) =
            harnessFactory.createUserVaultHarness(poolUser, revenueReward, _poolAddressesProviderRegistry, automation);

        // act
        address[] memory assets = new address[](5);
        assets[0] = USDC;
        assets[1] = WETH;
        assets[2] = WBTC;
        assets[3] = WMON;
        assets[4] = USDT;

        uint256[] memory prices1 = _userVault.exposed_getAssetsPrices(USDC, WETH, _poolAddressesProvider);
        uint256[] memory prices2 = _userVault.exposed_getAssetsPrices(WBTC, WMON, _poolAddressesProvider);
        uint256[] memory prices3 = _userVault.exposed_getAssetsPrices(USDT, address(0), _poolAddressesProvider);

        // assert
        emit log_named_uint("USDC", prices1[0]);
        emit log_named_uint("WETH", prices1[1]);
        emit log_named_uint("WBTC", prices2[0]);
        emit log_named_uint("WMON", prices2[1]);
        emit log_named_uint("USDT", prices3[0]);
        emit log_named_uint("address(0)", prices3[1]);
    }
}
