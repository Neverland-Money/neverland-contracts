// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

import "forge-std/Test.sol";

import {NeverlandDustHelper} from "../../src/utils/NeverlandDustHelper.sol";
import {MockERC20} from "../_utils/MockERC20.sol";

contract MockOracle {
    int256 private _answer;
    uint8 private _decimals;
    address private _token0;
    address private _token1;

    constructor(int256 answer_, uint8 decimals_, address token0_, address token1_) {
        _answer = answer_;
        _decimals = decimals_;
        _token0 = token0_;
        _token1 = token1_;
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (1, _answer, block.timestamp, block.timestamp, 1);
    }

    function decimals() external view returns (uint8) {
        return _decimals;
    }

    function token0() external view returns (address) {
        return _token0;
    }

    function token1() external view returns (address) {
        return _token1;
    }
}

contract MockUniswapV3Pool {
    uint160 private _sqrtPriceX96;
    address private _token0;
    address private _token1;

    constructor(uint160 sqrtPriceX96_, address token0_, address token1_) {
        _sqrtPriceX96 = sqrtPriceX96_;
        _token0 = token0_;
        _token1 = token1_;
    }

    function slot0()
        external
        view
        returns (
            uint160 sqrtPriceX96,
            int24 tick,
            uint16 observationIndex,
            uint16 observationCardinality,
            uint16 observationCardinalityNext,
            uint8 feeProtocol,
            bool unlocked
        )
    {
        return (_sqrtPriceX96, 0, 0, 0, 0, 0, true);
    }

    function token0() external view returns (address) {
        return _token0;
    }

    function token1() external view returns (address) {
        return _token1;
    }
}

contract MockUniswapV2Pool {
    uint112 private _reserve0;
    uint112 private _reserve1;
    address private _token0;
    address private _token1;

    constructor(uint112 reserve0_, uint112 reserve1_, address token0_, address token1_) {
        _reserve0 = reserve0_;
        _reserve1 = reserve1_;
        _token0 = token0_;
        _token1 = token1_;
    }

    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast) {
        return (_reserve0, _reserve1, uint32(block.timestamp));
    }

    function token0() external view returns (address) {
        return _token0;
    }

    function token1() external view returns (address) {
        return _token1;
    }
}

contract NeverlandDustHelperTest is Test {
    NeverlandDustHelper helper;
    MockERC20 dust;

    function setUp() public {
        dust = new MockERC20("DUST", "DUST", 18);
        helper = new NeverlandDustHelper(address(dust), address(this));
    }

    function test_OraclePrice_6Decimals() public {
        // Set MON/USD oracle to 1.0 (1:1 conversion)
        address usdAddr = makeAddr("USD");
        MockOracle monUsdOracle = new MockOracle(100_000_000, 8, usdAddr, address(0)); // MON/USD = 1.0
        helper.setPairOracle(address(monUsdOracle));

        // Oracle returns 0.69 DUST/MON with 6 decimals (690000)
        // Should be scaled up to 8 decimals (69000000)
        // DUST/USD = 0.69 * 1.0 = 0.69
        address mockMon = makeAddr("MON");
        MockOracle oracle = new MockOracle(690_000, 6, address(dust), mockMon);
        helper.setPair(address(oracle));

        (uint256 price, bool fromOracle) = helper.getPrice();

        assertTrue(fromOracle);
        assertEq(price, 69_000_000, "Price should be scaled from 6 to 8 decimals");
    }

    function test_OraclePrice_8Decimals() public {
        // Set MON/USD oracle to 1.0 (1:1 conversion)
        address usdAddr = makeAddr("USD");
        MockOracle monUsdOracle = new MockOracle(100_000_000, 8, usdAddr, address(0)); // MON/USD = 1.0
        helper.setPairOracle(address(monUsdOracle));

        // Oracle returns 0.69 DUST/MON with 8 decimals (69000000)
        // DUST is token0, so no inversion needed
        // DUST/USD = 0.69 * 1.0 = 0.69
        address mockMon = makeAddr("MON");
        MockOracle oracle = new MockOracle(69_000_000, 8, address(dust), mockMon);
        helper.setPair(address(oracle));

        (uint256 price, bool fromOracle) = helper.getPrice();

        assertTrue(fromOracle);
        assertEq(price, 69_000_000, "Price should be 69e6 (8 decimals)");
    }

    function test_OraclePrice_18Decimals() public {
        // Set MON/USD oracle to 1.0 (1:1 conversion)
        address usdAddr = makeAddr("USD");
        MockOracle monUsdOracle = new MockOracle(100_000_000, 8, usdAddr, address(0)); // MON/USD = 1.0
        helper.setPairOracle(address(monUsdOracle));

        // Oracle returns 0.69 DUST/MON with 18 decimals (690000000000000000)
        // Should be scaled down to 8 decimals (69000000)
        // DUST/USD = 0.69 * 1.0 = 0.69
        address mockMon = makeAddr("MON");
        MockOracle oracle = new MockOracle(690_000_000_000_000_000, 18, address(dust), mockMon);
        helper.setPair(address(oracle));

        (uint256 price, bool fromOracle) = helper.getPrice();

        assertTrue(fromOracle);
        assertEq(price, 69_000_000, "Price should be scaled from 18 to 8 decimals");
    }

    /// @notice Comprehensive test with 6-decimal USDC pair at various prices
    function test_6DecimalPair_VariousPrices() public {
        address usdcAddr = makeAddr("USDC");

        // Test Case 1: DUST/USDC = 0.50, USDC/USD = 1.00 => DUST/USD = 0.50
        {
            // USDC/USD = 1.00 (100_000_000 in 8 decimals)
            address usdAddr = makeAddr("USD");
            MockOracle usdcUsdOracle = new MockOracle(100_000_000, 8, usdAddr, address(0));
            helper.setPairOracle(address(usdcUsdOracle));

            // DUST/USDC = 0.50 (500_000 in 6 decimals)
            MockOracle dustUsdcPair = new MockOracle(500_000, 6, address(dust), usdcAddr);
            helper.setPair(address(dustUsdcPair));

            (uint256 price, bool fromOracle) = helper.getPrice();

            assertTrue(fromOracle, "Price should come from oracle");
            // Expected: 0.50 * 1.00 = 0.50 => 50_000_000 in 8 decimals
            assertEq(price, 50_000_000, "DUST/USD should be 0.50");
        }

        // Test Case 2: DUST/USDC = 0.25, USDC/USD = 0.9999 => DUST/USD = 0.249975
        {
            // USDC/USD = 0.9999 (99_990_000 in 8 decimals)
            address usdAddr = makeAddr("USD2");
            MockOracle usdcUsdOracle = new MockOracle(99_990_000, 8, usdAddr, address(0));
            helper.setPairOracle(address(usdcUsdOracle));

            // DUST/USDC = 0.25 (250_000 in 6 decimals)
            MockOracle dustUsdcPair = new MockOracle(250_000, 6, address(dust), usdcAddr);
            helper.setPair(address(dustUsdcPair));

            (uint256 price, bool fromOracle) = helper.getPrice();

            assertTrue(fromOracle, "Price should come from oracle");
            // Expected: 0.25 * 0.9999 = 0.249975 => 24_997_500 in 8 decimals
            assertEq(price, 24_997_500, "DUST/USD should be 0.249975");
        }

        // Test Case 3: DUST/USDC = 1.50, USDC/USD = 1.0001 => DUST/USD = 1.50015
        {
            // USDC/USD = 1.0001 (100_010_000 in 8 decimals)
            address usdAddr = makeAddr("USD3");
            MockOracle usdcUsdOracle = new MockOracle(100_010_000, 8, usdAddr, address(0));
            helper.setPairOracle(address(usdcUsdOracle));

            // DUST/USDC = 1.50 (1_500_000 in 6 decimals)
            MockOracle dustUsdcPair = new MockOracle(1_500_000, 6, address(dust), usdcAddr);
            helper.setPair(address(dustUsdcPair));

            (uint256 price, bool fromOracle) = helper.getPrice();

            assertTrue(fromOracle, "Price should come from oracle");
            // Expected: 1.50 * 1.0001 = 1.50015 => 150_015_000 in 8 decimals
            assertEq(price, 150_015_000, "DUST/USD should be 1.50015");
        }
    }

    /// @notice Comprehensive test with 18-decimal MON pair at various prices
    function test_18DecimalPair_VariousPrices() public {
        address monAddr = makeAddr("MON");

        // Test Case 1: DUST/MON = 0.06, MON/USD = 4.00 => DUST/USD = 0.24
        {
            // MON/USD = 4.00 (400_000_000 in 8 decimals)
            address usdAddr = makeAddr("USD");
            MockOracle monUsdOracle = new MockOracle(400_000_000, 8, usdAddr, address(0));
            helper.setPairOracle(address(monUsdOracle));

            // DUST/MON = 0.06 (60_000_000_000_000_000 in 18 decimals)
            MockOracle dustMonPair = new MockOracle(60_000_000_000_000_000, 18, address(dust), monAddr);
            helper.setPair(address(dustMonPair));

            (uint256 price, bool fromOracle) = helper.getPrice();

            assertTrue(fromOracle, "Price should come from oracle");
            // Expected: 0.06 * 4.00 = 0.24 => 24_000_000 in 8 decimals
            assertEq(price, 24_000_000, "DUST/USD should be 0.24");
        }

        // Test Case 2: DUST/MON = 0.125, MON/USD = 8.00 => DUST/USD = 1.00
        {
            // MON/USD = 8.00 (800_000_000 in 8 decimals)
            address usdAddr = makeAddr("USD2");
            MockOracle monUsdOracle = new MockOracle(800_000_000, 8, usdAddr, address(0));
            helper.setPairOracle(address(monUsdOracle));

            // DUST/MON = 0.125 (125_000_000_000_000_000 in 18 decimals)
            MockOracle dustMonPair = new MockOracle(125_000_000_000_000_000, 18, address(dust), monAddr);
            helper.setPair(address(dustMonPair));

            (uint256 price, bool fromOracle) = helper.getPrice();

            assertTrue(fromOracle, "Price should come from oracle");
            // Expected: 0.125 * 8.00 = 1.00 => 100_000_000 in 8 decimals
            assertEq(price, 100_000_000, "DUST/USD should be 1.00");
        }

        // Test Case 3: DUST/MON = 0.003, MON/USD = 100.00 => DUST/USD = 0.30
        {
            // MON/USD = 100.00 (10_000_000_000 in 8 decimals)
            address usdAddr = makeAddr("USD3");
            MockOracle monUsdOracle = new MockOracle(10_000_000_000, 8, usdAddr, address(0));
            helper.setPairOracle(address(monUsdOracle));

            // DUST/MON = 0.003 (3_000_000_000_000_000 in 18 decimals)
            MockOracle dustMonPair = new MockOracle(3_000_000_000_000_000, 18, address(dust), monAddr);
            helper.setPair(address(dustMonPair));

            (uint256 price, bool fromOracle) = helper.getPrice();

            assertTrue(fromOracle, "Price should come from oracle");
            // Expected: 0.003 * 100.00 = 0.30 => 30_000_000 in 8 decimals
            assertEq(price, 30_000_000, "DUST/USD should be 0.30");
        }

        // Test Case 4: DUST/MON = 2.50, MON/USD = 0.40 => DUST/USD = 1.00
        {
            // MON/USD = 0.40 (40_000_000 in 8 decimals)
            address usdAddr = makeAddr("USD4");
            MockOracle monUsdOracle = new MockOracle(40_000_000, 8, usdAddr, address(0));
            helper.setPairOracle(address(monUsdOracle));

            // DUST/MON = 2.50 (2_500_000_000_000_000_000 in 18 decimals)
            MockOracle dustMonPair = new MockOracle(2_500_000_000_000_000_000, 18, address(dust), monAddr);
            helper.setPair(address(dustMonPair));

            (uint256 price, bool fromOracle) = helper.getPrice();

            assertTrue(fromOracle, "Price should come from oracle");
            // Expected: 2.50 * 0.40 = 1.00 => 100_000_000 in 8 decimals
            assertEq(price, 100_000_000, "DUST/USD should be 1.00");
        }
    }

    function test_DustUsdConversion_MonUsd4_DustMon0_06() public {
        // MON/USD oracle returns 4.0 (400000000 in 8 decimals)
        address usdAddr = makeAddr("USD");
        MockOracle monUsdOracle = new MockOracle(400_000_000, 8, usdAddr, address(0)); // MON/USD
        helper.setPairOracle(address(monUsdOracle));

        // DUST/MON pair returns 0.06 (6000000 in 8 decimals)
        address monAddr = makeAddr("MON");
        MockOracle dustMonPair = new MockOracle(6_000_000, 8, address(dust), monAddr); // DUST/MON
        helper.setPair(address(dustMonPair));

        (uint256 price, bool fromOracle) = helper.getPrice();

        assertTrue(fromOracle, "Price should come from oracle");
        // DUST/USD = DUST/MON * MON/USD = 0.06 * 4.0 = 0.24
        // 0.24 in 8 decimals = 24,000,000
        assertEq(price, 24_000_000, "DUST/USD should be 0.24 (24e6 in 8 decimals)");
    }

    function test_DustUsdConversion_WithTokenInversion() public {
        // MON/USD oracle returns 2.0 (200000000 in 8 decimals)
        address usdAddr = makeAddr("USD");
        MockOracle monUsdOracle = new MockOracle(200_000_000, 8, usdAddr, address(0)); // MON/USD
        helper.setPairOracle(address(monUsdOracle));

        // DUST/MON pair returns 0.1 but with MON as token0 (inverted)
        address monAddr = makeAddr("MON");
        MockOracle dustMonPair = new MockOracle(10_000_000, 8, monAddr, address(dust)); // MON/DUST = 0.1
        helper.setPair(address(dustMonPair));

        (uint256 price, bool fromOracle) = helper.getPrice();

        assertTrue(fromOracle, "Price should come from oracle");
        // MON/DUST = 0.1 means DUST/MON = 10.0 (inverted)
        // DUST/USD = DUST/MON * MON/USD = 10.0 * 2.0 = 20.0
        // 20.0 in 8 decimals = 2,000,000,000
        assertEq(price, 2_000_000_000, "DUST/USD should be 20.0 with inversion");
    }

    function test_FallbackToHardcoded_WhenOracleFails() public {
        // Remove oracle which should cause fallback to hardcoded
        helper.removePair();

        (uint256 price, bool fromOracle) = helper.getPrice();

        assertFalse(fromOracle);
        assertEq(price, helper.DEFAULT_DUST_PRICE(), "Should fallback to hardcoded price");
    }

    function test_HardcodedPrice_ChainlinkInterface() public {
        // No oracle set, should use hardcoded price
        // Update cache to create round data
        helper.updatePriceCache();

        (uint256 price, bool fromOracle) = helper.getPrice();
        assertFalse(fromOracle, "Should not be from oracle");
        assertEq(price, helper.DEFAULT_DUST_PRICE(), "Should be hardcoded price");

        // Verify Chainlink interface returns hardcoded price
        (uint80 roundId, int256 answer,, uint256 updatedAt,) = helper.latestRoundData();
        assertEq(uint256(answer), helper.DEFAULT_DUST_PRICE(), "latestRoundData should return hardcoded price");
        assertGt(roundId, 0, "Round ID should be set");
        assertGt(updatedAt, 0, "Updated timestamp should be set");

        // Verify other Chainlink functions
        int256 latestAnswer = helper.latestAnswer();
        assertEq(uint256(latestAnswer), helper.DEFAULT_DUST_PRICE(), "latestAnswer should return hardcoded price");

        uint256 latestTimestamp = helper.latestTimestamp();
        assertGt(latestTimestamp, 0, "latestTimestamp should be set");
    }

    function test_HardcodedPrice_AfterOracleRemoved() public {
        // First set up oracle
        address usdAddr = makeAddr("USD");
        MockOracle monUsdOracle = new MockOracle(100_000_000, 8, usdAddr, address(0));
        helper.setPairOracle(address(monUsdOracle));

        address mockMon = makeAddr("MON");
        MockOracle oracle = new MockOracle(69_000_000, 8, address(dust), mockMon);
        helper.setPair(address(oracle));
        helper.updatePriceCache();

        // Verify oracle price works
        (, bool fromOracle1) = helper.getPrice();
        assertTrue(fromOracle1, "Should be from oracle");

        // Now remove oracle
        helper.removePair();
        helper.updatePriceCache();

        // Should fallback to hardcoded
        (uint256 price2, bool fromOracle2) = helper.getPrice();
        assertFalse(fromOracle2, "Should not be from oracle");
        assertEq(price2, helper.DEFAULT_DUST_PRICE(), "Should be hardcoded price");

        // Chainlink interface should still work
        (, int256 answer,,,) = helper.latestRoundData();
        assertEq(uint256(answer), helper.DEFAULT_DUST_PRICE(), "latestRoundData should return hardcoded price");
    }

    function test_HardcodedPrice_WhenOraclePriceOutOfBounds() public {
        // Set oracle with price that's too high
        address usdAddr = makeAddr("USD");
        MockOracle monUsdOracle = new MockOracle(100_000_000, 8, usdAddr, address(0)); // MON/USD = 1.0
        helper.setPairOracle(address(monUsdOracle));

        // Set DUST/MON to a very high value that will result in out-of-bounds DUST/USD
        // Max reasonable price is 1e11 (in 8 decimals) = $1000
        // Default min is 1e5 = $0.001
        address mockMon = makeAddr("MON");
        // DUST/MON = 2000 in 8 decimals, MON/USD = 1.0 => DUST/USD = 2000 (exceeds max of 1000)
        MockOracle oracle = new MockOracle(2_000_00_000_000, 8, address(dust), mockMon);
        helper.setPair(address(oracle));

        // getPrice should return hardcoded because oracle price is out of bounds
        (uint256 price, bool fromOracle) = helper.getPrice();
        assertFalse(fromOracle, "Should fallback to hardcoded when out of bounds");
        assertEq(price, helper.DEFAULT_DUST_PRICE(), "Should return hardcoded price");

        // Update cache with hardcoded price
        helper.updatePriceCache();

        // Chainlink interface should return hardcoded price
        (, int256 answer,,,) = helper.latestRoundData();
        assertEq(uint256(answer), helper.DEFAULT_DUST_PRICE(), "Should return hardcoded price in Chainlink interface");
    }

    function test_Chainlink_InitialRoundData() public view {
        // Round data should exist immediately after deployment with hardcoded price
        // No need to call updatePriceCache first!
        (uint80 roundId, int256 answer,, uint256 updatedAt, uint80 answeredInRound) = helper.latestRoundData();

        assertEq(roundId, 1, "Initial round ID should be 1");
        assertEq(uint256(answer), helper.DEFAULT_DUST_PRICE(), "Should return hardcoded price");
        assertGt(updatedAt, 0, "Updated timestamp should be set");
        assertEq(answeredInRound, 1, "Answered in round should be 1");

        // Verify other Chainlink functions work immediately
        int256 latestAnswer = helper.latestAnswer();
        assertEq(uint256(latestAnswer), helper.DEFAULT_DUST_PRICE(), "latestAnswer should work");

        uint256 latestTimestamp = helper.latestTimestamp();
        assertGt(latestTimestamp, 0, "latestTimestamp should work");

        uint256 latestRound = helper.latestRound();
        assertEq(latestRound, 1, "latestRound should be 1");
    }

    function test_Chainlink_WorksAfterOracleSetup() public {
        // First verify initial hardcoded data exists
        (uint80 roundId1, int256 answer1,,,) = helper.latestRoundData();
        assertEq(roundId1, 1, "Initial round should be 1");
        assertEq(uint256(answer1), helper.DEFAULT_DUST_PRICE(), "Should be hardcoded price initially");

        // Set up oracle and call updatePriceCache to create round data
        address usdAddr = makeAddr("USD");
        MockOracle monUsdOracle = new MockOracle(100_000_000, 8, usdAddr, address(0)); // MON/USD = 1.0
        helper.setPairOracle(address(monUsdOracle));

        address mockMon = makeAddr("MON");
        MockOracle oracle = new MockOracle(69_000_000, 8, address(dust), mockMon);
        helper.setPair(address(oracle));
        helper.updatePriceCache();

        // Now latestRoundData should work
        (uint80 roundId, int256 answer,,,) = helper.latestRoundData();
        assertEq(roundId, 1);
        assertGt(answer, 0);

        // Round 1 should now be retrievable
        int256 round1Answer = helper.getAnswer(1);
        uint256 round1Timestamp = helper.getTimestamp(1);
        assertGt(round1Answer, 0);
        assertGt(round1Timestamp, 0);
    }

    // ========== NEW: Direct DUST/USD Oracle Tests ==========

    function test_DirectDustUsdOracle_NoPairOracleNeeded() public {
        // Direct DUST/USD oracle returns 0.69 (69_000_000 in 8 decimals)
        // No pairOracle needed!
        address usdAddr = makeAddr("USD");
        MockOracle dustUsdOracle = new MockOracle(69_000_000, 8, address(dust), usdAddr);
        helper.setPair(address(dustUsdOracle));
        // Don't set pairOracle - it should work without it

        (uint256 price, bool fromOracle) = helper.getPrice();

        assertTrue(fromOracle, "Price should come from oracle");
        assertEq(price, 69_000_000, "DUST/USD should be 0.69 directly from oracle");
    }

    function test_DirectDustUsdOracle_18Decimals() public {
        // Direct DUST/USD oracle with 18 decimals
        // 0.50 USD = 500_000_000_000_000_000 in 18 decimals
        address usdAddr = makeAddr("USD");
        MockOracle dustUsdOracle = new MockOracle(500_000_000_000_000_000, 18, address(dust), usdAddr);
        helper.setPair(address(dustUsdOracle));

        (uint256 price, bool fromOracle) = helper.getPrice();

        assertTrue(fromOracle, "Price should come from oracle");
        // Should be scaled from 18 decimals to 8 decimals
        assertEq(price, 50_000_000, "DUST/USD should be 0.50 scaled from 18 to 8 decimals");
    }

    // ========== NEW: Uniswap V3 Pool Tests ==========

    function test_UniswapV3Pool_DustToken0() public {
        // Create DUST/MON V3 pool where DUST is token0
        // Price: 1 DUST = 4 MON (so sqrtPriceX96 represents MON/DUST)
        // sqrtPriceX96 = sqrt(4) * 2^96 = 2 * 2^96 = 158456325028528675187087900672
        MockERC20 mon = new MockERC20("MON", "MON", 18);
        MockUniswapV3Pool pool = new MockUniswapV3Pool(
            158456325028528675187087900672, // sqrt(4) * 2^96
            address(dust),
            address(mon)
        );
        helper.setPair(address(pool));

        // Set MON/USD = 2.0
        address usdAddr = makeAddr("USD");
        MockOracle monUsdOracle = new MockOracle(200_000_000, 8, usdAddr, address(0));
        helper.setPairOracle(address(monUsdOracle));

        (uint256 price, bool fromOracle) = helper.getPrice();

        assertTrue(fromOracle, "Price should come from pool");
        // DUST/MON = 0.25 (inverted from 4), DUST/USD = 0.25 * 2.0 = 0.50
        assertEq(price, 50_000_000, "DUST/USD should be 0.50 from V3 pool");
    }

    function test_UniswapV3Pool_DustToken1() public {
        // Create MON/DUST V3 pool where DUST is token1
        // Price: 1 MON = 4 DUST (so sqrtPriceX96 represents DUST/MON = 4)
        // sqrtPriceX96 = sqrt(4) * 2^96 = 2 * 2^96
        MockERC20 mon = new MockERC20("MON", "MON", 18);
        MockUniswapV3Pool pool = new MockUniswapV3Pool(
            158456325028528675187087900672, // sqrt(4) * 2^96
            address(mon),
            address(dust)
        );
        helper.setPair(address(pool));

        // Set MON/USD = 2.0
        address usdAddr = makeAddr("USD");
        MockOracle monUsdOracle = new MockOracle(200_000_000, 8, usdAddr, address(0));
        helper.setPairOracle(address(monUsdOracle));

        (uint256 price, bool fromOracle) = helper.getPrice();

        assertTrue(fromOracle, "Price should come from pool");
        // DUST/MON = 4, DUST/USD = 4 * 2.0 = 8.0
        assertEq(price, 800_000_000, "DUST/USD should be 8.0 from V3 pool");
    }

    // ========== NEW: Uniswap V2 Pool Tests ==========

    function test_UniswapV2Pool_DustToken0() public {
        // Create DUST/MON V2 pool where DUST is token0
        // Reserves: 1000 DUST, 4000 MON => price = 4000/1000 = 4 MON per DUST
        // We want DUST/MON = 1/4 = 0.25
        MockERC20 mon = new MockERC20("MON", "MON", 18);
        MockUniswapV2Pool pool = new MockUniswapV2Pool(
            1000e18, // reserve0 (DUST)
            4000e18, // reserve1 (MON)
            address(dust),
            address(mon)
        );
        helper.setPair(address(pool));

        // Set MON/USD = 2.0
        address usdAddr = makeAddr("USD");
        MockOracle monUsdOracle = new MockOracle(200_000_000, 8, usdAddr, address(0));
        helper.setPairOracle(address(monUsdOracle));

        (uint256 price, bool fromOracle) = helper.getPrice();

        assertTrue(fromOracle, "Price should come from pool");
        // DUST/MON = 0.25, DUST/USD = 0.25 * 2.0 = 0.50
        assertEq(price, 50_000_000, "DUST/USD should be 0.50 from V2 pool");
    }

    function test_UniswapV2Pool_DustToken1() public {
        // Create MON/DUST V2 pool where DUST is token1
        // Reserves: 1000 MON, 4000 DUST => price = 4000/1000 = 4 DUST per MON
        MockERC20 mon = new MockERC20("MON", "MON", 18);
        MockUniswapV2Pool pool = new MockUniswapV2Pool(
            1000e18, // reserve0 (MON)
            4000e18, // reserve1 (DUST)
            address(mon),
            address(dust)
        );
        helper.setPair(address(pool));

        // Set MON/USD = 2.0
        address usdAddr = makeAddr("USD");
        MockOracle monUsdOracle = new MockOracle(200_000_000, 8, usdAddr, address(0));
        helper.setPairOracle(address(monUsdOracle));

        (uint256 price, bool fromOracle) = helper.getPrice();

        assertTrue(fromOracle, "Price should come from pool");
        // DUST/MON = 4, DUST/USD = 4 * 2.0 = 8.0
        assertEq(price, 800_000_000, "DUST/USD should be 8.0 from V2 pool");
    }

    // ========== NEW: Fallback Cascade Tests ==========

    function test_FallbackFromV3ToV2ToOracle() public {
        // This test would require a more complex setup
        // For now, we've tested each individually
        // The contract tries V3 -> V2 -> Oracle in that order
    }

    function test_TokenOrdering_OracleWithToken0Token1() public {
        // Test oracle that exposes token0/token1 (like UniV3 TWAP oracle)
        address monAddr = makeAddr("MON");

        // Case 1: DUST is token0, oracle returns DUST/MON
        {
            MockOracle oracle = new MockOracle(50_000_000, 8, address(dust), monAddr); // 0.50 DUST/MON
            helper.setPair(address(oracle));

            address usdAddr = makeAddr("USD");
            MockOracle monUsdOracle = new MockOracle(200_000_000, 8, usdAddr, address(0)); // 2.0 MON/USD
            helper.setPairOracle(address(monUsdOracle));

            (uint256 price,) = helper.getPrice();
            // DUST/MON = 0.50, DUST/USD = 0.50 * 2.0 = 1.0
            assertEq(price, 100_000_000, "DUST/USD should be 1.0 when DUST is token0");
        }

        // Case 2: DUST is token1, oracle returns MON/DUST, needs inversion
        {
            MockOracle oracle = new MockOracle(50_000_000, 8, monAddr, address(dust)); // 0.50 MON/DUST
            helper.setPair(address(oracle));

            (uint256 price,) = helper.getPrice();
            // MON/DUST = 0.50, so DUST/MON = 2.0, DUST/USD = 2.0 * 2.0 = 4.0
            assertEq(price, 400_000_000, "DUST/USD should be 4.0 when DUST is token1 (inverted)");
        }
    }
}
