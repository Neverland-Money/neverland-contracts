// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

/**
 * @title IUserVaultRegistry
 */
interface IUserVaultRegistry {
    /// @notice Returns the address of the current executor
    function executor() external view returns (address);

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
}
