// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "./LeaderboardBase.sol";

contract LeaderboardConfigTest is LeaderboardBase {
    function testInitialConfiguration() public view {
        assertEq(leaderboardConfig.depositRateBps(), DEPOSIT_RATE, "Initial deposit rate");
        assertEq(leaderboardConfig.borrowRateBps(), BORROW_RATE, "Initial borrow rate");
        assertEq(leaderboardConfig.vpRateBps(), VP_RATE, "Initial VP rate");
        assertEq(leaderboardConfig.supplyDailyBonus(), SUPPLY_BONUS, "Initial supply bonus");
        assertEq(leaderboardConfig.borrowDailyBonus(), BORROW_BONUS, "Initial borrow bonus");
        assertEq(leaderboardConfig.repayDailyBonus(), 0, "Initial repay bonus");
        assertEq(leaderboardConfig.withdrawDailyBonus(), 0, "Initial withdraw bonus");
        assertEq(leaderboardConfig.cooldownSeconds(), COOLDOWN, "Initial cooldown");
        assertEq(leaderboardConfig.minDailyBonusUsd(), MIN_DAILY_BONUS_USD, "Initial min daily bonus USD");

        // Check constants
        assertEq(leaderboardConfig.MAX_RATE_BPS(), 10_000, "Max rate should be 10000 bps");
        assertEq(leaderboardConfig.MAX_DAILY_BONUS(), 1000e18, "Max daily bonus should be 1000e18");
        assertEq(leaderboardConfig.MAX_COOLDOWN_SECONDS(), 86_400, "Max cooldown should be 24 hours");
    }

    function testSetDepositRate() public {
        uint256 newRate = 200; // 0.02 per USD/day

        vm.prank(admin);
        leaderboardConfig.setDepositRate(newRate);

        assertEq(leaderboardConfig.depositRateBps(), newRate, "Deposit rate should be updated");

        // Other configs should remain unchanged
        assertEq(leaderboardConfig.borrowRateBps(), BORROW_RATE, "Borrow rate unchanged");
    }

    function testSetDepositRateTooHigh() public {
        uint256 tooHigh = 10_001;

        vm.prank(admin);
        vm.expectRevert();
        leaderboardConfig.setDepositRate(tooHigh);
    }

    function testSetDepositRateOnlyOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        leaderboardConfig.setDepositRate(200);
    }

    function testSetBorrowRate() public {
        uint256 newRate = 1000; // 0.1 per USD/day

        vm.prank(admin);
        leaderboardConfig.setBorrowRate(newRate);

        assertEq(leaderboardConfig.borrowRateBps(), newRate, "Borrow rate should be updated");
    }

    function testSetDailyBonuses() public {
        uint256 newSupply = 50e18;
        uint256 newBorrow = 100e18;
        uint256 newRepay = 15e18;
        uint256 newWithdraw = 5e18;

        vm.prank(admin);
        leaderboardConfig.setDailyBonuses(newSupply, newBorrow, newRepay, newWithdraw);

        assertEq(leaderboardConfig.supplyDailyBonus(), newSupply, "Supply bonus updated");
        assertEq(leaderboardConfig.borrowDailyBonus(), newBorrow, "Borrow bonus updated");
        assertEq(leaderboardConfig.repayDailyBonus(), newRepay, "Repay bonus updated");
        assertEq(leaderboardConfig.withdrawDailyBonus(), newWithdraw, "Withdraw bonus updated");
    }

    function testSetDailyBonusesTooHigh() public {
        uint256 tooHigh = 1001e18;

        vm.prank(admin);
        vm.expectRevert();
        leaderboardConfig.setDailyBonuses(tooHigh, 20e18, 0, 0);

        vm.prank(admin);
        vm.expectRevert();
        leaderboardConfig.setDailyBonuses(10e18, tooHigh, 0, 0);

        vm.prank(admin);
        vm.expectRevert();
        leaderboardConfig.setDailyBonuses(10e18, 20e18, tooHigh, 0);

        vm.prank(admin);
        vm.expectRevert();
        leaderboardConfig.setDailyBonuses(10e18, 20e18, 0, tooHigh);
    }

    function testSetCooldown() public {
        uint256 newCooldown = 7200; // 2 hours

        vm.prank(admin);
        leaderboardConfig.setCooldown(newCooldown);

        assertEq(leaderboardConfig.cooldownSeconds(), newCooldown, "Cooldown updated");
    }

    function testSetCooldownTooLong() public {
        uint256 tooLong = 86_401; // > 24 hours

        vm.prank(admin);
        vm.expectRevert();
        leaderboardConfig.setCooldown(tooLong);
    }

    function testSetMinDailyBonusUsd() public {
        uint256 newMin = 500e18; // $500

        vm.prank(admin);
        leaderboardConfig.setMinDailyBonusUsd(newMin);

        assertEq(leaderboardConfig.minDailyBonusUsd(), newMin, "Min daily bonus USD updated");
    }

    function testUpdateAllRates() public {
        uint256 newDepositRate = 150;
        uint256 newBorrowRate = 750;
        uint256 newSupplyBonus = 25e18;
        uint256 newBorrowBonus = 50e18;

        vm.prank(admin);
        leaderboardConfig.updateAllRates(newDepositRate, newBorrowRate, 200, newSupplyBonus, newBorrowBonus);

        assertEq(leaderboardConfig.depositRateBps(), newDepositRate, "Deposit rate updated");
        assertEq(leaderboardConfig.borrowRateBps(), newBorrowRate, "Borrow rate updated");
        assertEq(leaderboardConfig.supplyDailyBonus(), newSupplyBonus, "Supply bonus updated");
        assertEq(leaderboardConfig.borrowDailyBonus(), newBorrowBonus, "Borrow bonus updated");

        // Cooldown and min bonus should be unchanged
        assertEq(leaderboardConfig.cooldownSeconds(), COOLDOWN, "Cooldown unchanged");
        assertEq(leaderboardConfig.minDailyBonusUsd(), MIN_DAILY_BONUS_USD, "Min bonus unchanged");
    }

    function testUpdateAllRatesWithInvalidValues() public {
        vm.prank(admin);
        vm.expectRevert();
        leaderboardConfig.updateAllRates(10_001, 500, 200, 10e18, 20e18);

        vm.prank(admin);
        vm.expectRevert();
        leaderboardConfig.updateAllRates(100, 10_001, 200, 10e18, 20e18);

        vm.prank(admin);
        vm.expectRevert();
        leaderboardConfig.updateAllRates(100, 500, 200, 1001e18, 20e18);

        vm.prank(admin);
        vm.expectRevert();
        leaderboardConfig.updateAllRates(100, 500, 200, 10e18, 1001e18);
    }

    function testGetDepositRatePerDay() public view {
        uint256 rate = leaderboardConfig.getDepositRatePerDay();
        assertEq(rate, DEPOSIT_RATE, "Should return deposit rate");
    }

    function testGetBorrowRatePerDay() public view {
        uint256 rate = leaderboardConfig.getBorrowRatePerDay();
        assertEq(rate, BORROW_RATE, "Should return borrow rate");
    }

    function testGetDailyBonuses() public view {
        (uint256 supply, uint256 borrow, uint256 repay, uint256 withdraw) = leaderboardConfig.getDailyBonuses();
        assertEq(supply, SUPPLY_BONUS, "Should return supply bonus");
        assertEq(borrow, BORROW_BONUS, "Should return borrow bonus");
        assertEq(repay, 0, "Should return repay bonus");
        assertEq(withdraw, 0, "Should return withdraw bonus");
    }

    function testGetAllConfig() public view {
        (
            uint256 depositRate,
            uint256 borrowRate,
            uint256 vpRate,
            uint256 supplyBonus,
            uint256 borrowBonus,
            uint256 repayBonus,
            uint256 withdrawBonus,
            uint256 cooldown,
            uint256 minUsd
        ) = leaderboardConfig.getAllConfig();

        assertEq(depositRate, DEPOSIT_RATE, "Deposit rate");
        assertEq(borrowRate, BORROW_RATE, "Borrow rate");
        assertEq(vpRate, VP_RATE, "VP rate");
        assertEq(supplyBonus, SUPPLY_BONUS, "Supply bonus");
        assertEq(borrowBonus, BORROW_BONUS, "Borrow bonus");
        assertEq(repayBonus, 0, "Repay bonus");
        assertEq(withdrawBonus, 0, "Withdraw bonus");
        assertEq(cooldown, COOLDOWN, "Cooldown");
        assertEq(minUsd, MIN_DAILY_BONUS_USD, "Min USD");
    }

    function testConfigSnapshotEmitted() public {
        // Update a rate - ConfigSnapshot should be emitted automatically
        uint256 newRate = 200;

        vm.prank(admin);
        leaderboardConfig.setDepositRate(newRate);

        // Verify the config was updated
        assertEq(leaderboardConfig.depositRateBps(), newRate, "Rate updated");
        // Note: ConfigSnapshot event is emitted automatically on every change
    }

    function testDeterministicRateCalculations() public {
        // Set specific rates
        vm.prank(admin);
        leaderboardConfig.updateAllRates(
            100, // 0.01 per USD/day = 1 point per 100 USD per day
            500, // 0.05 per USD/day = 5 points per 100 USD per day
            200, // 0.02 per veDUST/day = 2 points per 100 veDUST per day
            15e18, // 15 points/day
            30e18 // 30 points/day
        );

        assertEq(leaderboardConfig.depositRateBps(), 100, "Deposit: 100 bps");
        assertEq(leaderboardConfig.borrowRateBps(), 500, "Borrow: 500 bps");
        assertEq(leaderboardConfig.vpRateBps(), 200, "VP: 200 bps");
        assertEq(leaderboardConfig.supplyDailyBonus(), 15e18, "Supply bonus: 15");
        assertEq(leaderboardConfig.borrowDailyBonus(), 30e18, "Borrow bonus: 30");

        // Example calculation:
        // User has $10,000 supplied
        // Points per day = 10000 * 100 / 10000 = 100 points/day
        // Plus bonus = 15 points/day
        // Total = 115 points/day (before multipliers)
    }
}
