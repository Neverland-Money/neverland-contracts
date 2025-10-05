// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

import "forge-std/Test.sol";
import {NeverlandDustHelper} from "../../src/utils/NeverlandDustHelper.sol";
import {INeverlandDustHelper} from "../../src/interfaces/INeverlandDustHelper.sol";
import {MockERC20} from "../_utils/MockERC20.sol";

contract MockV3Pool {
    address public token0;
    address public token1;
    uint160 private _sqrtPriceX96;

    constructor(address _t0, address _t1, uint160 sqrtPriceX96_) {
        token0 = _t0;
        token1 = _t1;
        _sqrtPriceX96 = sqrtPriceX96_;
    }

    function slot0() external view returns (uint160 sqrtPriceX96, int24, uint16, uint16, uint16, uint8, bool) {
        return (_sqrtPriceX96, 0, 0, 0, 0, 0, false);
    }
}

contract MockV2Pair {
    address public token0;
    address public token1;
    uint112 r0;
    uint112 r1;

    constructor(address _t0, address _t1, uint112 _r0, uint112 _r1) {
        token0 = _t0;
        token1 = _t1;
        r0 = _r0;
        r1 = _r1;
    }

    function getReserves() external view returns (uint112, uint112, uint32) {
        return (r0, r1, 0);
    }
}

contract NeverlandDustHelperTest is Test {
    NeverlandDustHelper helper;
    MockERC20 dust;
    MockERC20 usdc;

    function setUp() public {
        dust = new MockERC20("DUST", "DUST", 18);
        // Test USDC (6 decimals) path
        usdc = new MockERC20("USDC", "USDC", 6);
        helper = new NeverlandDustHelper(address(dust), address(this));
    }

    function test_UniswapV3Price_Parity() public {
        // Target price = 0.69 USD (8 decimals => 69_000_000)
        // For V3 with DUST = token0, USD per DUST = (priceX192 / Q192) * 10^(dec0 - dec1) * 1e8
        // Rearranged: priceX192 = (price * Q192 * 10^dec1) / (1e8 * 10^dec0)
        uint256 Q192 = uint256(1) << 192;
        uint8 d0 = 18; // DUST
        uint8 d1 = usdc.decimals(); // 6
        uint256 targetX192 = (Q192 * 69_000_000 * (10 ** uint256(d1))) / (1e8 * (10 ** uint256(d0)));
        uint160 sqrtPriceX96 = uint160(_sqrt(targetX192));
        MockV3Pool pool = new MockV3Pool(address(dust), address(usdc), sqrtPriceX96);
        helper.setUniswapPair(address(pool));

        (uint256 price, bool fromUni) = helper.getPrice();

        emit log_named_uint("Price", price);

        assertTrue(fromUni);
        // Allow 1 unit rounding tolerance from sqrt/quantization
        assertApproxEqAbs(price, 69_000_000, 1, "0.69 price should be ~69e6 (8 decimals)");
    }

    function test_UniswapV2Price_Parity() public {
        // price = reserve1 / reserve0 * 10^d0 / 10^d1 = 0.69
        // Choose large reserves to keep integer math precise
        MockV2Pair pair = new MockV2Pair(address(dust), address(usdc), 1_000_000 ether, 690_000_000_000);
        helper.setUniswapPair(address(pair));

        (uint256 price, bool fromUni) = helper.getPrice();

        emit log_named_uint("Price", price);

        assertTrue(fromUni);
        assertEq(price, 69_000_000, "0.69 price should be 69e6 (8 decimals)");
    }

    function _sqrt(uint256 x) internal pure returns (uint256 z) {
        if (x == 0) return 0;
        // Initial guess: 2^(log2(x)/2)
        uint256 y = x;
        z = 1;
        if (y >= 0x100000000000000000000000000000000) {
            y >>= 128;
            z <<= 64;
        }
        if (y >= 0x10000000000000000) {
            y >>= 64;
            z <<= 32;
        }
        if (y >= 0x100000000) {
            y >>= 32;
            z <<= 16;
        }
        if (y >= 0x10000) {
            y >>= 16;
            z <<= 8;
        }
        if (y >= 0x100) {
            y >>= 8;
            z <<= 4;
        }
        if (y >= 0x10) {
            y >>= 4;
            z <<= 2;
        }
        if (y >= 0x8) z <<= 1;
        // Babylonian method
        for (uint256 i; i < 7; ++i) {
            z = (z + x / z) >> 1;
        }
        uint256 z1 = x / z;
        if (z1 < z) z = z1;
    }
}
