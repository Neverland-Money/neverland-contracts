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
    // @notice Emitted when getting a reward lowers balance.
    error NegativeRewardAmount();
    // @notice Emitted when swapping lowers the swapped token amount.
    error NegativeSwapAmount();
    // @notice Emitted when swapping slippage exceeded the max allowed.
    error SlippageExceeded();
    // @notice Emitted when tokenId belongs to a different user vault.
    error InvalidUserVaultForToken();

    // EVENTS
    event LoanSelfRepaid(
        address indexed user, address indexed userVault, address pool, address debtToken, uint256 amount
    );

    /**
     * @notice Repays a user's debt for a specified token on a lending pool,
     *         potentially using rewards or swapped collateral.
     * @param debtToken The address of the debt token to be repaid.
     * @param poolAddress The address of the lending pool where the debt exists.
     * @param tokenIds List of token IDs involved in the operation.
     * @param rewardToken A reward token addresses to claim before repayment.
     * @param aggregatorAddress Swap aggregator address to use for asset conversion if needed.
     * @param aggregatorData Call data for aggregator to perform swaps.
     * @param maxSlippageBps Max slippage accepted.
     */
    function repayUserDebt(
        address debtToken,
        address poolAddress,
        uint256[] calldata tokenIds,
        address rewardToken,
        address aggregatorAddress,
        bytes calldata aggregatorData,
        uint256 maxSlippageBps
    ) external;

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
