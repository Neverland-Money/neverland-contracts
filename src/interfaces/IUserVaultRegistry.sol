// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
 * @title IUserVaultRegistry
 * @author Neverland
 * @notice Interface for the UserVaultRegistry contract.
 *         Manages executor and supported aggregators for user vaults.
 */
interface IUserVaultRegistry {
    /**
     * @notice Emitted when the executor is updated
     * @param oldExecutor The previous executor address
     * @param newExecutor The new executor address
     */
    event ExecutorUpdated(address indexed oldExecutor, address indexed newExecutor);

    /**
     * @notice Emitted when an aggregator's support status is updated
     * @param aggregator The aggregator address that was updated
     * @param isActive Whether the aggregator is now supported
     */
    event AggregatorSupportUpdated(address indexed aggregator, bool isActive);

    /**
     * @notice Emitted when the max swap slippage is updated
     * @param oldValue The previous max slippage in bps
     * @param newValue The new max slippage in bps
     */
    event MaxSwapSlippageUpdated(uint256 oldValue, uint256 newValue);

    /*//////////////////////////////////////////////////////////////
                                 VIEWS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the address of the current executor
     * @return The executor address
     */
    function executor() external view returns (address);

    /**
     * @notice Returns the max slippage allowed to be set by executor when swap is made in user vault
     * @return The maximum swap slippage in basis points
     */
    function maxSwapSlippageBps() external view returns (uint256);

    /**
     * @notice Checks if an aggregator is supported
     * @param aggregator The aggregator address to query
     * @return True if supported, false otherwise
     */
    function isSupportedAggregator(address aggregator) external view returns (bool);

    /*//////////////////////////////////////////////////////////////
                                ADMIN
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Sets the executor address
     * @param executor Address of the new executor
     */
    function setExecutor(address executor) external;

    /**
     * @notice Sets the aggregator as supported or not
     * @param aggregator The aggregator address
     * @param isActive True if the aggregator should be supported, false otherwise
     */
    function setSupportedAggregators(address aggregator, bool isActive) external;

    /**
     * @notice Sets the maximum allowed swap slippage, expressed in basis points.
     * @param newMaxSwapSlippageBps The new maximum swap slippage in basis points.
     */
    function setMaxSwapSlippageBps(uint256 newMaxSwapSlippageBps) external;
}
