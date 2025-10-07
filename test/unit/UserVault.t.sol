// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "../BaseTestLocal.sol";
import {HarnessFactory} from "../harness/HarnessFactory.sol";
import {UserVaultHarness} from "../harness/UserVaultHarness.sol";
import {IUserVault} from "../../src/interfaces/IUserVault.sol";
import {MockERC20} from "../_utils/MockERC20.sol";

contract RevenueRewardsTest is BaseTestLocal {
    HarnessFactory harnessFactory;

    MockERC20 mockWETH;
    MockERC20 mockWMON;

    // Oracle prices (8 decimals to match Aave format)
    uint256 constant USDC_PRICE = 1e8; // $1.00
    uint256 constant WMON_PRICE = 3e8; // $3.00
    uint256 constant WETH_PRICE = 4000e8; // $4000.00

    function _setUp() internal override {
        harnessFactory = new HarnessFactory();

        mockWETH = new MockERC20("WETH", "WETH", 18);
        mockWMON = new MockERC20("WMON", "WMON", 18);
    }

    function testVerifySlippage() public {
        // arrange
        (UserVaultHarness _userVault,,,) =
            harnessFactory.createUserVaultHarness(user, revenueReward, poolAddressesProviderRegistry, automation);

        // Test 1: Exactly 1% slippage, should pass with 1% max
        // 1000 USDC ($1000) -> 0.2475 WETH ($990 at $4000/WETH) = 1% slippage
        _userVault.exposed_verifySlippage(
            address(mockUSDC),
            1000 * 1e6, // 1000 USDC
            USDC_PRICE,
            address(mockWETH),
            2475 * 1e14, // 0.2475 WETH
            WETH_PRICE,
            100 // 1% max slippage
        );

        // Test 2: 1% slippage should revert with 0.99% max
        vm.expectRevert(IUserVault.SlippageExceeded.selector);
        _userVault.exposed_verifySlippage(
            address(mockUSDC),
            1000 * 1e6,
            USDC_PRICE,
            address(mockWETH),
            2475 * 1e14,
            WETH_PRICE,
            99 // 0.99% max
        );

        // Test 3: Favorable trade (getting more than expected, no slippage check needed)
        _userVault.exposed_verifySlippage(
            address(mockUSDC),
            1000 * 1e6, // 1000 USDC ($1000)
            USDC_PRICE,
            address(mockWETH),
            255 * 1e15, // 0.255 WETH ($1020 at $4000/WETH) - better than expected
            WETH_PRICE,
            100
        );
    }

    function testVerifySlippage_DecimalMismatchBug() public {
        (UserVaultHarness _userVault,,,) =
            harnessFactory.createUserVaultHarness(user, revenueReward, poolAddressesProviderRegistry, automation);

        /* ========== SCENARIO 1: USDC → WETH (6 decimals → 18 decimals) - Fair trade ========== */
        emit log("SCENARIO 1: USDC (6 dec) -> WETH (18 dec)");
        emit log("Swapping 1000 USDC for 0.25 WETH (fair trade)");

        {
            uint256 usdcIn = 1000 * 1e6; // 1000 USDC (6 decimals)
            uint256 wethOut = 25 * 1e16; // 0.25 WETH (18 decimals) = $1000 at $4000/WETH

            emit log("  Input: 1000 USDC ($1000 USD)");
            emit log("  Output: 0.25 WETH ($1000 USD at $4000/WETH)");

            // Fair trade should pass
            _userVault.exposed_verifySlippage(
                address(mockUSDC),
                usdcIn,
                USDC_PRICE,
                address(mockWETH),
                wethOut,
                WETH_PRICE,
                1000 // 10% max slippage
            );
        }

        /* ========== SCENARIO 2: USDC → WETH - 50% slippage (should REJECT) ========== */
        emit log("SCENARIO 2: USDC (6 dec) -> WETH (18 dec)");
        emit log("Testing with 50% slippage - should REJECT!");

        {
            uint256 usdcIn = 1_000 * 1e6; // 1,000 USDC (6 decimals)
            uint256 wethOut = 125 * 1e15; // 0.125 WETH = $500 at $4000/WETH (50% loss!)

            emit log("  Input: 1,000 USDC ($1,000 USD)");
            emit log("  Output: 0.125 WETH ($500 USD) - 50% LOSS!");

            // Properly rejects 50% slippage when max is 1%
            vm.expectRevert(IUserVault.SlippageExceeded.selector);
            _userVault.exposed_verifySlippage(
                address(mockUSDC),
                usdcIn,
                USDC_PRICE,
                address(mockWETH),
                wethOut,
                WETH_PRICE,
                100 // 1% max slippage
            );
        }

        /* ========== SCENARIO 3: USDC → WMON (6 decimals → 18 decimals) - 1% slippage ========== */
        emit log("SCENARIO 3: USDC (6 dec) -> WMON (18 dec)");
        emit log("1% slippage test");

        {
            uint256 usdcIn = 1_000 * 1e6; // 1,000 USDC (6 decimals)
            uint256 wmonOut = 33 * 1e19; // 330 WMON = $990 at $3/WMON (1% slippage)

            emit log("  Input: 1,000 USDC ($1,000)");
            emit log("  Output: 330 WMON ($990 at $3/WMON) - 1% slippage");

            // This passes correctly (within 1% limit)
            _userVault.exposed_verifySlippage(
                address(mockUSDC),
                usdcIn,
                USDC_PRICE,
                address(mockWMON),
                wmonOut,
                WMON_PRICE,
                100 // 1% max slippage
            );
        }

        /* ========== SCENARIO 4: USDC → WMON - Edge case with small amounts ========== */
        emit log("SCENARIO 4: USDC (6 dec) -> WMON (18 dec) - Small amounts");
        emit log("Testing with 20 USDC -> 6.6 WMON (1% slippage)");

        {
            uint256 usdcIn = 20 * 1e6; // 20 USDC (6 decimals)
            uint256 wmonOut = 66 * 1e17; // 6.6 WMON = $19.8 at $3/WMON (1% slippage)

            emit log("  Input: 20 USDC ($20)");
            emit log("  Output: 6.6 WMON ($19.8 at $3/WMON) - 1% slippage");

            // This passes correctly
            _userVault.exposed_verifySlippage(
                address(mockUSDC),
                usdcIn,
                USDC_PRICE,
                address(mockWMON),
                wmonOut,
                WMON_PRICE,
                100 // 1% max slippage
            );
        }
    }
}
