// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

/// @title IUserVault
/// @notice Interface for the UserVault contract that manages user collateral, repayments, swaps, and recovery of tokens or ETH.
/// @author
interface IUserVault {
    // ERRORS

    // @notice Emitted when an aggregator is not supported.
    error AggregatorNotSupported();
    //  @notice Emitted when the caller is not the executor.
    error NotExecutor();
    // @notice Emitted when swap is failed.
    error SwapFailed();
    // @notice Emitted the asset prices failed to be retrieved from oracle
    error GettingAssetPriceFailed();
    // @notice Emitted when swapping slippage exceeded the max allowed.
    error SlippageExceeded();
    // @notice Emitted when tokenId belongs to a different user vault.
    error InvalidUserVaultForToken();

    // EVENTS
    event LoanSelfRepaid(
        address indexed user, address indexed userVault, address pool, address debtToken, uint256 amount
    );

    // Structs

    /**
     * @notice Parameters for repaying a user's debt on a lending pool.
     * @dev
     * - tokenIds must belong to this user vault, otherwise the call reverts.
     * - Set aggregatorAddress and aggregatorData only if a swap is required (e.g., swapping rewards to the debt token).
     * - maxSlippageBps is expressed in basis points (1 bps = 0.01%).
     * @param debtToken The address of the debt token to be repaid.
     * @param poolAddress The address of the lending pool where the debt exists.
     * @param tokenIds List of token IDs involved in the operation.
     * @param rewardToken The reward token to claim and optionally swap before repayment.
     * @param rewardTokenAmountToSwap Amount of rewardToken to swap into the debt token.
     * @param aggregatorAddress Swap aggregator address to use for asset conversion, if needed.
     * @param aggregatorData Calldata for the aggregator to perform the swap.
     * @param maxSlippageBps Maximum acceptable swap slippage in basis points.
     */
    struct RepayUserDebtParams {
        address debtToken;
        address poolAddress;
        uint256[] tokenIds;
        address rewardToken;
        uint256 rewardTokenAmountToSwap;
        address aggregatorAddress;
        bytes aggregatorData;
        uint256 maxSlippageBps;
    }

    // Public Functions

    /**
     * @notice Repays a user's debt for a specified token on a lending pool.
     * @dev Optionally claims rewardToken and swaps it via the provided aggregator before repayment,
     *      enforcing the specified maxSlippageBps. Reverts if tokenIds are not associated with this vault.
     * @param params Structured parameters. See RepayUserDebtParams for details.
     */
    function repayUserDebt(RepayUserDebtParams calldata params) external;

    /**
     * @notice Claims rewards for the provided tokenIds and returns the total amount of rewardToken received.
     * @dev
     * - Reverts with InvalidUserVaultForToken if any tokenId’s reward receiver is not this vault.
     * - Calls the external rewards distributor for each tokenId to pull rewards into this contract.
     * - Computes the claimed amount by measuring this contract’s rewardToken balance delta.
     * - Callable only by the executor; otherwise reverts with NotExecutor.
     * @param tokenIds Array of token IDs whose rewards should be claimed.
     * @param rewardToken The ERC20 reward token to claim.
     * @return rewardTokenAmount The total amount of rewardToken claimed into this vault.
     */
    function getTokenIdsReward(uint256[] memory tokenIds, address rewardToken) external returns (uint256);

    /**
     * @notice Swaps tokenIn for tokenOut via a supported aggregator and verifies slippage against oracle prices.
     * @dev
     * - Reverts with AggregatorNotSupported if the aggregator is not approved.
     * - Forwards aggregatorData to the aggregator using a low-level call; reverts with SwapFailed on failure.
     * - Computes USD-denominated slippage using oracle prices and reverts with SlippageExceeded
     *   if it exceeds maxAllowedSlippageBps.
     * - Callable only by the executor; otherwise reverts with NotExecutor.
     * @param tokenIn The ERC20 token address to swap from.
     * @param tokenInAmount The exact amount of tokenIn to swap.
     * @param tokenOut The ERC20 token address to receive.
     * @param aggregator The swap aggregator contract to execute the swap.
     * @param aggregatorData Calldata to be sent to the aggregator for performing the swap.
     * @param maxAllowedSlippageBps Maximum acceptable slippage in basis points (1 bps = 0.01%).
     * @return The amount of tokenOut received from the swap.
     */
    function swapAndVerify(
        address tokenIn,
        uint256 tokenInAmount,
        address tokenOut,
        address aggregator,
        bytes memory aggregatorData,
        uint256 maxAllowedSlippageBps
    ) external returns (uint256);

    /**
     * @notice Repays debt for a given pool with a specified token and amount.
     * @param poolAddress The address of the lending pool.
     * @param debtToken The address of the token to repay.
     * @param amount The amount of the token to repay.
     */
    function repayDebt(address poolAddress, address debtToken, uint256 amount) external;

    /**
     * @notice Deposits collateral for a user into a lending pool.
     * @param poolAddress The address of the lending pool.
     * @param debtToken The address of the collateral token.
     * @param amount The amount of collateral to deposit.
     */
    function depositCollateral(address poolAddress, address debtToken, uint256 amount) external;

    /**
     * @notice Allows recovery of ERC20 tokens that may be stuck in the vault back to the user.
     * @param token The address of the ERC20 token to recover.
     * @param amount The amount of tokens to recover.
     */
    function recoverERC20(address token, uint256 amount) external;

    /**
     * @notice Allows recovery of native ETH that may be stuck in the vault back to the user.
     * @param amount The amount of ETH to recover.
     */
    function recoverETH(uint256 amount) external;
}
