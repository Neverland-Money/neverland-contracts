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
     * @notice Initializes the UserVault for a specific user.
     * @param _user The address of the user owning this vault.
     */
    function initialize(address _user) external;

    /**
     * @notice Repays a user's debt using a specified aggregator.
     * @param tokenB The address of the repayment token.
     * @param poolAddress The address of the lending pool.
     * @param aggregatorAddress The address of the aggregator to use.
     * @param aggregatorData Data to be passed to the aggregator.
     */
    function repayUserDebt(
        address tokenB,
        address poolAddress,
        address aggregatorAddress,
        bytes calldata aggregatorData
    ) external;

    /**
     * @notice Swaps assets in the vault using a supported aggregator.
     * @param tokenB The address of the asset to receive.
     * @param aggregator The address of the aggregator to use.
     * @param aggregatorData Data to be passed to the aggregator.
     */
    function swap(address tokenB, address aggregator, bytes calldata aggregatorData) external;

    /**
     * @notice Repays debt for a given pool with a specified token and amount.
     * @param poolAddress The address of the lending pool.
     * @param token The address of the token to repay.
     * @param amount The amount of the token to repay.
     */
    function repayDebt(address poolAddress, address token, uint256 amount) external;

    /**
     * @notice Deposits collateral for a user into a lending pool.
     * @param poolAddress The address of the lending pool.
     * @param token The address of the collateral token.
     * @param amount The amount of collateral to deposit.
     */
    function depositCollateral(address poolAddress, address token, uint256 amount) external;

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
