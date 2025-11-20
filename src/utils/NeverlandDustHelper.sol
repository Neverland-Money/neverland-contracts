// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IUniswapV2Pair} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import {CommonChecksLibrary} from "../libraries/CommonChecksLibrary.sol";
import {INeverlandDustHelper} from "../interfaces/INeverlandDustHelper.sol";
import {IChainlinkAggregator} from "../interfaces/IChainlinkAggregator.sol";

/**
 * @title NeverlandDustHelper
 * @author Neverland
 * @notice Production-ready oracle and helper contract for DUST token
 * @dev Provides market data, circulating supply, and price discovery via oracle integration
 */
contract NeverlandDustHelper is INeverlandDustHelper, Ownable {
    /*//////////////////////////////////////////////////////////////
                             CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Price decimals (8 decimals to match standard oracles)
    uint8 public constant PRICE_DECIMALS = 8;

    /// @notice Default DUST price in USD (8 decimals) - $0.25
    uint256 public constant DEFAULT_DUST_PRICE = 25e6; // 0.25 USD

    /// @notice 18-decimals unit
    uint256 private constant WAD = 1e18;

    /// @notice One USD in 8-decimal scale
    uint256 private constant USD_SCALE = 1e8;

    /*//////////////////////////////////////////////////////////////
                          STORAGE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice DUST token contract
    IERC20 public immutable dustToken;

    /// @notice Current hardcoded DUST price in USD (8 decimals)
    uint256 public hardcodedPrice;

    /// @notice DUST/<PAIR> pool/oracle or direct DUST/USD oracle
    /// @dev Can be: Uniswap V2/V3 pool, UniV3 TWAP oracle, or direct DUST/USD Chainlink oracle
    address public dustPair;

    /// @notice <PAIR>/USD oracle for two-step conversion (optional if dustPair is DUST/USD)
    /// @dev If not set (address(0)), dustPair is assumed to return DUST/USD directly
    address public pairOracle;

    /// @notice Last price update timestamp
    uint256 public lastPriceUpdate;

    /// @notice Price update interval (1 hour for production readiness)
    uint256 public priceUpdateInterval = 1 hours;

    /// @notice Cached price for gas optimization
    uint256 private cachedPrice;

    /// @notice Cache timestamp
    uint256 private cacheTimestamp;

    /// @notice Whether the cached price came from oracle (true) or hardcoded (false)
    bool private cachedPriceFromOracle;

    /// @notice Team addresses mapping
    mapping(address => bool) public isTeamAddress;

    /// @notice Array of team addresses for iteration
    address[] public teamAddresses;

    /// @notice Configurable maximum reasonable price (safety check)
    uint256 public maxReasonablePrice = 1e11;

    /// @notice Configurable minimum reasonable price (safety check)
    uint256 public minReasonablePrice = 1e5;

    /// @notice Round ID for Chainlink compatibility
    uint256 private currentRoundId;

    /// @notice Round data for Chainlink compatibility
    mapping(uint256 => RoundData) private rounds;

    /*//////////////////////////////////////////////////////////////
                               STRUCTS
    //////////////////////////////////////////////////////////////*/

    // MarketData struct is declared in the interface

    /**
     * @notice Chainlink round data structure
     * @param answer The answer of the round
     * @param timestamp The timestamp of the round
     * @param startedAt The start timestamp of the round
     * @param answeredInRound The round in which the answer was computed
     */
    struct RoundData {
        uint256 answer;
        uint256 timestamp;
        uint256 startedAt;
        uint256 answeredInRound;
    }

    /*//////////////////////////////////////////////////////////////
                             CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the helper with token and owner
     * @param _dustToken DUST token address (IERC20)
     * @param _initialOwner Initial owner for Ownable
     */
    constructor(address _dustToken, address _initialOwner) {
        _transferOwnership(_initialOwner);
        CommonChecksLibrary.revertIfZeroAddress(_dustToken);
        CommonChecksLibrary.revertIfZeroAddress(_initialOwner);

        dustToken = IERC20(_dustToken);
        hardcodedPrice = DEFAULT_DUST_PRICE;
        lastPriceUpdate = block.timestamp;
        cachedPrice = DEFAULT_DUST_PRICE;
        cacheTimestamp = block.timestamp;
        cachedPriceFromOracle = false;

        // Initialize round data with hardcoded price so Chainlink interface works immediately
        currentRoundId = 1;
        rounds[currentRoundId] = RoundData({
            answer: DEFAULT_DUST_PRICE, timestamp: block.timestamp, startedAt: block.timestamp, answeredInRound: 1
        });
    }

    /*//////////////////////////////////////////////////////////////
                           TEAM MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc INeverlandDustHelper
    function addTeamAddress(address teamAddress) external override onlyOwner {
        CommonChecksLibrary.revertIfZeroAddress(teamAddress);

        if (isTeamAddress[teamAddress]) revert TeamAddressAlreadyExists(teamAddress);

        isTeamAddress[teamAddress] = true;
        teamAddresses.push(teamAddress);

        emit TeamAddressAdded(teamAddress);
    }

    /// @inheritdoc INeverlandDustHelper
    function removeTeamAddress(address teamAddress) external override onlyOwner {
        if (!isTeamAddress[teamAddress]) revert TeamAddressNotFound(teamAddress);

        isTeamAddress[teamAddress] = false;

        // Remove from array by finding and swapping with last element
        uint256 len = teamAddresses.length;
        for (uint256 i = 0; i < len; ++i) {
            if (teamAddresses[i] == teamAddress) {
                teamAddresses[i] = teamAddresses[teamAddresses.length - 1];
                teamAddresses.pop();
                break;
            }
        }

        emit TeamAddressRemoved(teamAddress);
    }

    /// @inheritdoc INeverlandDustHelper
    function getTeamAddresses() external view override returns (address[] memory addresses) {
        return teamAddresses;
    }

    /// @inheritdoc INeverlandDustHelper
    function getTeamAddressCount() external view override returns (uint256 count) {
        return teamAddresses.length;
    }

    /// @inheritdoc INeverlandDustHelper
    function addTeamAddresses(address[] calldata teamAddressesBatch) external override onlyOwner {
        if (teamAddressesBatch.length == 0) {
            revert EmptyArray();
        }

        for (uint256 i = 0; i < teamAddressesBatch.length; ++i) {
            address teamAddress = teamAddressesBatch[i];
            CommonChecksLibrary.revertIfZeroAddress(teamAddress);

            if (isTeamAddress[teamAddress]) revert TeamAddressAlreadyExists(teamAddress);

            isTeamAddress[teamAddress] = true;
            teamAddresses.push(teamAddress);
        }

        emit TeamAddressesBatchAdded(teamAddressesBatch);
    }

    /// @inheritdoc INeverlandDustHelper
    function removeTeamAddresses(address[] calldata teamAddressesBatch) external override onlyOwner {
        if (teamAddressesBatch.length == 0) {
            revert EmptyArray();
        }

        for (uint256 i = 0; i < teamAddressesBatch.length; ++i) {
            address teamAddress = teamAddressesBatch[i];

            if (!isTeamAddress[teamAddress]) revert TeamAddressNotFound(teamAddress);

            isTeamAddress[teamAddress] = false;

            // Remove from array by finding and swapping with last element
            uint256 lenInner = teamAddresses.length;
            for (uint256 j = 0; j < lenInner; ++j) {
                if (teamAddresses[j] == teamAddress) {
                    teamAddresses[j] = teamAddresses[teamAddresses.length - 1];
                    teamAddresses.pop();
                    break;
                }
            }
        }

        emit TeamAddressesBatchRemoved(teamAddressesBatch);
    }

    /*//////////////////////////////////////////////////////////////
                         ORACLE INTEGRATION
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc INeverlandDustHelper
    function pair() external view override returns (address pairAddress) {
        return dustPair;
    }

    /**
     * @notice Set the price source for DUST
     * @param pairAddress Can be:
     *        - Uniswap V2/V3 pool (DUST/<PAIR> or <PAIR>/DUST)
     *        - UniV3 TWAP oracle (Chainlink-compatible with token0/token1)
     *        - Direct DUST/USD Chainlink oracle (if pairOracle not needed)
     *        - DUST/<PAIR> Chainlink oracle (used with pairOracle for two-step conversion)
     */
    function setPair(address pairAddress) external override onlyOwner {
        CommonChecksLibrary.revertIfZeroAddress(pairAddress);

        address oldPair = dustPair;
        dustPair = pairAddress;

        // Clear cache when switching pairs
        cacheTimestamp = 0;

        emit PairUpdated(oldPair, pairAddress);
    }

    /**
     * @notice Remove the DUST/<PAIR> pool/oracle
     */
    function removePair() external override onlyOwner {
        address oldPair = dustPair;
        dustPair = address(0);
        cacheTimestamp = 0;

        emit PairUpdated(oldPair, address(0));
    }

    /**
     * @notice Set the <PAIR>/USD Chainlink oracle for USD conversion
     * @param pairOracleAddress <PAIR>/USD Chainlink oracle address (e.g., MON/USD, USDC/USD)
     */
    function setPairOracle(address pairOracleAddress) external onlyOwner {
        CommonChecksLibrary.revertIfZeroAddress(pairOracleAddress);

        address oldPairOracle = pairOracle;
        pairOracle = pairOracleAddress;

        emit PairOracleUpdated(oldPairOracle, pairOracleAddress);
    }

    /*//////////////////////////////////////////////////////////////
                               PRICE MANAGEMENT
        //////////////////////////////////////////////////////////////*/

    /// @inheritdoc INeverlandDustHelper
    function updateHardcodedPrice(uint256 newPrice) external override onlyOwner {
        if (newPrice < minReasonablePrice || newPrice > maxReasonablePrice) revert InvalidPrice(newPrice);

        uint256 oldPrice = hardcodedPrice;
        hardcodedPrice = newPrice;
        lastPriceUpdate = block.timestamp;

        // Update cache if using hardcoded price
        if (dustPair == address(0)) {
            cachedPrice = newPrice;
            cacheTimestamp = block.timestamp;
            cachedPriceFromOracle = false;
        }

        emit PriceUpdated(oldPrice, newPrice, block.timestamp, false);
    }

    /// @inheritdoc INeverlandDustHelper
    function setPriceUpdateInterval(uint256 interval) external override onlyOwner {
        if (interval < 60 || interval > 24 hours) revert InvalidPriceUpdateInterval(interval);

        uint256 oldInterval = priceUpdateInterval;
        priceUpdateInterval = interval;

        emit PriceUpdateIntervalChanged(oldInterval, interval);
    }

    /// @inheritdoc INeverlandDustHelper
    function setPriceLimits(uint256 minPrice, uint256 maxPrice) external override onlyOwner {
        if (minPrice == 0 || maxPrice <= minPrice) revert InvalidPriceLimits(minPrice, maxPrice);

        minReasonablePrice = minPrice;
        maxReasonablePrice = maxPrice;

        emit PriceLimitsUpdated(minPrice, maxPrice);
    }

    /*//////////////////////////////////////////////////////////////
                         SUPPLY CALCULATIONS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc INeverlandDustHelper
    function getTotalSupply() public view override returns (uint256 supply) {
        return dustToken.totalSupply();
    }

    /// @inheritdoc INeverlandDustHelper
    function getCirculatingSupply() public view override returns (uint256 supply) {
        uint256 totalSupply = dustToken.totalSupply();
        uint256 teamBalance = 0;

        // Sum all team address balances
        uint256 len = teamAddresses.length;
        for (uint256 i = 0; i < len; ++i) {
            teamBalance += dustToken.balanceOf(teamAddresses[i]);
        }

        return totalSupply > teamBalance ? totalSupply - teamBalance : 0;
    }

    /// @inheritdoc INeverlandDustHelper
    function getTeamTotalBalance() external view override returns (uint256 balance) {
        uint256 len = teamAddresses.length;
        for (uint256 i = 0; i < len; ++i) {
            balance += dustToken.balanceOf(teamAddresses[i]);
        }
    }

    /*//////////////////////////////////////////////////////////////
                         PRICE DISCOVERY
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc INeverlandDustHelper
    function getPrice() public view override returns (uint256 price, bool fromOracle) {
        // Use cache if valid
        if (cacheTimestamp > 0 && block.timestamp <= cacheTimestamp + priceUpdateInterval) {
            return (cachedPrice, cachedPriceFromOracle);
        }

        if (dustPair != address(0)) {
            (uint256 oraclePrice, bool oracleSuccess) = _getOraclePrice();
            return (oraclePrice, oracleSuccess);
        }
        return (hardcodedPrice, false);
    }

    /// @inheritdoc INeverlandDustHelper
    function updatePriceCache() external override {
        (uint256 newPrice, bool fromOracle) = _getPriceWithoutCache();

        // Validate price reasonableness
        if (newPrice < minReasonablePrice || newPrice > maxReasonablePrice) {
            revert InvalidPrice(newPrice);
        }

        uint256 oldPrice = cachedPrice;
        cachedPrice = newPrice;
        cacheTimestamp = block.timestamp;
        cachedPriceFromOracle = fromOracle;

        // Update lastPriceUpdate when cache is refreshed
        lastPriceUpdate = block.timestamp;

        // Always update Chainlink round data (even for hardcoded prices)
        _updateRoundData(newPrice, fromOracle);

        emit PriceUpdated(oldPrice, newPrice, block.timestamp, fromOracle);
    }

    /**
     * @notice Internal function to update Chainlink round data
     * @param price New price to record
     * @param fromOracle Whether price came from oracle or is hardcoded
     */
    function _updateRoundData(uint256 price, bool fromOracle) internal {
        // If we have a <PAIR>/USD oracle and price is from oracle, use its round data
        if (pairOracle != address(0) && fromOracle) {
            (uint80 oracleRoundId,, uint256 oracleStartedAt, uint256 oracleUpdatedAt, uint80 oracleAnsweredInRound) =
                IChainlinkAggregator(pairOracle).latestRoundData();

            currentRoundId = uint256(oracleRoundId);
            rounds[currentRoundId] = RoundData({
                answer: price,
                timestamp: oracleUpdatedAt,
                startedAt: oracleStartedAt,
                answeredInRound: uint256(oracleAnsweredInRound)
            });

            emit AnswerUpdated(int256(price), currentRoundId, oracleUpdatedAt);
        } else {
            // Hardcoded price or no oracle - create synthetic round data
            currentRoundId += 1;
            rounds[currentRoundId] = RoundData({
                answer: price, timestamp: block.timestamp, startedAt: block.timestamp, answeredInRound: currentRoundId
            });

            emit AnswerUpdated(int256(price), currentRoundId, block.timestamp);
        }
    }

    /**
     * @notice Get price without using cache
     * @return price Current price (8 decimals)
     * @return fromOracle Whether price is from oracle
     */
    function _getPriceWithoutCache() internal view returns (uint256 price, bool fromOracle) {
        if (dustPair != address(0)) {
            (uint256 oraclePrice, bool oracleSuccess) = _getOraclePrice();
            return (oraclePrice, oracleSuccess);
        }
        return (hardcodedPrice, false);
    }

    /**
     * @notice Get price from oracle
     * @return price Price from oracle (8 decimals), or hardcoded price if validation fails
     * @return success True if price came from successful oracle read, false if fallback
     */
    function _getOraclePrice() internal view returns (uint256 price, bool success) {
        // Need at least dustPair to get oracle price
        if (dustPair == address(0)) {
            return (hardcodedPrice, false);
        }

        uint256 dustPerUsdPrice18; // Price in 18 decimals

        // Case 1: Direct DUST/USD oracle (no pairOracle needed)
        if (pairOracle == address(0)) {
            // dustPair is assumed to return DUST/USD directly
            bool dustUsdSuccess;
            (dustPerUsdPrice18, dustUsdSuccess) = _getDustPairPrice();
            if (!dustUsdSuccess) return (hardcodedPrice, false);
        } else {
            // Case 2: Two-step conversion via DUST/<PAIR> and <PAIR>/USD
            // Get DUST/<PAIR> price from pool or oracle
            (uint256 dustPerPairPrice, bool dustPairSuccess) = _getDustPairPrice();
            if (!dustPairSuccess) return (hardcodedPrice, false);

            // Get <PAIR>/USD price from oracle
            (uint256 pairPerUsdPrice, bool pairUsdSuccess) = _getPairUsdPrice();
            if (!pairUsdSuccess) return (hardcodedPrice, false);

            // Calculate DUST/USD = DUST/<PAIR> * <PAIR>/USD
            // Both prices are in 18 decimals, result is 36 decimals, divide by 1e18
            dustPerUsdPrice18 = (dustPerPairPrice * pairPerUsdPrice) / 1e18;
        }

        // Convert to 8 decimals
        uint256 finalPrice = dustPerUsdPrice18 / 1e10;

        // Final bounds check
        if (finalPrice >= minReasonablePrice && finalPrice <= maxReasonablePrice) {
            return (finalPrice, true);
        }
        return (hardcodedPrice, false);
    }

    /**
     * @notice Get DUST/<PAIR> price from Uniswap pool or oracle
     * @dev Tries Uniswap V3 pool first, falls back to V2, then Chainlink oracle
     * @return price Price in 18 decimals (DUST per PAIR token)
     * @return success Whether price was successfully retrieved
     */
    function _getDustPairPrice() internal view returns (uint256 price, bool success) {
        // Try Uniswap V3 pool first
        (uint256 v3Price, bool v3Success) = _getUniswapV3Price();
        if (v3Success) return (v3Price, true);

        // Try Uniswap V2 pool
        (uint256 v2Price, bool v2Success) = _getUniswapV2Price();
        if (v2Success) return (v2Price, true);

        // Try Chainlink oracle as fallback
        (uint256 oraclePrice, bool oracleSuccess) = _getChainlinkPrice();
        if (oracleSuccess) return (oraclePrice, true);

        return (0, false);
    }

    /**
     * @notice Get price from Uniswap V3 pool using slot0
     */
    function _getUniswapV3Price() internal view returns (uint256 price, bool success) {
        try IUniswapV3Pool(dustPair).slot0() returns (
            uint160 sqrtPriceX96, int24, uint16, uint16, uint16, uint8, bool
        ) {
            if (sqrtPriceX96 == 0) return (0, false);

            // Get token addresses and decimals to determine ordering
            address token0 = IUniswapV3Pool(dustPair).token0();
            address token1 = IUniswapV3Pool(dustPair).token1();
            address dustAddr = address(dustToken);

            // Get token decimals for proper scaling
            uint8 decimals0 = IERC20Metadata(token0).decimals();
            uint8 decimals1 = IERC20Metadata(token1).decimals();

            // Calculate price from sqrtPriceX96
            // sqrtPriceX96 = sqrt(token1/token0) * 2^96 (in raw token amounts)
            // price = (sqrtPriceX96)^2 / 2^192 = token1/token0
            // But we need to adjust for decimals to get the price in 18-decimal format

            // Multiply sqrtPrice by itself to get price * 2^192
            uint256 priceX192 = uint256(sqrtPriceX96) * uint256(sqrtPriceX96);

            // Adjust for decimals: price_adjusted = price_raw * 10^decimals0 / 10^decimals1
            // Combine with shifting: price18 = priceX192 * 1e18 * 10^decimals0 / (2^192 * 10^decimals1)
            uint256 price18;
            if (decimals0 >= decimals1) {
                // Avoid overflow: first shift, then multiply
                uint256 shifted = priceX192 >> 192;
                price18 = shifted * 1e18 * (10 ** (decimals0 - decimals1));
            } else {
                // More complex: need to divide by extra decimals
                uint256 shifted = priceX192 >> 192;
                price18 = (shifted * 1e18) / (10 ** (decimals1 - decimals0));
            }

            // Handle token ordering
            if (token0 == dustAddr) {
                // Pool is DUST/<PAIR>, price18 = <PAIR> per DUST in 18 decimals
                // We want DUST per <PAIR>, so invert
                if (price18 == 0) return (0, false);
                price = (1e18 * 1e18) / price18;
            } else if (token1 == dustAddr) {
                // Pool is <PAIR>/DUST, price18 = DUST per <PAIR> in 18 decimals
                price = price18;
            } else {
                // DUST not in pool
                return (0, false);
            }

            return (price, true);
        } catch {
            return (0, false);
        }
    }

    /**
     * @notice Get price from Uniswap V2 pool using reserves
     */
    function _getUniswapV2Price() internal view returns (uint256 price, bool success) {
        try IUniswapV2Pair(dustPair).getReserves() returns (uint112 reserve0, uint112 reserve1, uint32) {
            if (reserve0 == 0 || reserve1 == 0) return (0, false);

            // Get token addresses to determine ordering
            address token0 = IUniswapV2Pair(dustPair).token0();
            address token1 = IUniswapV2Pair(dustPair).token1();
            address dustAddr = address(dustToken);

            // Calculate price based on reserves
            if (token0 == dustAddr) {
                // Pool is DUST/<PAIR>: price = reserve1 / reserve0 (<PAIR> per DUST)
                // We want DUST per <PAIR>, so invert
                price = (uint256(reserve0) * 1e18) / uint256(reserve1);
            } else if (token1 == dustAddr) {
                // Pool is <PAIR>/DUST: price = reserve0 / reserve1 (DUST per <PAIR>)
                price = (uint256(reserve1) * 1e18) / uint256(reserve0);
            } else {
                // DUST not in pool
                return (0, false);
            }

            return (price, true);
        } catch {
            return (0, false);
        }
    }

    /**
     * @notice Get price from Chainlink-compatible oracle (may include token ordering)
     * @dev Supports both standard Chainlink oracles and custom oracles with token0/token1
     */
    function _getChainlinkPrice() internal view returns (uint256 price, bool success) {
        try IChainlinkAggregator(dustPair).latestRoundData() returns (uint80, int256 answer, uint256, uint256, uint80) {
            if (answer <= 0) return (0, false);

            uint256 rawPrice = uint256(answer);
            uint8 decimalsOracle = IChainlinkAggregator(dustPair).decimals();

            // Normalize to 18 decimals
            uint256 price18;
            if (decimalsOracle == 18) {
                price18 = rawPrice;
            } else if (decimalsOracle < 18) {
                price18 = rawPrice * (10 ** (18 - decimalsOracle));
            } else {
                price18 = rawPrice / (10 ** (decimalsOracle - 18));
            }

            // Try to detect token ordering if oracle exposes token0/token1 (UniV3 oracle)
            try IChainlinkAggregator(dustPair).token0() returns (address token0) {
                try IChainlinkAggregator(dustPair).token1() returns (address token1) {
                    address dustAddr = address(dustToken);

                    // Handle token ordering
                    // Oracle returns price as token0/token1
                    if (token1 == dustAddr) {
                        // token0=<PAIR>, token1=DUST: oracle returns <PAIR>/DUST
                        // We want DUST/<PAIR>, so invert
                        if (price18 == 0) return (0, false);
                        price = (1e18 * 1e18) / price18;
                    } else if (token0 == dustAddr) {
                        // token0=DUST, token1=<PAIR>: oracle returns DUST/<PAIR>
                        // Already correct
                        price = price18;
                    } else {
                        // DUST not in oracle pair, assume oracle returns DUST/<PAIR>
                        price = price18;
                    }
                    return (price, true);
                } catch {
                    // token1() failed, assume oracle returns DUST/<PAIR>
                    price = price18;
                    return (price, true);
                }
            } catch {
                // token0() not available (standard Chainlink oracle)
                // Assume oracle returns DUST/<PAIR>
                price = price18;
                return (price, true);
            }
        } catch {
            return (0, false);
        }
    }

    /**
     * @notice Get <PAIR>/USD price from Chainlink oracle
     * @return price Price in 18 decimals (USD per PAIR token)
     * @return success Whether price was successfully retrieved
     */
    function _getPairUsdPrice() internal view returns (uint256 price, bool success) {
        try IChainlinkAggregator(pairOracle).latestRoundData() returns (
            uint80, int256 answer, uint256, uint256, uint80
        ) {
            if (answer <= 0) return (0, false);

            uint256 rawPrice = uint256(answer);
            uint8 pairOracleDecimals = IChainlinkAggregator(pairOracle).decimals();

            // Normalize to 18 decimals
            if (pairOracleDecimals == 18) {
                price = rawPrice;
            } else if (pairOracleDecimals < 18) {
                price = rawPrice * (10 ** (18 - pairOracleDecimals));
            } else {
                price = rawPrice / (10 ** (pairOracleDecimals - 18));
            }

            return (price, true);
        } catch {
            return (0, false);
        }
    }

    /*//////////////////////////////////////////////////////////////
                         MARKET DATA (MAIN FUNCTION)
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc INeverlandDustHelper
    function getMarketData() external view override returns (INeverlandDustHelper.MarketData memory data) {
        uint256 totalSupply = getTotalSupply();
        uint256 circulatingSupply = getCirculatingSupply();
        (uint256 usdPrice, bool fromOracle) = getPrice();

        // Calculate market caps (convert to 8 decimals for consistency)
        // circulatingSupply is 18 decimals, price is 8 decimals
        // Result should be 8 decimals: (supply * price) / WAD
        uint256 marketCap = (circulatingSupply * usdPrice) / WAD;
        uint256 fullyDilutedMarketCap = (totalSupply * usdPrice) / WAD;

        return INeverlandDustHelper.MarketData({
            circulatingSupply: circulatingSupply,
            totalSupply: totalSupply,
            usdPrice: usdPrice,
            marketCap: marketCap,
            fullyDilutedMarketCap: fullyDilutedMarketCap,
            timestamp: block.timestamp,
            isPriceFromOracle: fromOracle
        });
    }

    /// @inheritdoc INeverlandDustHelper
    function getMarketMetrics()
        external
        view
        override
        returns (uint256 circulatingSupply, uint256 totalSupply, uint256 usdPrice, uint256 marketCap)
    {
        totalSupply = getTotalSupply();
        circulatingSupply = getCirculatingSupply();
        (usdPrice,) = getPrice();
        marketCap = (circulatingSupply * usdPrice) / WAD;
    }

    /*//////////////////////////////////////////////////////////////
                           UTILITY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc INeverlandDustHelper
    function getDustValueInUSD(uint256 dustAmount) external view override returns (uint256 usdValue) {
        (uint256 price,) = getPrice();
        return (dustAmount * price) / WAD;
    }

    /// @inheritdoc INeverlandDustHelper
    function getUSDValueInDust(uint256 usdValue) external view override returns (uint256 dustAmount) {
        (uint256 price,) = getPrice();
        if (price == 0) return 0;
        return (usdValue * WAD) / price;
    }

    /// @inheritdoc INeverlandDustHelper
    function isPriceCacheStale() external view override returns (bool isStale) {
        return cacheTimestamp < 1 || block.timestamp > cacheTimestamp + priceUpdateInterval;
    }

    /// @inheritdoc INeverlandDustHelper
    function getPriceInfo()
        external
        view
        override
        returns (uint256 price, bool isFromOracle, uint256 lastUpdate, bool isStale)
    {
        (price, isFromOracle) = getPrice();
        lastUpdate = cacheTimestamp;
        isStale = cacheTimestamp < 1 || block.timestamp > cacheTimestamp + priceUpdateInterval;
    }

    /*//////////////////////////////////////////////////////////////
                         CHAINLINK COMPATIBILITY
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc INeverlandDustHelper
    function latestRoundData()
        external
        view
        override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        if (currentRoundId == 0 || rounds[currentRoundId].timestamp == 0) revert NoRoundsRecorded();

        RoundData memory round = rounds[currentRoundId];
        return
            (
                uint80(currentRoundId),
                int256(round.answer),
                round.startedAt,
                round.timestamp,
                uint80(round.answeredInRound)
            );
    }

    /// @inheritdoc INeverlandDustHelper
    function getRoundData(uint80 requestRoundId)
        external
        view
        override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        RoundData memory round = rounds[uint256(requestRoundId)];
        if (round.timestamp == 0) revert NoDataPresent();

        return (requestRoundId, int256(round.answer), round.startedAt, round.timestamp, uint80(round.answeredInRound));
    }

    /// @inheritdoc INeverlandDustHelper
    function latestAnswer() external view override returns (int256 price) {
        if (currentRoundId == 0 || rounds[currentRoundId].timestamp == 0) revert NoRoundsRecorded();
        return int256(rounds[currentRoundId].answer);
    }

    /// @inheritdoc INeverlandDustHelper
    function latestTimestamp() external view override returns (uint256 timestamp) {
        if (currentRoundId == 0 || rounds[currentRoundId].timestamp == 0) revert NoRoundsRecorded();
        return rounds[currentRoundId].timestamp;
    }

    /// @inheritdoc INeverlandDustHelper
    function latestRound() external view override returns (uint256 roundId) {
        if (currentRoundId == 0 || rounds[currentRoundId].timestamp == 0) revert NoRoundsRecorded();
        return currentRoundId;
    }

    /// @inheritdoc INeverlandDustHelper
    function getAnswer(uint256 roundId) external view override returns (int256 answer) {
        RoundData memory round = rounds[roundId];
        if (round.timestamp == 0) revert NoDataPresent();

        return int256(round.answer);
    }

    /// @inheritdoc INeverlandDustHelper
    function getTimestamp(uint256 roundId) external view override returns (uint256 timestamp) {
        RoundData memory round = rounds[roundId];
        if (round.timestamp == 0) revert NoDataPresent();

        return round.timestamp;
    }

    /// @inheritdoc INeverlandDustHelper
    function decimals() external pure override returns (uint8) {
        return PRICE_DECIMALS;
    }

    /// @inheritdoc INeverlandDustHelper
    function description() external pure override returns (string memory) {
        return "DUST / MON";
    }

    /// @inheritdoc INeverlandDustHelper
    function version() external pure override returns (uint256) {
        return 1;
    }

    /// @notice Disabled to prevent accidental renouncement of ownership
    function renounceOwnership() public view override onlyOwner {
        revert();
    }
}
