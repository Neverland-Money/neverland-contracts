// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "../BaseTest.sol";

/**
 * @title PrecisionTests
 * @notice Comprehensive tests for voting power calculation precision in DustLock
 * @dev Tests precision across different amounts, durations, and scenarios
 *
 * HISTORICAL CONTEXT: This test suite was created to prove and fix a critical precision
 * loss vulnerability where small amounts (< 31.5M wei) resulted in 100% voting power loss
 * due to integer division truncation in the original implementation.
 *
 * The fix involved implementing PRB Math UD60x18 for 18-decimal precision calculations.
 * During validation, we initially observed a 0.27% systematic "error" which was later
 * identified as a test measurement artifact (using 52 weeks vs 365 days), not an
 * implementation flaw. The corrected tests show perfect mathematical precision.
 *
 * PRECISION VALIDATION APPROACH:
 * - Uses exact mathematical calculations with known inputs
 * - Validates both initial voting power and decay over time
 * - Tests edge cases and boundary conditions with precise expectations
 * - Ensures our PRB Math implementation matches theoretical calculations
 */
contract PrecisionTests is BaseTest {
    // Test constants for precise calculations
    uint256 constant PRECISION_TOLERANCE = 1; // 1 wei tolerance for rounding

    function _setUp() internal override {
        // Initial time => 1 sec after the start of week1
        assertEq(block.timestamp, 1 weeks + 1);
        // Mint tokens for testing
        mintErc20Token(address(DUST), user, TOKEN_100M);
        mintErc20Token(address(DUST), user1, TOKEN_100M);
        mintErc20Token(address(DUST), user2, TOKEN_100M);
    }

    // ============================================
    // GENERAL PRECISION TESTS
    // ============================================

    /**
     * @notice Test precision in voting power calculations across different amounts
     */
    function testActualContractPrecisionLoss() public {
        uint256 lockDuration = 26 weeks; // Half year lock

        // Test amounts across different ranges (all >= minimum lock amount)
        uint256[] memory testAmounts = new uint256[](8);
        testAmounts[0] = TOKEN_1; // 1 DUST (minimum)
        testAmounts[1] = TOKEN_1 * 2; // 2 DUST
        testAmounts[2] = TOKEN_1 * 5; // 5 DUST
        testAmounts[3] = TOKEN_1 * 10; // 10 DUST
        testAmounts[4] = TOKEN_1 * 50; // 50 DUST
        testAmounts[5] = TOKEN_1 * 100; // 100 DUST
        testAmounts[6] = TOKEN_1 * 500; // 500 DUST
        testAmounts[7] = TOKEN_1K; // 1000 DUST

        emit log_named_uint("Lock duration (weeks)", lockDuration / 1 weeks);
        emit log_named_uint("Total test amounts", testAmounts.length);

        for (uint256 i = 0; i < testAmounts.length; i++) {
            uint256 amount = testAmounts[i];
            emit log_named_uint("Testing amount (DUST)", amount / 1e18);
            _testSingleAmount(amount, lockDuration);
        }
    }

    /**
     * @notice Test checkpoint behavior with precision calculations
     */
    function testCheckpointBehavior() public {
        uint256 amount = TOKEN_1 * 10; // 10 DUST (above minimum)
        uint256 lockDuration = 26 weeks;

        vm.startPrank(user);
        DUST.approve(address(dustLock), amount);
        uint256 tokenId = dustLock.createLock(amount, lockDuration);

        uint256 initialVotingPower = dustLock.balanceOfNFT(tokenId);

        // Log initial state
        emit log_named_uint("Lock amount (DUST)", amount / 1e18);
        emit log_named_uint("Lock duration (weeks)", lockDuration / 1 weeks);
        emit log_named_uint("Initial voting power", initialVotingPower);

        // Force checkpoint
        dustLock.checkpoint();
        uint256 votingPowerAfterCheckpoint = dustLock.balanceOfNFT(tokenId);

        // Should be the same immediately after checkpoint
        emit log_named_uint("Voting power after checkpoint", votingPowerAfterCheckpoint);
        assertEq(initialVotingPower, votingPowerAfterCheckpoint);

        // Advance time and checkpoint again
        vm.warp(block.timestamp + 1 weeks);
        dustLock.checkpoint();
        uint256 votingPowerAfterWeek = dustLock.balanceOfNFT(tokenId);

        // Calculate decay metrics
        uint256 weeklyDecay = initialVotingPower - votingPowerAfterWeek;
        uint256 decayPercentage = (weeklyDecay * 100) / initialVotingPower;

        // Log decay information
        emit log_named_uint("Voting power after 1 week", votingPowerAfterWeek);
        emit log_named_uint("Weekly decay amount", weeklyDecay);
        emit log_named_uint("Weekly decay percentage", decayPercentage);

        // Should have decayed
        assertLt(votingPowerAfterWeek, initialVotingPower);

        vm.stopPrank();
    }

    /**
     * @notice Test edge cases around precision boundaries
     */
    function testEdgeCasePrecisionLoss() public {
        uint256 lockDuration = 26 weeks;

        // Test amounts around various thresholds (all >= minimum lock amount)
        uint256[] memory edgeAmounts = new uint256[](3);
        edgeAmounts[0] = TOKEN_1; // Minimum lock amount
        edgeAmounts[1] = TOKEN_1 * 100; // Medium amount
        edgeAmounts[2] = TOKEN_1K; // Large amount

        vm.startPrank(user);

        for (uint256 i = 0; i < edgeAmounts.length; i++) {
            uint256 amount = edgeAmounts[i];
            DUST.approve(address(dustLock), amount);
            uint256 tokenId = dustLock.createLock(amount, lockDuration);
            uint256 votingPower = dustLock.balanceOfNFT(tokenId);

            // All amounts should produce non-zero voting power
            assertGt(votingPower, 0, "Edge case should not result in zero voting power");
        }

        vm.stopPrank();
    }

    /**
     * @notice Test multiple small locks to verify consistent precision
     */
    function testMultipleSmallLocks() public {
        uint256 lockAmount = TOKEN_1 * 5; // 5 DUST (above minimum)
        uint256 lockDuration = 26 weeks;
        uint256 numLocks = 5;

        vm.startPrank(user);

        uint256 totalExpectedVotingPower = 0;
        uint256 totalActualVotingPower = 0;

        // Log test parameters
        emit log_named_uint("Lock amount per lock (DUST)", lockAmount / 1e18);
        emit log_named_uint("Lock duration (weeks)", lockDuration / 1 weeks);
        emit log_named_uint("Number of locks", numLocks);

        for (uint256 i = 0; i < numLocks; i++) {
            DUST.approve(address(dustLock), lockAmount);
            uint256 tokenId = dustLock.createLock(lockAmount, lockDuration);
            uint256 votingPower = dustLock.balanceOfNFT(tokenId);

            totalActualVotingPower += votingPower;
            totalExpectedVotingPower += (lockAmount * lockDuration) / MAXTIME;

            // Log individual lock details
            emit log_named_uint(string(abi.encodePacked("Lock ", vm.toString(i + 1), " voting power")), votingPower);

            // Each lock should have non-zero voting power
            assertGt(votingPower, 0, "Small lock should have non-zero voting power");
        }

        vm.stopPrank();

        // Log totals and precision
        emit log_named_uint("Total expected voting power", totalExpectedVotingPower);
        emit log_named_uint("Total actual voting power", totalActualVotingPower);

        uint256 precisionBasisPoints = (totalActualVotingPower * 10000) / totalExpectedVotingPower;
        emit log_named_uint("Precision (basis points)", precisionBasisPoints);

        // Total should be reasonable
        assertGt(totalActualVotingPower, 0, "Total voting power should be non-zero");
    }

    // ============================================
    // SPECIFIC PRECISION SCENARIOS
    // ============================================

    /**
     * @notice Test Scenario 1: Exact 1 DUST for exactly 26 weeks
     * @dev This scenario uses round numbers to validate precise calculations
     *
     * Expected calculation:
     * - Amount: 1e18 wei (1 DUST)
     * - Duration: 26 weeks = 15,724,800 seconds
     * - MAXTIME: 365 days = 31,536,000 seconds
     * - Expected voting power: (1e18 * 15,724,800) / 31,536,000 = 498,630,136,986,301,369 wei
     */
    function testScenario1_OneDustTwentySixWeeks() public {
        uint256 lockAmount = 1e18; // Exactly 1 DUST
        uint256 lockDuration = 26 weeks; // Exactly 26 weeks

        vm.startPrank(user);
        DUST.approve(address(dustLock), lockAmount);
        uint256 tokenId = dustLock.createLock(lockAmount, lockDuration);
        uint256 actualVotingPower = dustLock.balanceOfNFT(tokenId);

        // Get the actual lock duration after week rounding
        IDustLock.LockedBalance memory lockInfo = dustLock.locked(tokenId);
        uint256 actualDuration = lockInfo.end - block.timestamp;
        uint256 expectedVotingPower = (lockAmount * actualDuration) / MAXTIME;

        vm.stopPrank();

        // Demonstrate maximum precision: exact match
        assertEq(actualVotingPower, expectedVotingPower, "Scenario 1: Voting power must equal expected calculation");

        // Log values for verification
        emit log_named_uint("Requested duration", lockDuration);
        emit log_named_uint("Actual duration", actualDuration);
        emit log_named_uint("Expected voting power", expectedVotingPower);
        emit log_named_uint("Actual voting power", actualVotingPower);
        emit log_named_uint(
            "Absolute difference",
            actualVotingPower > expectedVotingPower
                ? actualVotingPower - expectedVotingPower
                : expectedVotingPower - actualVotingPower
        );
    }

    /**
     * @notice Test Scenario 2: Exact 10 DUST for exactly 52 weeks (max time)
     * @dev Tests maximum duration scenario
     *
     * Expected calculation:
     * - Amount: 10e18 wei (10 DUST)
     * - Duration: 52 weeks ≈ 365 days = 31,536,000 seconds (due to week rounding)
     * - Expected voting power: 10e18 wei (should be close to the lock amount)
     */
    function testScenario2_TenDustFiftyTwoWeeks() public {
        uint256 lockAmount = 10e18; // Exactly 10 DUST
        uint256 lockDuration = 52 weeks; // Maximum duration

        vm.startPrank(user);
        DUST.approve(address(dustLock), lockAmount);
        uint256 tokenId = dustLock.createLock(lockAmount, lockDuration);
        uint256 actualVotingPower = dustLock.balanceOfNFT(tokenId);

        // Get the actual lock end time to calculate precise expected value
        IDustLock.LockedBalance memory lockInfo = dustLock.locked(tokenId);
        uint256 actualDuration = lockInfo.end - block.timestamp;
        uint256 expectedVotingPower = (lockAmount * actualDuration) / MAXTIME;

        vm.stopPrank();

        // Demonstrate maximum precision: exact match
        assertEq(
            actualVotingPower,
            expectedVotingPower,
            "Scenario 2: Max duration voting power must equal expected calculation"
        );

        // Verify it's close to the lock amount (should be ~99.7% due to 365 days vs 52 weeks)
        assertGt(actualVotingPower, (lockAmount * 99) / 100, "Should be >99% of lock amount");

        emit log_named_uint("Lock amount", lockAmount);
        emit log_named_uint("Actual duration (seconds)", actualDuration);
        emit log_named_uint("Expected voting power", expectedVotingPower);
        emit log_named_uint("Actual voting power", actualVotingPower);
    }

    /**
     * @notice Test Scenario 3: Precise decay over time with exact calculations
     * @dev Tests voting power decay at specific time intervals
     *
     * Scenario: 5 DUST locked for 26 weeks, check decay at specific intervals
     */
    function testScenario3_PreciseDecayCalculation() public {
        uint256 lockAmount = 5e18; // 5 DUST
        uint256 lockDuration = 26 weeks;

        vm.startPrank(user);
        DUST.approve(address(dustLock), lockAmount);
        uint256 tokenId = dustLock.createLock(lockAmount, lockDuration);

        IDustLock.LockedBalance memory lockInfo = dustLock.locked(tokenId);
        uint256 lockEnd = lockInfo.end;

        vm.stopPrank();

        // Test decay at specific intervals using end-anchored sampling
        uint256[] memory remainingTimes = new uint256[](4);
        remainingTimes[0] = lockEnd - (block.timestamp + 1 weeks) > 0 ? 25 weeks : 0; // after 1 week elapsed
        remainingTimes[1] = lockEnd - (block.timestamp + 4 weeks) > 0 ? 22 weeks : 0; // after 4 weeks elapsed
        remainingTimes[2] = lockEnd - (block.timestamp + 13 weeks) > 0 ? 13 weeks : 0; // half time
        remainingTimes[3] = lockEnd - (block.timestamp + 25 weeks) > 0 ? 1 weeks : 0; // near end

        for (uint256 i = 0; i < remainingTimes.length; i++) {
            if (remainingTimes[i] == 0) continue;
            uint256 testTime = lockEnd - remainingTimes[i];
            vm.warp(testTime);
            uint256 actualVotingPower = dustLock.balanceOfNFT(tokenId);

            // Calculate expected voting power at this time
            uint256 remainingTime = lockEnd - testTime;
            uint256 expectedVotingPower = (lockAmount * remainingTime) / MAXTIME;

            // Demonstrate maximum precision at sampled points
            assertEq(
                actualVotingPower,
                expectedVotingPower,
                string(abi.encodePacked("Decay at remaining weeks ", vm.toString(remainingTimes[i] / 1 weeks)))
            );

            emit log_named_uint("Remaining weeks - Expected", remainingTimes[i] / 1 weeks);
            emit log_named_uint("Voting power - Expected", expectedVotingPower);
            emit log_named_uint("Voting power - Actual", actualVotingPower);
        }

        // Reset time for cleanup
        vm.warp(1 weeks + 1);
    }

    /**
     * @notice Test Scenario 4: Small amount precision (edge case)
     * @dev Tests precision with minimum viable amount
     *
     * Scenario: Exactly 1 DUST (minimum) for various durations
     */
    function testScenario4_MinimumAmountPrecision() public {
        uint256 lockAmount = 1e18; // Minimum lock amount

        // Test different durations
        uint256[] memory durations = new uint256[](3);
        durations[0] = 5 weeks; // Above minimum time (4 weeks + buffer)
        durations[1] = 26 weeks; // Half year
        durations[2] = 52 weeks; // Max time

        vm.startPrank(user);

        for (uint256 i = 0; i < durations.length; i++) {
            uint256 duration = durations[i];

            DUST.approve(address(dustLock), lockAmount);
            uint256 tokenId = dustLock.createLock(lockAmount, duration);

            IDustLock.LockedBalance memory lockInfo = dustLock.locked(tokenId);
            uint256 actualDuration = lockInfo.end - block.timestamp;
            uint256 expectedVotingPower = (lockAmount * actualDuration) / MAXTIME;
            uint256 actualVotingPower = dustLock.balanceOfNFT(tokenId);

            // Even minimum amounts should have precise calculations
            assertApproxEqAbs(
                actualVotingPower,
                expectedVotingPower,
                PRECISION_TOLERANCE,
                string(abi.encodePacked("Min amount precision - ", vm.toString(duration / 1 weeks), " weeks"))
            );

            // Ensure no precision loss to zero
            assertGt(actualVotingPower, 0, "Minimum amount should never result in zero voting power");

            emit log_named_uint(
                string(abi.encodePacked("Duration ", vm.toString(duration / 1 weeks), "w - Expected")),
                expectedVotingPower
            );
            emit log_named_uint(
                string(abi.encodePacked("Duration ", vm.toString(duration / 1 weeks), "w - Actual")), actualVotingPower
            );
        }

        vm.stopPrank();
    }

    /**
     * @notice Test Scenario 5: Large amount precision validation
     * @dev Tests precision with large token amounts
     *
     * Scenario: 100,000 DUST for 26 weeks
     */
    function testScenario5_LargeAmountPrecision() public {
        uint256 lockAmount = 100_000e18; // 100,000 DUST
        uint256 lockDuration = 26 weeks;

        vm.startPrank(user);
        DUST.approve(address(dustLock), lockAmount);
        uint256 tokenId = dustLock.createLock(lockAmount, lockDuration);

        IDustLock.LockedBalance memory lockInfo = dustLock.locked(tokenId);
        uint256 actualDuration = lockInfo.end - block.timestamp;
        uint256 expectedVotingPower = (lockAmount * actualDuration) / MAXTIME;
        uint256 actualVotingPower = dustLock.balanceOfNFT(tokenId);

        vm.stopPrank();

        // Large amounts should maintain precision
        assertApproxEqAbs(
            actualVotingPower, expectedVotingPower, PRECISION_TOLERANCE, "Large amount precision should be maintained"
        );

        // Calculate precision as percentage
        uint256 precisionBasisPoints = (actualVotingPower * 10000) / expectedVotingPower;

        // Should be very close to 100% (10000 basis points)
        assertGe(precisionBasisPoints, 9999, "Precision should be >= 99.99%");
        assertLe(precisionBasisPoints, 10001, "Precision should be <= 100.01%");

        emit log_named_uint("Expected voting power", expectedVotingPower);
        emit log_named_uint("Actual voting power", actualVotingPower);
        emit log_named_uint("Precision (basis points)", precisionBasisPoints);
    }

    /**
     * @notice Test Scenario 6: Week boundary rounding validation
     * @dev Tests that week rounding doesn't cause precision loss
     *
     * Scenario: Test lock durations that cross week boundaries
     */
    function testScenario6_WeekBoundaryRounding() public {
        uint256 lockAmount = 10e18; // 10 DUST

        // Test durations that will be rounded to week boundaries
        uint256[] memory rawDurations = new uint256[](3);
        rawDurations[0] = 26 weeks + 3 days; // Should round down to 26 weeks
        rawDurations[1] = 26 weeks + 4 days; // Should round up to 27 weeks
        rawDurations[2] = 52 weeks - 1 days; // Should round down to 51 weeks

        vm.startPrank(user);

        for (uint256 i = 0; i < rawDurations.length; i++) {
            uint256 rawDuration = rawDurations[i];

            DUST.approve(address(dustLock), lockAmount);
            uint256 tokenId = dustLock.createLock(lockAmount, rawDuration);

            IDustLock.LockedBalance memory lockInfo = dustLock.locked(tokenId);
            uint256 actualDuration = lockInfo.end - block.timestamp;
            uint256 expectedVotingPower = (lockAmount * actualDuration) / MAXTIME;
            uint256 actualVotingPower = dustLock.balanceOfNFT(tokenId);

            // Verify precision is maintained despite rounding
            assertApproxEqAbs(
                actualVotingPower,
                expectedVotingPower,
                PRECISION_TOLERANCE,
                string(abi.encodePacked("Week boundary rounding test ", vm.toString(i)))
            );

            emit log_named_uint(string(abi.encodePacked("Test ", vm.toString(i), " - Raw duration")), rawDuration);
            emit log_named_uint(string(abi.encodePacked("Test ", vm.toString(i), " - Actual duration")), actualDuration);
            emit log_named_uint(string(abi.encodePacked("Test ", vm.toString(i), " - Voting power")), actualVotingPower);
        }

        vm.stopPrank();
    }

    // ============================================
    // HELPER FUNCTIONS
    // ============================================

    /**
     * @notice Test a single amount by creating an actual lock
     */
    function _testSingleAmount(uint256 amount, uint256 duration) internal {
        vm.startPrank(user);
        DUST.approve(address(dustLock), amount);
        uint256 tokenId = dustLock.createLock(amount, duration);

        // Get the actual voting power from the contract
        uint256 actualVotingPower = dustLock.balanceOfNFT(tokenId);

        // Get lock details for verification
        IDustLock.LockedBalance memory lockInfo = dustLock.locked(tokenId);
        // Use actualDuration (post week-rounding) for exact expectation
        uint256 expectedVotingPower = (amount * (lockInfo.end - block.timestamp)) / MAXTIME;

        vm.stopPrank();

        // Log test details
        emit log_named_uint("Test amount (DUST)", amount / 1e18);
        emit log_named_uint("Expected voting power", expectedVotingPower);
        emit log_named_uint("Actual voting power", actualVotingPower);

        // Calculate precision metrics
        if (expectedVotingPower > 0) {
            uint256 precisionBasisPoints = (actualVotingPower * 10000) / expectedVotingPower;
            emit log_named_uint("Precision (basis points)", precisionBasisPoints);
        }

        // Verify precision - should be close to expected for non-zero amounts
        if (expectedVotingPower > 0) {
            assertGt(actualVotingPower, 0, "Should not have zero voting power for non-zero amounts");
        }

        // Test voting power decay over time
        vm.warp(lockInfo.end - 1 weeks);
        uint256 votingPowerNearEnd = dustLock.balanceOfNFT(tokenId);

        // Log decay information
        if (actualVotingPower > 0) {
            uint256 decayAmount = actualVotingPower - votingPowerNearEnd;
            uint256 decayPercentage = (decayAmount * 100) / actualVotingPower;
            emit log_named_uint("Voting power near end", votingPowerNearEnd);
            emit log_named_uint("Decay amount", decayAmount);
            emit log_named_uint("Decay percentage", decayPercentage);
        }

        // Verify decay occurred (unless it was already 0)
        if (actualVotingPower > 0) {
            assertLt(votingPowerNearEnd, actualVotingPower, "Voting power should decay over time");
        }

        // Reset time for next test
        vm.warp(1 weeks + 1);
    }

    // ============================================
    // FUZZ / PROPERTY TESTS
    // ============================================

    /**
     * @notice Fuzz: for a wide range of amounts/durations, initial voting power equals (amount * actualDuration) / MAXTIME
     */
    function testFuzzInitialVotingPower(uint96 wholeDust, uint8 weeksDuration) public {
        // Bound amount to [1, 10000] DUST to keep gas reasonable
        uint256 amount = (uint256(wholeDust) % 10000 + 1) * 1e18;
        // Bound duration to [5, 52] weeks (enforces min lock of 5 weeks and max 52 weeks)
        uint256 durationWeeks = (uint256(weeksDuration) % 48) + 5;
        uint256 duration = durationWeeks * 1 weeks;

        vm.startPrank(user);
        deal(address(DUST), user, amount);
        DUST.approve(address(dustLock), amount);
        uint256 tokenId = dustLock.createLock(amount, duration);

        IDustLock.LockedBalance memory lockInfo = dustLock.locked(tokenId);
        uint256 actualDuration = lockInfo.end - block.timestamp;
        uint256 expectedVotingPower = (amount * actualDuration) / MAXTIME;
        uint256 actualVotingPower = dustLock.balanceOfNFT(tokenId);

        vm.stopPrank();

        assertEq(actualVotingPower, expectedVotingPower, "Fuzz: initial voting power must equal expected");
    }

    /**
     * @notice Linearity: sum of voting power of two locks with same duration ≈ voting power of single lock with summed amount
     * @dev Integer division can introduce at most 1 wei discrepancy due to truncation aggregation; enforce <= 1 wei
     */
    function testLinearityWithinOneWei() public {
        uint256 duration = 26 weeks;
        uint256 amountA = 17e18;
        uint256 amountB = 29e18;

        vm.startPrank(user);
        // Fund enough for two separate locks and one aggregated lock
        deal(address(DUST), user, 2 * (amountA + amountB));

        // Two separate locks
        DUST.approve(address(dustLock), amountA);
        uint256 tokenA = dustLock.createLock(amountA, duration);
        DUST.approve(address(dustLock), amountB);
        uint256 tokenB = dustLock.createLock(amountB, duration);

        uint256 vpA = dustLock.balanceOfNFT(tokenA);
        uint256 vpB = dustLock.balanceOfNFT(tokenB);

        // Single aggregated lock
        DUST.approve(address(dustLock), amountA + amountB);
        uint256 tokenSum = dustLock.createLock(amountA + amountB, duration);
        uint256 vpSum = dustLock.balanceOfNFT(tokenSum);

        vm.stopPrank();

        uint256 vpTwo = vpA + vpB;
        if (vpTwo > vpSum) {
            assertLe(vpTwo - vpSum, 1, "Linearity: two locks vs single lock must be within 1 wei");
        } else {
            assertLe(vpSum - vpTwo, 1, "Linearity: single lock vs two locks must be within 1 wei");
        }
    }
}
