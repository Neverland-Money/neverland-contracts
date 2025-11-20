// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

/**
 * @title IChainlinkAggregator
 * @notice Chainlink aggregator interface for price feeds
 * @dev Minimal interface for reading price data from Chainlink oracles
 */
interface IChainlinkAggregator {
    /**
     * @notice Get the latest round data
     * @return roundId The round ID
     * @return answer The price answer
     * @return startedAt Timestamp when round started
     * @return updatedAt Timestamp when round was updated
     * @return answeredInRound The round in which answer was computed
     */
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);

    /**
     * @notice Get the number of decimals for the price feed
     * @return decimals The number of decimals
     */
    function decimals() external view returns (uint8);

    /**
     * @notice Get token0 address (for Uniswap-style oracles)
     * @return token0 The address of token0
     */
    function token0() external view returns (address);

    /**
     * @notice Get token1 address (for Uniswap-style oracles)
     * @return token1 The address of token1
     */
    function token1() external view returns (address);
}
