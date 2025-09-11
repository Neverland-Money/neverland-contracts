// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {IPoolAddressesProviderRegistry} from "@aave/core-v3/contracts/interfaces/IPoolAddressesProviderRegistry.sol";
import {IPoolAddressesProvider} from "@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol";
import {IPool} from "@aave/core-v3/contracts/interfaces/IPool.sol";

import {IRevenueReward} from "../interfaces/IRevenueReward.sol";
import {IUserVaultRegistry} from "../interfaces/IUserVaultRegistry.sol";
import {IUserVault} from "../interfaces/IUserVault.sol";
import {CommonChecksLibrary} from "../libraries/CommonChecksLibrary.sol";
import {IPoolAddressesProvider} from "@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol";
import {IAaveOracle} from "@aave/core-v3/contracts/interfaces/IAaveOracle.sol";

contract UserVault is IUserVault, Initializable {
    IUserVaultRegistry userVaultRegistry;
    IRevenueReward revenueReward;
    IPoolAddressesProviderRegistry poolAddressProviderRegistry;

    address user;

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _user,
        IRevenueReward _revenueReward,
        IUserVaultRegistry _userVaultRegistry,
        IPoolAddressesProviderRegistry _poolAddressProviderRegistry
    ) external initializer {
        CommonChecksLibrary.revertIfZeroAddress(address(_userVaultRegistry));
        CommonChecksLibrary.revertIfZeroAddress(address(_poolAddressProviderRegistry));
        CommonChecksLibrary.revertIfZeroAddress(address(_revenueReward));
        CommonChecksLibrary.revertIfZeroAddress(_user);

        user = _user;
        revenueReward = _revenueReward;
        userVaultRegistry = _userVaultRegistry;
        poolAddressProviderRegistry = _poolAddressProviderRegistry;
    }

    /// @inheritdoc IUserVault
    function repayUserDebt(RepayUserDebtParams calldata params) public onlyExecutor {
        getTokenIdsReward(params.tokenIds, params.rewardToken);

        uint256 debtTokenSwapAmount = swapAndVerify(
            params.rewardToken,
            params.rewardTokenAmountToSwap,
            params.debtToken,
            params.aggregatorAddress,
            params.aggregatorData,
            params.poolAddressProvider,
            params.maxSlippageBps
        );

        repayDebt(params.poolAddressProvider, params.debtToken, debtTokenSwapAmount);

        emit LoanSelfRepaid(user, address(this), params.poolAddressProvider, params.debtToken, debtTokenSwapAmount);
    }

    /// @inheritdoc IUserVault
    function getTokenIdsReward(uint256[] memory tokenIds, address rewardToken) public onlyExecutor returns (uint256) {
        CommonChecksLibrary.revertIfZeroAddress(rewardToken);

        uint256 rewardTokenTokenBalanceBefore = _getErc20TokenBalance(rewardToken, address(this));

        address[] memory rewardTokens = new address[](1);
        rewardTokens[0] = address(rewardToken);
        for (uint256 i = 0; i < tokenIds.length; i++) {
            if (revenueReward.tokenRewardReceiver(tokenIds[i]) != address(this)) {
                revert InvalidUserVaultForToken();
            }
            revenueReward.getReward(tokenIds[i], rewardTokens);
        }

        uint256 rewardTokenTokenBalanceAfter = _getErc20TokenBalance(rewardToken, address(this));
        uint256 rewardTokenAmount = rewardTokenTokenBalanceAfter - rewardTokenTokenBalanceBefore;
        return rewardTokenAmount;
    }

    /// @inheritdoc IUserVault
    function swapAndVerify(
        address tokenIn,
        uint256 tokenInAmount,
        address tokenOut,
        address aggregator,
        bytes memory aggregatorData,
        address poolAddressProvider,
        uint256 maxAllowedSlippageBps
    ) public onlyExecutor poolAddressProviderShouldBeValid(poolAddressProvider) returns (uint256) {
        CommonChecksLibrary.revertIfZeroAddress(tokenIn);
        CommonChecksLibrary.revertIfZeroAddress(tokenOut);
        CommonChecksLibrary.revertIfZeroAmount(tokenInAmount);
        CommonChecksLibrary.revertIfZeroAddress(aggregator);
        if (maxAllowedSlippageBps > userVaultRegistry.maxSwapSlippageBps()) revert MaxSlippageTooHigh();

        uint256 debtTokenSwapAmount = _swap(tokenIn, tokenInAmount, tokenOut, aggregator, aggregatorData);

        uint256[] memory tokenPricesInUSD_8dec =
            _getTokenPricesInUsd_8dec(tokenIn, tokenOut, IPoolAddressesProvider(poolAddressProvider));
        _verifySlippage(
            tokenInAmount,
            tokenPricesInUSD_8dec[0],
            debtTokenSwapAmount,
            tokenPricesInUSD_8dec[1],
            maxAllowedSlippageBps
        );

        return debtTokenSwapAmount;
    }

    /// @inheritdoc IUserVault
    function repayDebt(address poolAddressProvider, address debtToken, uint256 amount)
        public
        onlyExecutor
        poolAddressProviderShouldBeValid(poolAddressProvider)
    {
        address poolAddress = IPoolAddressesProvider(poolAddressProvider).getPool();
        IERC20(debtToken).approve(poolAddress, amount);
        IPool(poolAddress).repay(debtToken, amount, 2, user);
    }

    /// @inheritdoc IUserVault
    function depositCollateral(address poolAddressProvider, address debtToken, uint256 amount)
        public
        onlyExecutor
        poolAddressProviderShouldBeValid(poolAddressProvider)
    {
        address poolAddress = IPoolAddressesProvider(poolAddressProvider).getPool();
        IERC20(debtToken).approve(poolAddress, amount);
        IPool(poolAddress).supply(debtToken, amount, user, 0);
    }

    /// @inheritdoc IUserVault
    function recoverERC20(address token, uint256 amount) public onlyExecutorOrUser {
        IERC20(token).transfer(user, amount);
    }

    /// @inheritdoc IUserVault
    function recoverETH(uint256 amount) public onlyExecutorOrUser {
        payable(user).transfer(amount);
    }

    /*//////////////////////////////////////////////////////////////
                            HELPERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Swaps a specified token using a given aggregator contract.
     * @param tokenIn The address of the token swapped in.
     * @param tokenInAmount Amount needed to swap tokens.
     * @param tokenOut The address of the token swapped out.
     * @param aggregator The address of the swap aggregator contract to use for performing the swap.
     * @param aggregatorData The calldata required by the aggregator contract for the swap execution.
     */
    function _swap(
        address tokenIn,
        uint256 tokenInAmount,
        address tokenOut,
        address aggregator,
        bytes memory aggregatorData
    ) internal returns (uint256) {
        uint256 debtTokenBalanceBefore = _getErc20TokenBalance(tokenOut, address(this));

        if (!userVaultRegistry.isSupportedAggregator(aggregator)) {
            revert AggregatorNotSupported();
        }
        IERC20(tokenIn).approve(aggregator, tokenInAmount);
        (bool success,) = aggregator.call(aggregatorData);

        if (!success) revert SwapFailed();

        uint256 debtTokenBalanceAfter = _getErc20TokenBalance(tokenOut, address(this));
        uint256 debtTokenSwapAmount = debtTokenBalanceAfter - debtTokenBalanceBefore;

        return debtTokenSwapAmount;
    }

    /**
     * @notice Returns a list of prices from a list of assets addresses
     * @param token1 token1 address
     * @param token2 token2 address
     * @return The prices of the given assets
     */
    function _getTokenPricesInUsd_8dec(address token1, address token2, IPoolAddressesProvider poolAddressProvider)
        internal
        view
        returns (uint256[] memory)
    {
        address[] memory tokens = new address[](2);
        tokens[0] = token1;
        tokens[1] = token2;

        return IAaveOracle(poolAddressProvider.getPriceOracle()).getAssetsPrices(tokens);
    }

    /**
     * @notice Gets the balance of an ERC20 token for a specified account
     * @param erc20Token The address of the ERC20 token
     * @param account The address of the account to check balance for
     * @return The balance of the ERC20 token for the specified account
     */
    function _getErc20TokenBalance(address erc20Token, address account) internal view returns (uint256) {
        return IERC20(erc20Token).balanceOf(account);
    }

    /*//////////////////////////////////////////////////////////////
                            CALCULATIONS
    //////////////////////////////////////////////////////////////*/

    function _verifySlippage(
        uint256 desiredSwapAmountInTokenA,
        uint256 tokenAUnitPriceInUSD_8dec,
        uint256 actualSwapedAmountInTokenB,
        uint256 tokenBUnitPriceInUSD_8dec,
        uint256 maxAllowedSlippageBps
    ) internal pure {
        uint256 desiredSwapAmountInUsd = desiredSwapAmountInTokenA * tokenAUnitPriceInUSD_8dec;
        uint256 actualSwapAmountInUsd = actualSwapedAmountInTokenB * tokenBUnitPriceInUSD_8dec;

        if (actualSwapAmountInUsd < desiredSwapAmountInUsd) {
            uint256 actualSlippageBps =
                (desiredSwapAmountInUsd - actualSwapAmountInUsd) * 10_000 / desiredSwapAmountInUsd;

            if (actualSlippageBps > maxAllowedSlippageBps) revert SlippageExceeded();
        }
    }

    /*//////////////////////////////////////////////////////////////
                             MODIFIERS
     //////////////////////////////////////////////////////////////*/

    modifier onlyExecutor() {
        if (userVaultRegistry.executor() != msg.sender) {
            revert NotExecutor();
        }
        _;
    }

    modifier onlyExecutorOrUser() {
        if (userVaultRegistry.executor() != msg.sender || user != msg.sender) {
            revert CommonChecksLibrary.UnauthorizedAccess();
        }
        _;
    }

    modifier poolAddressProviderShouldBeValid(address poolAddressProvider) {
        uint256 poolAddressProviderId = poolAddressProviderRegistry.getAddressesProviderIdByAddress(poolAddressProvider);
        if (poolAddressProviderId == 0) revert InvalidPoolAddressProvider();
        _;
    }
}
