// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IAaveOracle} from "@aave/core-v3/contracts/interfaces/IAaveOracle.sol";
import {IPoolAddressesProviderRegistry} from "@aave/core-v3/contracts/interfaces/IPoolAddressesProviderRegistry.sol";
import {IPoolAddressesProvider} from "@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol";
import {IPool} from "@aave/core-v3/contracts/interfaces/IPool.sol";

import {IRevenueReward} from "../interfaces/IRevenueReward.sol";
import {IUserVaultRegistry} from "../interfaces/IUserVaultRegistry.sol";
import {IUserVault} from "../interfaces/IUserVault.sol";

import {CommonChecksLibrary} from "../libraries/CommonChecksLibrary.sol";

/**
 * @title UserVault
 * @author Neverland
 * @notice User vault contract for self-repaying loans
 */
contract UserVault is IUserVault, Initializable {
    using SafeERC20 for IERC20;

    /// @notice UserVaultRegistry contract
    IUserVaultRegistry public userVaultRegistry;
    /// @notice RevenueReward contract
    IRevenueReward public revenueReward;
    /// @notice AAVE PoolAddressesProviderRegistry contract
    IPoolAddressesProviderRegistry public poolAddressesProviderRegistry;

    /// @notice User address
    address public user;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the contract
     * @param _user User address
     * @param _revenueReward RevenueReward address
     * @param _userVaultRegistry UserVaultRegistry address
     * @param _poolAddressesProviderRegistry PoolAddressesProviderRegistry address
     */
    function initialize(
        address _user,
        IRevenueReward _revenueReward,
        IUserVaultRegistry _userVaultRegistry,
        IPoolAddressesProviderRegistry _poolAddressesProviderRegistry
    ) external initializer {
        CommonChecksLibrary.revertIfZeroAddress(address(_userVaultRegistry));
        CommonChecksLibrary.revertIfZeroAddress(address(_poolAddressesProviderRegistry));
        CommonChecksLibrary.revertIfZeroAddress(address(_revenueReward));
        CommonChecksLibrary.revertIfZeroAddress(_user);

        user = _user;
        revenueReward = _revenueReward;
        userVaultRegistry = _userVaultRegistry;
        poolAddressesProviderRegistry = _poolAddressesProviderRegistry;
    }

    /// @inheritdoc IUserVault
    function repayUserDebt(RepayUserDebtParams calldata params) external onlyExecutor {
        getTokenIdsReward(params.tokenIds, params.rewardToken);

        uint256 debtTokenSwapAmount = swapAndVerify(
            params.rewardToken,
            params.rewardTokenAmountToSwap,
            params.debtToken,
            params.aggregatorAddress,
            params.aggregatorData,
            params.poolAddressesProvider,
            params.maxSlippageBps
        );

        repayDebt(params.poolAddressesProvider, params.debtToken, debtTokenSwapAmount);
    }

    /// @inheritdoc IUserVault
    function getTokenIdsReward(uint256[] memory tokenIds, address rewardToken) public onlyExecutor returns (uint256) {
        CommonChecksLibrary.revertIfZeroAddress(rewardToken);

        uint256 rewardTokenTokenBalanceBefore = _getErc20TokenBalance(rewardToken, address(this));

        address[] memory rewardTokens = new address[](1);
        rewardTokens[0] = address(rewardToken);
        uint256 tokenIdsLength = tokenIds.length;
        for (uint256 i = 0; i < tokenIdsLength; ++i) {
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
        address poolAddressesProvider,
        uint256 maxAllowedSlippageBps
    ) public onlyExecutor poolAddressesProviderShouldBeValid(poolAddressesProvider) returns (uint256) {
        CommonChecksLibrary.revertIfZeroAddress(tokenIn);
        CommonChecksLibrary.revertIfZeroAddress(tokenOut);
        CommonChecksLibrary.revertIfZeroAmount(tokenInAmount);
        CommonChecksLibrary.revertIfZeroAddress(aggregator);
        if (maxAllowedSlippageBps > userVaultRegistry.maxSwapSlippageBps()) revert MaxSlippageTooHigh();

        uint256 debtTokenSwapAmount = _swap(tokenIn, tokenInAmount, tokenOut, aggregator, aggregatorData);

        uint256[] memory tokenPricesInUSD_8dec =
            _getTokenPricesInUsd_8dec(tokenIn, tokenOut, IPoolAddressesProvider(poolAddressesProvider));

        // Ensure oracle returned valid non-zero prices for both tokens
        if (tokenPricesInUSD_8dec.length < 2 || tokenPricesInUSD_8dec[0] == 0 || tokenPricesInUSD_8dec[1] == 0) {
            revert GettingAssetPriceFailed();
        }

        _verifySlippage(
            tokenIn,
            tokenInAmount,
            tokenPricesInUSD_8dec[0],
            tokenOut,
            debtTokenSwapAmount,
            tokenPricesInUSD_8dec[1],
            maxAllowedSlippageBps
        );

        return debtTokenSwapAmount;
    }

    /// @inheritdoc IUserVault
    function repayDebt(address poolAddressesProvider, address debtToken, uint256 amount)
        public
        onlyExecutor
        poolAddressesProviderShouldBeValid(poolAddressesProvider)
    {
        address poolAddress = IPoolAddressesProvider(poolAddressesProvider).getPool();
        IERC20(debtToken).safeApprove(poolAddress, amount);
        IPool(poolAddress).repay(debtToken, amount, 2, user);
        IERC20(debtToken).safeApprove(poolAddress, 0);

        emit LoanSelfRepaid(user, address(this), poolAddressesProvider, debtToken, amount);
    }

    /// @inheritdoc IUserVault
    function depositCollateral(address poolAddressesProvider, address debtToken, uint256 amount)
        external
        onlyExecutor
        poolAddressesProviderShouldBeValid(poolAddressesProvider)
    {
        address poolAddress = IPoolAddressesProvider(poolAddressesProvider).getPool();
        IERC20(debtToken).safeApprove(poolAddress, amount);
        IPool(poolAddress).supply(debtToken, amount, user, 0);
        IERC20(debtToken).safeApprove(poolAddress, 0);
    }

    /// @inheritdoc IUserVault
    function recoverERC20(address token, uint256 amount) external onlyExecutorOrUser {
        IERC20(token).safeTransfer(user, amount);
    }

    /// @inheritdoc IUserVault
    function recoverETH(uint256 amount) external onlyExecutorOrUser {
        (bool ok,) = payable(user).call{value: amount}("");
        if (!ok) revert IUserVault.ETHSendFailed();
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
     * @return Amount of tokens swapped out
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
        IERC20(tokenIn).safeApprove(aggregator, tokenInAmount);

        (bool success,) = aggregator.call(aggregatorData);
        if (!success) revert SwapFailed();

        uint256 debtTokenBalanceAfter = _getErc20TokenBalance(tokenOut, address(this));
        uint256 debtTokenSwapAmount = debtTokenBalanceAfter - debtTokenBalanceBefore;

        IERC20(tokenIn).safeApprove(aggregator, 0);

        return debtTokenSwapAmount;
    }

    /**
     * @notice Returns a list of prices from a list of assets addresses
     * @param token1 token1 address
     * @param token2 token2 address
     * @return The prices of the given assets
     */
    function _getTokenPricesInUsd_8dec(address token1, address token2, IPoolAddressesProvider poolAddressesProvider)
        internal
        view
        returns (uint256[] memory)
    {
        address[] memory tokens = new address[](2);
        tokens[0] = token1;
        tokens[1] = token2;

        return IAaveOracle(poolAddressesProvider.getPriceOracle()).getAssetsPrices(tokens);
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

    /**
     * @notice Verifies that the slippage between the desired swap amount and the actual swapped amount is within the allowed slippage
     * @dev Normalizes token amounts to 18 decimals before comparison to handle tokens with different decimals
     * @param tokenA The address of token A (token being swapped from)
     * @param desiredSwapAmountInTokenA The desired amount of token A to swap
     * @param tokenAUnitPriceInUSD_8dec The price of token A in USD with 8 decimals
     * @param tokenB The address of token B (token being swapped to)
     * @param actualSwappedAmountInTokenB The actual amount of token B that was swapped
     * @param tokenBUnitPriceInUSD_8dec The price of token B in USD with 8 decimals
     * @param maxAllowedSlippageBps The maximum allowed slippage in basis points
     */
    function _verifySlippage(
        address tokenA,
        uint256 desiredSwapAmountInTokenA,
        uint256 tokenAUnitPriceInUSD_8dec,
        address tokenB,
        uint256 actualSwappedAmountInTokenB,
        uint256 tokenBUnitPriceInUSD_8dec,
        uint256 maxAllowedSlippageBps
    ) internal view {
        // Get token decimals
        uint8 tokenADecimals = IERC20Metadata(tokenA).decimals();
        uint8 tokenBDecimals = IERC20Metadata(tokenB).decimals();

        uint256 desiredSwapAmountInUsd = desiredSwapAmountInTokenA * tokenAUnitPriceInUSD_8dec / 10 ** tokenADecimals;
        uint256 actualSwapAmountInUsd = actualSwappedAmountInTokenB * tokenBUnitPriceInUSD_8dec / 10 ** tokenBDecimals;

        if (actualSwapAmountInUsd < desiredSwapAmountInUsd) {
            uint256 actualSlippageBps =
                (desiredSwapAmountInUsd - actualSwapAmountInUsd) * 10_000 / desiredSwapAmountInUsd;

            if (actualSlippageBps > maxAllowedSlippageBps) revert SlippageExceeded();
        }
    }

    /*//////////////////////////////////////////////////////////////
                             MODIFIERS
     //////////////////////////////////////////////////////////////*/

    /// @notice Modifier to check if the caller is the executor
    modifier onlyExecutor() {
        if (userVaultRegistry.executor() != msg.sender) {
            revert NotExecutor();
        }
        _;
    }

    /// @notice Modifier to check if the caller is the executor or the user
    modifier onlyExecutorOrUser() {
        if (!(userVaultRegistry.executor() == msg.sender || user == msg.sender)) {
            revert CommonChecksLibrary.UnauthorizedAccess();
        }
        _;
    }

    /// @notice Modifier to check if the pool addresses provider is valid
    modifier poolAddressesProviderShouldBeValid(address poolAddressesProvider) {
        uint256 poolAddressesProviderId =
            poolAddressesProviderRegistry.getAddressesProviderIdByAddress(poolAddressesProvider);
        if (poolAddressesProviderId == 0) revert InvalidPoolAddressesProvider();
        _;
    }
}
