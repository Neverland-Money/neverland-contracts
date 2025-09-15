// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title INeverlandDustHelper
 * @author Neverland
 * @notice Interface for the DUST oracle/helper used by UI and integrations
 */
interface INeverlandDustHelper {
    /*//////////////////////////////////////////////////////////////
                               STRUCTS
    //////////////////////////////////////////////////////////////*/

    struct MarketData {
        uint256 circulatingSupply; // 18 decimals
        uint256 totalSupply; // 18 decimals
        uint256 usdPrice; // 8 decimals
        uint256 marketCap; // 8 decimals
        uint256 fullyDilutedMarketCap; // 8 decimals
        uint256 timestamp;
        bool isPriceFromUniswap;
    }

    /*//////////////////////////////////////////////////////////////
                               EVENTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Emitted when the cached price is updated
     * @param oldPrice Previous price (8 decimals)
     * @param newPrice New price (8 decimals)
     * @param timestamp Block timestamp when the price was updated
     * @param fromUniswap True if the price came from Uniswap, false if hardcoded
     */
    event PriceUpdated(uint256 oldPrice, uint256 newPrice, uint256 timestamp, bool fromUniswap);

    /**
     * @notice Emitted when the Uniswap pair used for price discovery changes
     * @param oldPair Previous pair address
     * @param newPair New pair address (zero to disable)
     */
    event UniswapPairUpdated(address oldPair, address newPair);

    /**
     * @notice Emitted when a team address is added to the exclusion list
     * @param teamAddress The added team address
     */
    event TeamAddressAdded(address teamAddress);

    /**
     * @notice Emitted when a team address is removed from the exclusion list
     * @param teamAddress The removed team address
     */
    event TeamAddressRemoved(address teamAddress);

    /**
     * @notice Emitted when multiple team addresses are added
     * @param teamAddresses Array of added team addresses
     */
    event TeamAddressesBatchAdded(address[] teamAddresses);

    /**
     * @notice Emitted when multiple team addresses are removed
     * @param teamAddresses Array of removed team addresses
     */
    event TeamAddressesBatchRemoved(address[] teamAddresses);

    /**
     * @notice Emitted when the cache invalidation interval changes
     * @param oldInterval Previous interval in seconds
     * @param newInterval New interval in seconds
     */
    event PriceUpdateIntervalChanged(uint256 oldInterval, uint256 newInterval);

    /**
     * @notice Emitted when the reasonable price limits are updated
     * @param minPrice New minimum price (8 decimals)
     * @param maxPrice New maximum price (8 decimals)
     */
    event PriceLimitsUpdated(uint256 minPrice, uint256 maxPrice);

    /**
     * @notice Emitted for Chainlink-compatibility when the answer changes
     * @param current Current price (8 decimals)
     * @param roundId Round identifier
     * @param updatedAt Timestamp when the answer was updated
     */
    event AnswerUpdated(int256 indexed current, uint256 indexed roundId, uint256 updatedAt);

    /*//////////////////////////////////////////////////////////////
                               ERRORS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Invalid price provided
     * @param price Invalid price (8 decimals)
     */
    error InvalidPrice(uint256 price);

    /**
     * @notice Team address already exists
     * @param teamAddress Team address
     */
    error TeamAddressAlreadyExists(address teamAddress);

    /**
     * @notice Team address not found
     * @param teamAddress Team address
     */
    error TeamAddressNotFound(address teamAddress);

    /**
     * @notice Invalid price update interval
     * @param interval Invalid interval
     */
    error InvalidPriceUpdateInterval(uint256 interval);

    /**
     * @notice Invalid price limits
     * @param minPrice Minimum price (8 decimals)
     * @param maxPrice Maximum price (8 decimals)
     */
    error InvalidPriceLimits(uint256 minPrice, uint256 maxPrice);

    /// @notice Empty array provided
    error EmptyArray();

    /**
     * @notice Invalid round ID
     * @param roundId Invalid round ID
     */
    error InvalidRoundId(uint256 roundId);

    /*//////////////////////////////////////////////////////////////
                           TEAM MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Add a team address
     * @param teamAddress Team address to add
     */
    function addTeamAddress(address teamAddress) external;

    /**
     * @notice Remove a team address
     * @param teamAddress Team address to remove
     */
    function removeTeamAddress(address teamAddress) external;

    /**
     * @notice Add multiple team addresses
     * @param teamAddresses Array of team addresses to add
     */
    function addTeamAddresses(address[] calldata teamAddresses) external;

    /**
     * @notice Remove multiple team addresses
     * @param teamAddresses Array of team addresses to remove
     */
    function removeTeamAddresses(address[] calldata teamAddresses) external;

    /**
     * @notice Get all team addresses
     * @return addresses Array of team addresses
     */
    function getTeamAddresses() external view returns (address[] memory addresses);

    /**
     * @notice Get the number of team addresses
     * @return count Number of team addresses
     */
    function getTeamAddressCount() external view returns (uint256 count);

    /**
     * @notice Check if an address is a team address
     * @param account Address to check
     * @return isTeam Whether the address is a team address
     */
    function isTeamAddress(address account) external view returns (bool isTeam);

    /*//////////////////////////////////////////////////////////////
                         UNISWAP INTEGRATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Set the Uniswap pair address
     * @param pairAddress Uniswap pair address
     */
    function setUniswapPair(address pairAddress) external;

    /**
     * @notice Remove the Uniswap pair address
     */
    function removeUniswapPair() external;

    /**
     * @notice Get the Uniswap pair address
     * @return pairAddress Uniswap pair address
     */
    function uniswapPair() external view returns (address pairAddress);

    /*//////////////////////////////////////////////////////////////
                           PRICE MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Update the hardcoded price
     * @param newPrice New price (8 decimals)
     */
    function updateHardcodedPrice(uint256 newPrice) external;

    /**
     * @notice Set the price update interval
     * @param interval Price update interval in seconds
     */
    function setPriceUpdateInterval(uint256 interval) external;

    /**
     * @notice Set the price limits
     * @param minPrice Minimum price (8 decimals)
     * @param maxPrice Maximum price (8 decimals)
     */
    function setPriceLimits(uint256 minPrice, uint256 maxPrice) external;

    /**
     * @notice Update the price cache
     */
    function updatePriceCache() external;

    /**
     * @notice Get the current price
     * @return price Current price (8 decimals)
     * @return fromUniswap Whether the price came from Uniswap
     */
    function getPrice() external view returns (uint256 price, bool fromUniswap);

    /*//////////////////////////////////////////////////////////////
                         SUPPLY CALCULATIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get total token supply (18 decimals)
     * @return supply Total supply
     */
    function getTotalSupply() external view returns (uint256 supply);
    /**
     * @notice Get circulating supply (excludes team balances)
     * @return supply Circulating supply (18 decimals)
     */
    function getCirculatingSupply() external view returns (uint256 supply);
    /**
     * @notice Sum of balances held by all team addresses
     * @return balance Total balance (18 decimals)
     */
    function getTeamTotalBalance() external view returns (uint256 balance);

    /*//////////////////////////////////////////////////////////////
                         MARKET DATA (MAIN FUNCTION)
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Return full market data snapshot
     * @return data MarketData struct with supplies, price and caps
     */
    function getMarketData() external view returns (MarketData memory data);

    /**
     * @notice Return basic market metrics
     * @return circulatingSupply Circulating supply (18 decimals)
     * @return totalSupply Total supply (18 decimals)
     * @return usdPrice Price (8 decimals)
     * @return marketCap Market cap (8 decimals)
     */
    function getMarketMetrics()
        external
        view
        returns (uint256 circulatingSupply, uint256 totalSupply, uint256 usdPrice, uint256 marketCap);

    /*//////////////////////////////////////////////////////////////
                           UTILITY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Convert DUST (18 decimals) to USD value (8 decimals)
     * @param dustAmount DUST amount (18 decimals)
     * @return usdValue USD value (8 decimals)
     */
    function getDustValueInUSD(uint256 dustAmount) external view returns (uint256 usdValue);

    /**
     * @notice Convert USD value (8 decimals) to DUST (18 decimals)
     * @param usdValue USD value (8 decimals)
     * @return dustAmount DUST amount (18 decimals)
     */
    function getUSDValueInDust(uint256 usdValue) external view returns (uint256 dustAmount);

    /**
     * @notice Check if price cache is stale
     * @return isStale True if stale, false otherwise
     */
    function isPriceCacheStale() external view returns (bool isStale);

    /**
     * @notice Detailed price info and cache state
     * @return price USD price (8 decimals)
     * @return isFromUniswap True if the price comes from Uniswap
     * @return lastUpdate Cache timestamp of last price update
     * @return isStale True if the cached price is stale
     */
    function getPriceInfo()
        external
        view
        returns (uint256 price, bool isFromUniswap, uint256 lastUpdate, bool isStale);

    /*//////////////////////////////////////////////////////////////
                         CHAINLINK COMPATIBILITY
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get latest round data
     * @return roundId Round ID
     * @return answer Price (8 decimals)
     * @return startedAt Round start timestamp
     * @return updatedAt Round update timestamp
     * @return answeredInRound Round answered in
     */
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);

    /**
     * @notice Get round data by round ID
     * @param _roundId Round ID
     * @return roundId Round ID
     * @return answer Price (8 decimals)
     * @return startedAt Round start timestamp
     * @return updatedAt Round update timestamp
     * @return answeredInRound Round answered in
     */
    function getRoundData(uint80 _roundId)
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);

    /**
     * @notice Get latest answer
     * @return price Price (8 decimals)
     */
    function latestAnswer() external view returns (int256 price);

    /**
     * @notice Get latest timestamp
     * @return timestamp Timestamp
     */
    function latestTimestamp() external view returns (uint256 timestamp);

    /**
     * @notice Get latest round ID
     * @return roundId Round ID
     */
    function latestRound() external view returns (uint256 roundId);

    /**
     * @notice Get answer by round ID
     * @param roundId Round ID
     * @return answer Price (8 decimals)
     */
    function getAnswer(uint256 roundId) external view returns (int256 answer);

    /**
     * @notice Get timestamp by round ID
     * @param roundId Round ID
     * @return timestamp Timestamp
     */
    function getTimestamp(uint256 roundId) external view returns (uint256 timestamp);

    /**
     * @notice Get number of decimals used by price (8)
     * @return decimals Number of decimals
     */
    function decimals() external pure returns (uint8 decimals);

    /**
     * @notice Get description of price feed
     * @return description Description
     */
    function description() external pure returns (string memory description);

    /**
     * @notice Get version of price feed
     * @return version Version
     */
    function version() external pure returns (uint256 version);

    /*//////////////////////////////////////////////////////////////
                           VIEW VARIABLES
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get DUST token
     * @return dustToken DUST token (IERC20)
     */
    function dustToken() external view returns (IERC20 dustToken);

    /**
     * @notice Get hardcoded price
     * @return price Hardcoded price (8 decimals)
     */
    function hardcodedPrice() external view returns (uint256 price);

    /**
     * @notice Get last price update timestamp
     * @return timestamp Last price update timestamp
     */
    function lastPriceUpdate() external view returns (uint256 timestamp);

    /**
     * @notice Get price update interval
     * @return interval Price update interval
     */
    function priceUpdateInterval() external view returns (uint256 interval);

    /**
     * @notice Get minimum reasonable price
     * @return price Minimum reasonable price (8 decimals)
     */
    function minReasonablePrice() external view returns (uint256 price);

    /**
     * @notice Get maximum reasonable price
     * @return price Maximum reasonable price (8 decimals)
     */
    function maxReasonablePrice() external view returns (uint256 price);

    /**
     * @notice Number of decimals used by USD price (8)
     * @return decimals Price decimals
     */
    function PRICE_DECIMALS() external view returns (uint8 decimals);

    /**
     * @notice Default hardcoded price used when Uniswap is disabled
     * @return price Default price (8 decimals)
     */
    function DEFAULT_DUST_PRICE() external view returns (uint256 price);
}
