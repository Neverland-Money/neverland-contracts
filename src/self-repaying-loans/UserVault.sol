// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {IAaveOracle} from "@aave/core-v3/contracts/interfaces/IAaveOracle.sol";
import {IPool} from "@aave/core-v3/contracts/interfaces/IPool.sol";

import {IRevenueReward} from "../interfaces/IRevenueReward.sol";
import {IUserVaultRegistry} from "../interfaces/IUserVaultRegistry.sol";
import {IUserVault} from "../interfaces/IUserVault.sol";
import {CommonChecksLibrary} from "../libraries/CommonChecksLibrary.sol";

contract UserVault is IUserVault, Initializable {
    IUserVaultRegistry userVaultRegistry;
    IAaveOracle aaveOracle;
    IRevenueReward revenueReward;
    address user;

    constructor() {
        _disableInitializers();
    }

    function initialize(
        IUserVaultRegistry _userVaultRegistry,
        IAaveOracle _aaveOracle,
        IRevenueReward _revenueReward,
        address _user
    ) external initializer {
        CommonChecksLibrary.revertIfZeroAddress(address(_userVaultRegistry));
        CommonChecksLibrary.revertIfZeroAddress(address(_aaveOracle));
        CommonChecksLibrary.revertIfZeroAddress(address(_revenueReward));
        CommonChecksLibrary.revertIfZeroAddress(_user);

        userVaultRegistry = _userVaultRegistry;
        aaveOracle = _aaveOracle;
        revenueReward = _revenueReward;
        user = _user;
    }

    function repayUserDebt(RepayUserDebtParams calldata params) public onlyExecutor {
        // basic checks
        CommonChecksLibrary.revertIfZeroAddress(params.debtToken);
        CommonChecksLibrary.revertIfZeroAddress(params.poolAddress);
        // limit slippagePercent: read from registry value

        // get rewards
        uint256 rewardTokenAmount = _getTokenIdsReward(params.tokenIds, params.rewardToken);
        if (rewardTokenAmount < 0) revert NegativeRewardAmount();

        // swap
        uint256 debtTokenSwapAmount =
            _swap(params.rewardToken, params.rewardTokenAmountToSwap, params.aggregatorAddress, params.aggregatorData);
        if (debtTokenSwapAmount < 0) revert NegativeSwapAmount();

        // verify slippage
        uint256[] memory tokenPricesInUSD_8dec = _getTokenPricesInUsd_8dec(params.rewardToken, params.debtToken);
        _verifySlippage(
            params.rewardTokenAmountToSwap,
            tokenPricesInUSD_8dec[0],
            debtTokenSwapAmount,
            tokenPricesInUSD_8dec[1],
            params.maxSlippageBps
        );

        // repay
        _repayDebt(params.poolAddress, params.debtToken, debtTokenSwapAmount);

        emit LoanSelfRepaid(user, address(this), params.poolAddress, params.debtToken, debtTokenSwapAmount);
    }

    function depositCollateral(address poolAddress, address debtToken, uint256 amount) public onlyExecutor {
        IERC20(debtToken).approve(poolAddress, amount);
        IPool(poolAddress).supply(debtToken, amount, user, 0);
    }

    function recoverERC20(address token, uint256 amount) public onlyExecutor {
        IERC20(token).transfer(user, amount);
    }

    function recoverETH(uint256 amount) public onlyExecutor {
        payable(user).transfer(amount);
    }

    /*//////////////////////////////////////////////////////////////
                            HELPERS
    //////////////////////////////////////////////////////////////*/

    function _getTokenIdsReward(uint256[] memory tokenIds, address rewardToken) internal returns (uint256) {
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

    /**
     * @notice Swaps a specified token using a given aggregator contract.
     * @param tokenIn The address of the token to be swapped.
     * @param tokenInAmount Amount needed to swap tokens.
     * @param aggregator The address of the swap aggregator contract to use for performing the swap.
     * @param aggregatorData The calldata required by the aggregator contract for the swap execution.
     */
    function _swap(address tokenIn, uint256 tokenInAmount, address aggregator, bytes memory aggregatorData)
        internal
        returns (uint256)
    {
        uint256 debtTokenBalanceBefore = _getErc20TokenBalance(tokenIn, address(this));

        if (!userVaultRegistry.isSupportedAggregator(aggregator)) {
            revert AggregatorNotSupported();
        }
        IERC20(tokenIn).approve(aggregator, tokenInAmount);
        (bool success,) = aggregator.call(aggregatorData);

        if (!success) revert SwapFailed();

        uint256 debtTokenBalanceAfter = _getErc20TokenBalance(tokenIn, address(this));
        uint256 debtTokenSwapAmount = debtTokenBalanceAfter - debtTokenBalanceBefore;

        return debtTokenSwapAmount;
    }

    /**
     * @notice Returns a list of prices from a list of assets addresses
     * @param token1 token1 address
     * @param token2 token2 address
     * @return The prices of the given assets
     */
    function _getTokenPricesInUsd_8dec(address token1, address token2) internal view returns (uint256[] memory) {
        address[] memory tokens = new address[](2);
        tokens[0] = token1;
        tokens[1] = token2;

        return aaveOracle.getAssetsPrices(tokens);
    }

    /**
     * @notice Repays debt for a given pool with a specified token and amount.
     * @param poolAddress The address of the lending pool.
     * @param debtToken The address of the token to repay.
     * @param amount The amount of the token to repay.
     */
    function _repayDebt(address poolAddress, address debtToken, uint256 amount) public onlyExecutor {
        IERC20(debtToken).approve(poolAddress, amount);
        IPool(poolAddress).repay(debtToken, amount, 2, user);
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
        uint256 desiredSwapAmountInUsd = desiredSwapAmountInTokenA / 10e8 * tokenAUnitPriceInUSD_8dec;
        uint256 actualSwapAmountInUsd = actualSwapedAmountInTokenB / 10e8 * tokenBUnitPriceInUSD_8dec;

        uint256 actualSlippageBps = (desiredSwapAmountInUsd - actualSwapAmountInUsd) / desiredSwapAmountInUsd * 10_000;

        if (actualSlippageBps < maxAllowedSlippageBps) revert SlippageExceeded();
    }

    /*//////////////////////////////////////////////////////////////
                             MODIFIERS
     //////////////////////////////////////////////////////////////*/

    modifier onlyExecutor() {
        if (!isExecutor(msg.sender)) {
            revert NotExecutor();
        }
        _;
    }

    function isExecutor(address account) private view returns (bool) {
        return userVaultRegistry.executor() == account;
    }
}
