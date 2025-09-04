// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

/// @title IUserVault
/// @notice Interface for the UserVault contract that manages user collateral, repayments, swaps, and recovery of tokens or ETH.
/// @author
interface IUserVault {
    /**
     * @notice Emitted when an aggregator is not supported.
     */
    error AggregatorNotSupported();

    /**
     * @notice Emitted when the caller is not the executor.
     */
    error NotExecutor();

    /**
     * @notice Emitted when swap is failed.
     */
    error SwapFailed();

    /**
     * @notice Initializes the UserVault for a specific user.
     * @param _user The address of the user owning this vault.
     */
    function initialize(address _user) external;

    /**
     * @notice Repays a user's debt for a specified token on a lending pool,
     *         potentially using rewards or swapped collateral.
     * @param debtToken The address of the debt token to be repaid.
     * @param poolAddress The address of the lending pool where the debt exists.
     * @param tokenIds List of token IDs involved in the operation.
     * @param rewardTokens Array of reward token addresses to claim before repayment.
     * @param aggregatorAddress Array of swap aggregator addresses to use for asset conversion if needed.
     * @param aggregatorData Call data for each aggregator to perform swaps.
     */
    function repayUserDebt(
        address debtToken,
        address poolAddress,
        uint256[] calldata tokenIds,
        address[] calldata rewardTokens,
        address[] calldata aggregatorAddress,
        bytes[] calldata aggregatorData
    ) external;

    /**
     * @notice Swaps a specified token using a given aggregator contract.
     * @param token The address of the token to be swapped.
     * @param aggregator The address of the swap aggregator contract to use for performing the swap.
     * @param aggregatorData The calldata required by the aggregator contract for the swap execution.
     * @param slippage The maximum acceptable slippage (in basis points or aggregator-specific format) for the swap transaction.
     */
    function swapAndVerifySlippage(address token, address aggregator, bytes calldata aggregatorData, uint256 slippage)
        external;

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
