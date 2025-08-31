// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "../BaseTest.sol";
import "forge-std/console2.sol";

import {DustRewardsController} from "../../src/emissions/DustRewardsController.sol";
import {DustLockTransferStrategy} from "../../src/emissions/DustLockTransferStrategy.sol";
import {IDustRewardsController} from "../../src/interfaces/IDustRewardsController.sol";

/**
 * @title DustEmissionsFlow
 * @notice End-to-end tests for emissions-based lock creation and modifications
 * @dev Tests the full integration between DustRewardsController, DustLockTransferStrategy,
 *      and DustLock contracts, including gaming prevention mechanisms and penalty calculations
 */
contract DustEmissionsFlow is BaseTest {
    DustRewardsController public rewardsController;
    DustLockTransferStrategy public transferStrategy;
    address public emissionsManager;
    address public dustVault;
    address public rewardsAdmin;

    function _setUp() internal override {
        // Initial time => 1 sec after the start of week1
        assertEq(block.timestamp, 1 weeks + 1);

        // Set up emissions infrastructure
        emissionsManager = address(0xE111);
        rewardsAdmin = address(0xA111);
        dustVault = address(0x1111);

        vm.label(emissionsManager, "emissionsManager");
        vm.label(rewardsAdmin, "rewardsAdmin");
        vm.label(dustVault, "dustVault");

        // Deploy emissions contracts
        rewardsController = new DustRewardsController(emissionsManager);
        transferStrategy =
            new DustLockTransferStrategy(address(rewardsController), rewardsAdmin, dustVault, address(dustLock));

        // Set up transfer strategy in rewards controller
        vm.prank(emissionsManager);
        rewardsController.setTransferStrategy(address(DUST), transferStrategy);

        // Mint tokens for testing and fund vault
        mintErc20Token(address(DUST), user, TOKEN_100M);
        mintErc20Token(address(DUST), user1, TOKEN_100M);
        mintErc20Token(address(DUST), user2, TOKEN_100M);
        mintErc20Token(address(DUST), dustVault, TOKEN_100M);

        // Approve transfer strategy to spend vault tokens
        vm.prank(dustVault);
        DUST.approve(address(transferStrategy), TOKEN_100M);
    }

    // ============================================
    // TEST 1: EMISSIONS LOCK WITH INSTANT EARLY WITHDRAW
    // ============================================

    function testEmissionsLockInstantEarlyWithdraw() public {
        // Set up early withdraw parameters
        dustLock.setEarlyWithdrawTreasury(user2);
        dustLock.setEarlyWithdrawPenalty(5000); // 50% max penalty

        uint256 lockAmount = TOKEN_1K;
        uint256 lockDuration = MINTIME + WEEK; // Minimum required duration

        // Simulate emissions reward claim that creates a lock
        // transferStrategy.performTransfer(to, reward, amount, lockTime, tokenId)
        // lockTime > 0 and tokenId = 0 means create new lock
        vm.prank(address(rewardsController));
        bool success = transferStrategy.performTransfer(user, address(DUST), lockAmount, lockDuration, 0);
        assertTrue(success, "Transfer strategy should succeed");

        // Find the created token ID (should be 1 since it's the first NFT)
        uint256 tokenId = 1;

        // Verify lock was created correctly
        IDustLock.LockedBalance memory lockDetails = dustLock.locked(tokenId);
        assertEq(dustLock.ownerOf(tokenId), user);
        assertEq(uint256(lockDetails.amount), lockAmount);
        assertTrue(lockDetails.end > block.timestamp);

        emit log_named_uint("[emissions] Created lock tokenId", tokenId);
        emit log_named_uint("[emissions] Lock amount", uint256(lockDetails.amount));
        emit log_named_uint("[emissions] Lock end time", lockDetails.end);

        // Record balances before early withdraw
        uint256 userBalanceBefore = DUST.balanceOf(user);
        uint256 treasuryBalanceBefore = DUST.balanceOf(user2);

        // Instant early withdraw (maximum penalty expected)
        vm.prank(user);
        dustLock.earlyWithdraw(tokenId);

        uint256 userBalanceAfter = DUST.balanceOf(user);
        uint256 treasuryBalanceAfter = DUST.balanceOf(user2);

        uint256 actualPenalty = treasuryBalanceAfter - treasuryBalanceBefore;
        uint256 actualUserReceived = userBalanceAfter - userBalanceBefore;

        // Manual calculation for instant early withdraw:
        // 30 days = 30 x 24 x 60 x 60 = 2,592,000 seconds
        // Contract rounds to weeks: 2,592,000/604,800 = 4.285... weeks
        // Rounded down: 4 weeks = 4 x 604,800 = 2,419,200 seconds
        // Duration = 2,419,199 seconds (timestamp offset)
        //
        // Instant withdraw means remainingTime ≈ totalLockTime
        // Time ratio ≈ 100%, so penalty = 50% of lock amount
        uint256 expectedPenalty = lockAmount / 2; // 500 tokens (50% max penalty)
        uint256 expectedUserReceived = lockAmount - expectedPenalty; // 500 tokens

        emit log_named_uint("[emissions] Actual penalty", actualPenalty);
        emit log_named_uint("[emissions] Expected penalty", expectedPenalty);
        emit log_named_uint("[emissions] User received", actualUserReceived);

        // Verify penalty calculation
        assertEq(actualPenalty, expectedPenalty);
        assertEq(actualUserReceived, expectedUserReceived);
        assertEq(actualPenalty + actualUserReceived, lockAmount);

        // Verify NFT was burned
        assertEq(dustLock.balanceOfNFT(tokenId), 0);

        emit log("[emissions] Emissions lock with instant early withdraw completed");
    }

    // ============================================
    // TEST 2: GAMING PREVENTION - INCREASE AMOUNT AFTER TIME ELAPSED AND LOCK EXPIRING SOON
    // ============================================

    function testEmissionsIncreaseAmountGamingPrevention() public {
        uint256 initialAmount = TOKEN_1K;
        uint256 additionalAmount = TOKEN_100K / 200; // 500 tokens
        uint256 lockDuration = MINTIME + WEEK; // MINTIME + WEEK = 35 days, after skipping 1 week = 28 days
        emit log_named_uint("[gaming] Lock duration", lockDuration);

        // Create initial lock via emissions
        vm.prank(address(rewardsController));
        bool success = transferStrategy.performTransfer(user, address(DUST), initialAmount, lockDuration, 0);
        assertTrue(success, "Initial transfer strategy should succeed");

        uint256 tokenId = 1; // First NFT created
        emit log_named_uint("[gaming] Created initial lock tokenId", tokenId);
        emit log_named_uint("[gaming] Initial amount", initialAmount);

        // Skip 2 weeks (significant time elapsed)
        skipAndRoll(2 weeks);

        emit log("[gaming] Skipped 2 weeks, attempting to increase amount from emissions");

        // Calculate remaining time to verify it's below MINTIME
        IDustLock.LockedBalance memory lockDetails = dustLock.locked(tokenId);
        uint256 remainingTime = lockDetails.end > block.timestamp ? lockDetails.end - block.timestamp : 0;

        emit log_named_uint("[gaming] Remaining time", remainingTime);
        emit log_named_uint("[gaming] MINTIME", MINTIME);

        // Verify remaining time is below MINTIME (should be ~21 days < 28 days)
        assertTrue(remainingTime < MINTIME, "Remaining time should be less than MINTIME");

        // Try to increase amount from emissions after significant time has elapsed
        // This should REVERT because remaining lock time < MINTIME
        vm.prank(address(rewardsController));
        vm.expectRevert(IDustLock.DepositForLockDurationTooShort.selector);
        transferStrategy.performTransfer(user, address(DUST), additionalAmount, 0, tokenId);

        emit log("[gaming] Emissions correctly rejected - lock expiring too soon");
    }

    // ============================================
    // TEST 3: EMISSIONS INCREASE THEN EARLY WITHDRAW WITH PENALTY
    // ============================================

    function testEmissionsIncreaseAmountThenEarlyWithdraw() public {
        // Set up early withdraw parameters
        dustLock.setEarlyWithdrawTreasury(user2);
        dustLock.setEarlyWithdrawPenalty(5000); // 50% max penalty

        uint256 initialAmount = TOKEN_1;
        uint256 additionalAmount = TOKEN_100K / 200; // 500 tokens
        uint256 totalAmount = initialAmount + additionalAmount;

        // Create initial lock for 6 months via emissions
        vm.prank(address(rewardsController));
        bool success = transferStrategy.performTransfer(user, address(DUST), initialAmount, 180 days, 0);
        assertTrue(success, "Initial transfer strategy should succeed");

        uint256 tokenId = 1; // First NFT created

        // Skip 3 months (90 days)
        skipAndRoll(90 days);

        // Increase amount via emissions
        vm.prank(address(rewardsController));
        bool increaseSuccess = transferStrategy.performTransfer(user, address(DUST), additionalAmount, 0, tokenId);
        assertTrue(increaseSuccess, "Increase transfer strategy should succeed");

        // Verify amount increase and get lock details for calculation
        {
            IDustLock.LockedBalance memory lockDetails = dustLock.locked(tokenId);
            assertEq(uint256(lockDetails.amount), totalAmount);

            uint256 remainingTime = lockDetails.end > block.timestamp ? lockDetails.end - block.timestamp : 0;
            uint256 totalLockTime = lockDetails.end - lockDetails.effectiveStart;

            // Manual calculation for early withdraw after amount increase with weighted average:

            // Original scenario:
            // - Initial: 1 token lock for 180 days (6 months)
            // - Skip 90 days (3 months), then increase amount by 500 tokens via emissions
            // - Early withdraw immediately after amount increase

            // Time calculations with weekly rounding:
            // 180 days = 180 x 24 x 60 x 60 = 15,552,000 seconds
            // Contract rounds to weeks: 15,552,000/604,800 = 25.714... weeks
            // Rounded down: 25 weeks = 25 x 604,800 = 15,120,000 seconds
            // Duration = 15,119,999 seconds (timestamp offset)
            //
            // After 90 days = 90 x 24 x 60 x 60 = 7,776,000 seconds:
            // Remaining time = 15,119,999 - 7,776,000 = 7,343,999 seconds
            //
            // Weighted average start time calculation:
            // Original amount: 1 token, start time: 604801
            // Deposit amount: 500 tokens, deposit time: 604801 + 7,776,000 = 8,380,801
            // Weighted start = (1 * 604801 + 500 * 8,380,801) / (1 + 500)
            // Weighted start = (604801 + 4,190,400,500) / 501 ≈ 8,365,280 (actual)
            //
            // New total lock time = lock_end - weighted_start
            // New total lock time = (604801 + 15,119,999) - 8,365,280 = 7,359,520
            // Time ratio = 7,343,999 / 7,359,520 ≈ 0.9978 = 99.78%
            //
            // Since deposit is 500x larger, weighted average heavily favors deposit time
            // Result: near-maximum penalty (~50%) due to proportional gaming prevention

            uint256 expectedRemainingTime = 7343999; // Remaining at deposit point
            uint256 expectedWeightedStart = 8365280; // Actual weighted average from implementation
            uint256 expectedTotalLockTime = 7359520; // From weighted start to end
            uint256 expectedTimeRatio = 9978; // 99.78% in basis points

            emit log_named_uint("[weighted] Expected weighted start", expectedWeightedStart);
            emit log_named_uint("[weighted] Actual start", lockDetails.effectiveStart);
            emit log_named_uint("[weighted] Remaining time", remainingTime);
            emit log_named_uint("[weighted] Total lock time", totalLockTime);
            emit log_named_uint("[weighted] Time ratio (BP)", (remainingTime * 10000) / totalLockTime);

            assertEq(remainingTime, expectedRemainingTime);
            assertEq(totalLockTime, expectedTotalLockTime);
            assertEq((remainingTime * 10000) / totalLockTime, expectedTimeRatio);
        }

        // Record balances and early withdraw
        {
            uint256 userBefore = DUST.balanceOf(user);
            uint256 treasuryBefore = DUST.balanceOf(user2);

            vm.prank(user);
            dustLock.earlyWithdraw(tokenId);

            uint256 penalty = DUST.balanceOf(user2) - treasuryBefore;
            uint256 userReceived = DUST.balanceOf(user) - userBefore;

            // Calculate expected penalty using weighted average formula:
            // penalty = (totalAmount x 5000 x remainingTime) / (10000 x totalLockTime)
            // penalty = (501 x 10^18 x 5000 x 7,343,999) / (10000 x 7,359,520)
            // penalty = (501 x 10^18 x 5000 x 0.9978) ≈ 249,971,703,249,668,456,638
            uint256 expectedPenalty = 249971703249668456638; // Calculated with weighted average

            emit log_named_uint("[increase] Total amount", totalAmount);
            emit log_named_uint("[increase] Actual penalty", penalty);
            emit log_named_uint("[increase] Expected penalty", expectedPenalty);

            // Verify penalty calculation (weighted gaming prevention applied)
            assertEq(penalty, expectedPenalty);
            assertEq(userReceived, totalAmount - expectedPenalty);
        }

        emit log("[increase] Weighted average gaming prevention applied proportional penalty");
    }
}
