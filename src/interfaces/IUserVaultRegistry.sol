// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
 * @title IUserVaultRegistry
 */
interface IUserVaultRegistry {
    /// @notice Returns the address of the current executor
    function executor() external view returns (address);

    /// @notice Returns the max slippage allowed to be set by executor when swap in made in user vault
    function maxSwapSlippageBps() external view returns (uint256);

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
     * @notice Checks if an aggregator is supported
     * @param aggregator The aggregator address
     * @return True if supported, false otherwise
     */
    function isSupportedAggregator(address aggregator) external view returns (bool);

    /**
     * @notice Sets the maximum allowed swap slippage, expressed in basis points.
     * @dev
     * - 1 basis point (bps) = 0.01% (10_000 bps = 100%).
     * - This value is used to cap the acceptable difference between expected and actual swap output.
     * - Typically configured to a conservative threshold (e.g., 50–300 bps) depending on market conditions.
     * @param newMaxSwapSlippageBps The new maximum swap slippage in basis points.
     */
    function setMaxSwapSlippageBps(uint256 newMaxSwapSlippageBps) external;
}
