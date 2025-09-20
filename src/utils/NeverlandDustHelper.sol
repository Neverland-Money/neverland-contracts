// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IUniswapV2Pair} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import {CommonChecksLibrary} from "../libraries/CommonChecksLibrary.sol";
import {INeverlandDustHelper} from "../interfaces/INeverlandDustHelper.sol";

/**
 * @title NeverlandDustHelper
 * @author Neverland
 * @notice Production-ready oracle and helper contract for DUST token
 * @dev Provides market data, circulating supply, and price discovery via Uniswap integration
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

    /// @notice 2^192 used for Uniswap V3 price math
    uint256 private constant Q192 = 1 << 192;

    /// @notice One USD in 8-decimal scale
    uint256 private constant USD_SCALE = 1e8;

    /*//////////////////////////////////////////////////////////////
                          STORAGE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice DUST token contract
    IERC20 public immutable dustToken;

    /// @notice Current hardcoded DUST price in USD (8 decimals)
    uint256 public hardcodedPrice;

    /// @notice Uniswap pair address for price discovery (zero means use hardcoded)
    address public uniswapPair;

    /// @notice Last price update timestamp
    uint256 public lastPriceUpdate;

    /// @notice Price update interval (1 hour for production readiness)
    uint256 public priceUpdateInterval = 1 hours;

    /// @notice Cached price for gas optimization
    uint256 private cachedPrice;

    /// @notice Cache timestamp
    uint256 private cacheTimestamp;

    /// @notice Team addresses mapping
    mapping(address => bool) public isTeamAddress;

    /// @notice Array of team addresses for iteration
    address[] public teamAddresses;

    /// @notice Configurable maximum reasonable price (safety check)
    uint256 public maxReasonablePrice = 1e11;

    /// @notice Configurable minimum reasonable price (safety check)
    uint256 public minReasonablePrice = 1e5;

    /// @notice Round ID for Chainlink compatibility
    uint256 private currentRoundId = 1;

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
     */
    struct RoundData {
        uint256 answer;
        uint256 timestamp;
        uint256 startedAt;
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
    }

    /*//////////////////////////////////////////////////////////////
                           TEAM MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc INeverlandDustHelper
    function addTeamAddress(address teamAddress) external override onlyOwner {
        CommonChecksLibrary.revertIfZeroAddress(teamAddress);

        if (isTeamAddress[teamAddress]) {
            revert TeamAddressAlreadyExists(teamAddress);
        }

        isTeamAddress[teamAddress] = true;
        teamAddresses.push(teamAddress);

        emit TeamAddressAdded(teamAddress);
    }

    /// @inheritdoc INeverlandDustHelper
    function removeTeamAddress(address teamAddress) external override onlyOwner {
        if (!isTeamAddress[teamAddress]) {
            revert TeamAddressNotFound(teamAddress);
        }

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

            if (isTeamAddress[teamAddress]) {
                revert TeamAddressAlreadyExists(teamAddress);
            }

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

            if (!isTeamAddress[teamAddress]) {
                revert TeamAddressNotFound(teamAddress);
            }

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
                         UNISWAP INTEGRATION
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc INeverlandDustHelper
    function setUniswapPair(address pairAddress) external override onlyOwner {
        CommonChecksLibrary.revertIfZeroAddress(pairAddress);

        address oldPair = uniswapPair;
        uniswapPair = pairAddress;

        // Clear cache when switching pairs
        cacheTimestamp = 0;

        emit UniswapPairUpdated(oldPair, pairAddress);
    }

    /// @inheritdoc INeverlandDustHelper
    function removeUniswapPair() external override onlyOwner {
        address oldPair = uniswapPair;
        uniswapPair = address(0);
        cacheTimestamp = 0;

        emit UniswapPairUpdated(oldPair, address(0));
    }

    /*//////////////////////////////////////////////////////////////
                           PRICE MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc INeverlandDustHelper
    function updateHardcodedPrice(uint256 newPrice) external override onlyOwner {
        if (newPrice < minReasonablePrice || newPrice > maxReasonablePrice) {
            revert InvalidPrice(newPrice);
        }

        uint256 oldPrice = hardcodedPrice;
        hardcodedPrice = newPrice;
        lastPriceUpdate = block.timestamp;

        // Update cache if using hardcoded price
        if (uniswapPair == address(0)) {
            cachedPrice = newPrice;
            cacheTimestamp = block.timestamp;
        }

        emit PriceUpdated(oldPrice, newPrice, block.timestamp, false);
    }

    /// @inheritdoc INeverlandDustHelper
    function setPriceUpdateInterval(uint256 interval) external override onlyOwner {
        if (interval < 60 || interval > 24 hours) {
            revert InvalidPriceUpdateInterval(interval);
        }

        uint256 oldInterval = priceUpdateInterval;
        priceUpdateInterval = interval;

        emit PriceUpdateIntervalChanged(oldInterval, interval);
    }

    /// @inheritdoc INeverlandDustHelper
    function setPriceLimits(uint256 minPrice, uint256 maxPrice) external override onlyOwner {
        if (minPrice == 0 || maxPrice <= minPrice) {
            revert InvalidPriceLimits(minPrice, maxPrice);
        }

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
    function getPrice() public view override returns (uint256 price, bool fromUniswap) {
        // Use cache if valid
        if (cacheTimestamp > 0 && block.timestamp <= cacheTimestamp + priceUpdateInterval) {
            return (cachedPrice, uniswapPair != address(0));
        }

        if (uniswapPair != address(0)) {
            return (_getUniswapPrice(), true);
        } else {
            return (hardcodedPrice, false);
        }
    }

    /// @inheritdoc INeverlandDustHelper
    function updatePriceCache() external override {
        (uint256 newPrice, bool fromUniswap) = _getPriceWithoutCache();

        // Validate price reasonableness
        if (newPrice < minReasonablePrice || newPrice > maxReasonablePrice) {
            revert InvalidPrice(newPrice);
        }

        uint256 oldPrice = cachedPrice;
        cachedPrice = newPrice;
        cacheTimestamp = block.timestamp;

        // Update Chainlink round data
        _updateRoundData(newPrice);

        emit PriceUpdated(oldPrice, newPrice, block.timestamp, fromUniswap);
    }

    /**
     * @notice Internal function to update Chainlink round data
     * @param price New price to record
     */
    function _updateRoundData(uint256 price) internal {
        ++currentRoundId;
        rounds[currentRoundId] = RoundData({answer: price, timestamp: block.timestamp, startedAt: block.timestamp});

        // Emit Chainlink-compatible event
        emit AnswerUpdated(int256(price), currentRoundId, block.timestamp);
    }

    /**
     * @notice Get price without using cache
     * @return price Current price (8 decimals)
     * @return fromUniswap Whether price is from Uniswap
     */
    function _getPriceWithoutCache() internal view returns (uint256 price, bool fromUniswap) {
        if (uniswapPair != address(0)) {
            return (_getUniswapPrice(), true);
        } else {
            return (hardcodedPrice, false);
        }
    }

    /**
     * @notice Get price from Uniswap pair
     * @return price Price from Uniswap (8 decimals)
     */
    function _getUniswapPrice() internal view returns (uint256 price) {
        address pair = uniswapPair;
        if (pair == address(0) || pair.code.length == 0) return hardcodedPrice;

        // Try Uniswap V3 pool (slot0)
        try IUniswapV3Pool(pair).slot0() returns (
            uint160 sqrtPriceX96, int24, /*tick*/ uint16, uint16, uint16, uint8, bool
        ) {
            address t0 = IUniswapV3Pool(pair).token0();
            address t1 = IUniswapV3Pool(pair).token1();
            uint8 d0 = IERC20Metadata(t0).decimals();
            uint8 d1 = IERC20Metadata(t1).decimals();

            uint256 priceX192 = uint256(sqrtPriceX96) * uint256(sqrtPriceX96); // Q192

            if (address(dustToken) == t0) {
                // DUST is token0, USD per DUST = (priceX192 / Q192) * 10^(dec0 - dec1)
                // Implemented as: (priceX192 * 10^dec0 * USD_SCALE) / (Q192 * 10^dec1)
                return Math.mulDiv(priceX192, (10 ** uint256(d0)) * USD_SCALE, Q192 * (10 ** uint256(d1)));
            } else if (address(dustToken) == t1) {
                // DUST is token1, USD per DUST = (Q192 / priceX192) * 10^(dec1 - dec0)
                // Implemented as: (Q192 * 10^dec1 * USD_SCALE) / (priceX192 * 10^dec0)
                return Math.mulDiv(Q192, (10 ** uint256(d1)) * USD_SCALE, priceX192 * (10 ** uint256(d0)));
            } else {
                return hardcodedPrice;
            }
        } catch {
            // Try Uniswap V2 pair reserves
            try IUniswapV2Pair(pair).getReserves() returns (uint112 r0, uint112 r1, uint32) {
                address t0 = IUniswapV2Pair(pair).token0();
                address t1 = IUniswapV2Pair(pair).token1();
                uint8 d0 = IERC20Metadata(t0).decimals();
                uint8 d1 = IERC20Metadata(t1).decimals();
                if (address(dustToken) == t0 && r0 > 0) {
                    return Math.mulDiv(uint256(r1), (10 ** uint256(d0)) * USD_SCALE, uint256(r0) * (10 ** uint256(d1)));
                } else if (address(dustToken) == t1 && r1 > 0) {
                    return Math.mulDiv(uint256(r0), (10 ** uint256(d1)) * USD_SCALE, uint256(r1) * (10 ** uint256(d0)));
                } else {
                    return hardcodedPrice;
                }
            } catch {
                return hardcodedPrice;
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                         MARKET DATA (MAIN FUNCTION)
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc INeverlandDustHelper
    function getMarketData() external view override returns (INeverlandDustHelper.MarketData memory data) {
        uint256 totalSupply = getTotalSupply();
        uint256 circulatingSupply = getCirculatingSupply();
        (uint256 usdPrice, bool fromUniswap) = getPrice();

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
            isPriceFromUniswap: fromUniswap
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
        returns (uint256 price, bool isFromUniswap, uint256 lastUpdate, bool isStale)
    {
        (price, isFromUniswap) = getPrice();
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
        (uint256 price,) = getPrice();
        return (
            uint80(currentRoundId),
            int256(price),
            cacheTimestamp > 0 ? cacheTimestamp : block.timestamp,
            cacheTimestamp > 0 ? cacheTimestamp : block.timestamp,
            uint80(currentRoundId)
        );
    }

    /// @inheritdoc INeverlandDustHelper
    function getRoundData(uint80 requestRoundId)
        external
        view
        override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        if (requestRoundId > currentRoundId || requestRoundId == 0) {
            revert InvalidRoundId(requestRoundId);
        }

        RoundData memory round = rounds[requestRoundId];
        return (requestRoundId, int256(round.answer), round.startedAt, round.timestamp, requestRoundId);
    }

    /// @inheritdoc INeverlandDustHelper
    function latestAnswer() external view override returns (int256 price) {
        (uint256 p,) = getPrice();
        return int256(p);
    }

    /// @inheritdoc INeverlandDustHelper
    function latestTimestamp() external view override returns (uint256 timestamp) {
        return cacheTimestamp > 0 ? cacheTimestamp : block.timestamp;
    }

    /// @inheritdoc INeverlandDustHelper
    function latestRound() external view override returns (uint256 roundId) {
        return currentRoundId;
    }

    /// @inheritdoc INeverlandDustHelper
    function getAnswer(uint256 roundId) external view override returns (int256 answer) {
        if (roundId > currentRoundId || roundId == 0) {
            revert InvalidRoundId(roundId);
        }
        return int256(rounds[roundId].answer);
    }

    /// @inheritdoc INeverlandDustHelper
    function getTimestamp(uint256 roundId) external view override returns (uint256 timestamp) {
        if (roundId > currentRoundId || roundId == 0) {
            revert InvalidRoundId(roundId);
        }
        return rounds[roundId].timestamp;
    }

    /// @inheritdoc INeverlandDustHelper
    function decimals() external pure override returns (uint8) {
        return PRICE_DECIMALS;
    }

    /// @inheritdoc INeverlandDustHelper
    function description() external pure override returns (string memory) {
        return "DUST / USD";
    }

    /// @inheritdoc INeverlandDustHelper
    function version() external pure override returns (uint256) {
        return 1;
    }
}
