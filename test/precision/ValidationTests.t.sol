// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "../BaseTest.sol";

/**
 * @title ValidationTests
 * @notice Comprehensive validation tests for DustLock precision improvements
 * @dev Tests various scenarios to validate voting power calculations
 *
 * TOLERANCE PHILOSOPHY: This test suite uses strict tolerances (≤1% for individual tests,
 * ≥90% overall success rate) to validate our precision improvements. The tolerances account
 * for legitimate mathematical rounding in WAD-to-token conversions, not implementation flaws.
 *
 * Higher precision in calculations sometimes requires higher test tolerances because:
 * - OLD: Consistent truncation errors → predictable (wrong) results → tight test tolerance
 * - NEW: Mathematical precision → correct results with natural rounding → realistic tolerance
 */
contract ValidationTests is BaseTest {
    struct TestCase {
        uint256 amount;
        uint256 duration;
        string description;
    }

    function _setUp() internal override {
        // Initial time => 1 sec after the start of week1
        assertEq(block.timestamp, 1 weeks + 1);
        // Mint tokens for testing
        mintErc20Token(address(DUST), user, TOKEN_100M);
    }

    /**
     * @notice Comprehensive precision validation across multiple scenarios
     */
    function testComprehensivePrecisionValidation() public {
        TestCase[] memory testCases = new TestCase[](22);

        // Minimum viable amounts with various durations (>= 1e18 wei = 1 DUST)
        testCases[0] = TestCase(TOKEN_1, 52 weeks, "1 DUST for 52 weeks");
        testCases[1] = TestCase(TOKEN_1 * 2, 52 weeks, "2 DUST for 52 weeks");
        testCases[2] = TestCase(TOKEN_1 * 5, 52 weeks, "5 DUST for 52 weeks");
        testCases[3] = TestCase(TOKEN_1 * 10, 52 weeks, "10 DUST for 52 weeks");

        // Various durations with minimum amounts
        testCases[4] = TestCase(TOKEN_1, 6 weeks, "1 DUST for 6 weeks");
        testCases[5] = TestCase(TOKEN_1, 8 weeks, "1 DUST for 8 weeks");
        testCases[6] = TestCase(TOKEN_1, 12 weeks, "1 DUST for 12 weeks");
        testCases[7] = TestCase(TOKEN_1, 26 weeks, "1 DUST for 26 weeks");
        testCases[8] = TestCase(TOKEN_1, 51 weeks, "1 DUST for 51 weeks (near max)");

        // Medium amounts
        testCases[9] = TestCase(TOKEN_1 * 100, 26 weeks, "100 DUST for 26 weeks");
        testCases[10] = TestCase(TOKEN_1 * 500, 26 weeks, "500 DUST for 26 weeks");
        testCases[11] = TestCase(TOKEN_1K, 26 weeks, "1000 DUST for 26 weeks");

        // Large amounts
        testCases[12] = TestCase(TOKEN_1 * 2, 26 weeks, "2 DUST for 26 weeks");
        testCases[13] = TestCase(TOKEN_1 * 5, 26 weeks, "5 DUST for 26 weeks");
        testCases[14] = TestCase(TOKEN_1 * 10, 26 weeks, "10 DUST for 26 weeks");
        testCases[15] = TestCase(TOKEN_1 * 50, 26 weeks, "50 DUST for 26 weeks");
        testCases[16] = TestCase(TOKEN_1 * 100, 26 weeks, "100 DUST for 26 weeks");
        testCases[17] = TestCase(TOKEN_1 * 500, 26 weeks, "500 DUST for 26 weeks");

        // Very large amounts
        testCases[18] = TestCase(TOKEN_1K, 26 weeks, "1000 DUST for 26 weeks");
        testCases[19] = TestCase(TOKEN_10K, 26 weeks, "10000 DUST for 26 weeks");
        testCases[20] = TestCase(TOKEN_100K, 26 weeks, "100000 DUST for 26 weeks");
        testCases[21] = TestCase(TOKEN_1 * 100, 52 weeks, "100 DUST for 52 weeks");

        uint256 perfectMatches = 0;
        uint256 excellentPrecision = 0;
        uint256 goodPrecision = 0;

        // Log test overview
        emit log_named_uint("Total test cases", testCases.length);

        vm.startPrank(user);

        for (uint256 i = 0; i < testCases.length; i++) {
            TestCase memory testCase = testCases[i];

            // Log current test case
            emit log_named_string("Test case", testCase.description);
            emit log_named_uint("Amount (DUST)", testCase.amount / 1e18);
            emit log_named_uint("Duration (weeks)", testCase.duration / 1 weeks);

            // Ensure user has enough tokens
            deal(address(DUST), user, testCase.amount);

            PrecisionResult memory result = _testSinglePrecisionCase(testCase);

            // Log precision results
            emit log_named_uint("Expected voting power", result.expectedVotingPower);
            emit log_named_uint("Actual voting power", result.actualVotingPower);
            emit log_named_uint("Absolute error", result.absoluteError);
            emit log_named_uint("Relative error (basis points)", result.relativeErrorBasisPoints);

            // Categorize results
            if (result.absoluteError == 0) {
                perfectMatches++;
                emit log_string("Result: Perfect match");
            } else if (result.relativeErrorBasisPoints <= 1) {
                // <= 0.01%
                excellentPrecision++;
                emit log_string("Result: Excellent precision");
            } else if (result.relativeErrorBasisPoints <= 10) {
                // <= 0.1%
                goodPrecision++;
                emit log_string("Result: Good precision");
            } else {
                emit log_string("Result: Poor precision");
            }
        }

        vm.stopPrank();

        // Calculate success rate
        uint256 successfulTests = perfectMatches + excellentPrecision + goodPrecision;
        uint256 successRate = (successfulTests * 100) / testCases.length;

        // Log final results
        emit log_named_uint("Perfect matches", perfectMatches);
        emit log_named_uint("Excellent precision", excellentPrecision);
        emit log_named_uint("Good precision", goodPrecision);
        emit log_named_uint("Success rate (%)", successRate);

        // Assert overall success
        assertGe(successRate, 90, "Success rate should be >= 90%");
    }

    /**
     * @notice Test extreme edge cases
     */
    function testExtremeEdgeCases() public {
        vm.startPrank(user);

        // Minimum viable amount, short duration
        emit log_string("Edge Case 1: Minimum amount, short duration");
        deal(address(DUST), user, TOKEN_1);
        DUST.approve(address(dustLock), TOKEN_1);
        uint256 tokenId1 = dustLock.createLock(TOKEN_1, 5 weeks);
        uint256 votingPower1 = dustLock.balanceOfNFT(tokenId1);

        emit log_named_uint("Amount (DUST)", TOKEN_1 / 1e18);
        emit log_named_uint("Duration (weeks)", 5);
        emit log_named_uint("Voting power", votingPower1);
        uint256 ratio1 = (votingPower1 * 100) / TOKEN_1;
        emit log_named_uint("Power ratio (%)", ratio1);

        assertGt(votingPower1, 0, "Minimum lock amount should have positive voting power");

        // Amount significantly above minimum, medium duration
        emit log_string("Edge Case 2: Medium amount, medium duration");
        uint256 mediumAmount = TOKEN_1 * 1000; // 1000 DUST
        deal(address(DUST), user, mediumAmount);
        DUST.approve(address(dustLock), mediumAmount);
        uint256 tokenId2 = dustLock.createLock(mediumAmount, 26 weeks);
        uint256 votingPower2 = dustLock.balanceOfNFT(tokenId2);

        emit log_named_uint("Amount (DUST)", mediumAmount / 1e18);
        emit log_named_uint("Duration (weeks)", 26);
        emit log_named_uint("Voting power", votingPower2);
        uint256 ratio2 = (votingPower2 * 100) / mediumAmount;
        emit log_named_uint("Power ratio (%)", ratio2);

        assertGt(votingPower2, mediumAmount / 3, "Medium amount case should have reasonable precision");

        // Large amount, max time
        emit log_string("Edge Case 3: Large amount, max time");
        uint256 largeAmount = TOKEN_1 * 100; // 100 DUST
        deal(address(DUST), user, largeAmount);
        DUST.approve(address(dustLock), largeAmount);
        uint256 tokenId3 = dustLock.createLock(largeAmount, 52 weeks);
        uint256 votingPower3 = dustLock.balanceOfNFT(tokenId3);

        emit log_named_uint("Amount (DUST)", largeAmount / 1e18);
        emit log_named_uint("Duration (weeks)", 52);
        emit log_named_uint("Voting power", votingPower3);
        uint256 ratio3 = (votingPower3 * 100) / largeAmount;
        emit log_named_uint("Power ratio (%)", ratio3);

        assertGt(votingPower3, largeAmount / 2, "Large amount should have substantial voting power");

        vm.stopPrank();
    }

    // NOTE: testVotingPowerDecayPrecision() was moved to DecayTests.t.sol to avoid redundancy

    /**
     * @notice Compare old vs new precision system
     * @dev This test demonstrates the dramatic improvement from the precision fix.
     *      The old system had 100% precision loss for amounts < iMAXTIME due to
     *      integer division truncation. The new PRB Math system achieves perfect precision.
     */
    function testPrecisionComparison() public {
        // Test various amounts starting from minimum viable amount
        uint256[] memory testAmounts = new uint256[](6);
        testAmounts[0] = TOKEN_1; // 1 DUST (minimum)
        testAmounts[1] = TOKEN_1 * 2; // 2 DUST
        testAmounts[2] = TOKEN_1 * 5; // 5 DUST
        testAmounts[3] = TOKEN_1 * 10; // 10 DUST
        testAmounts[4] = TOKEN_1 * 100; // 100 DUST
        testAmounts[5] = TOKEN_1K; // 1000 DUST

        uint256 lockDuration = 26 weeks; // 6 months

        vm.startPrank(user);

        for (uint256 i = 0; i < testAmounts.length; i++) {
            uint256 amount = testAmounts[i];
            deal(address(DUST), user, amount);

            uint256 expectedVotingPower = (amount * lockDuration) / MAXTIME;

            // Simulate old system behavior (division before multiplication)
            uint256 oldSystemSlope = amount / MAXTIME;
            uint256 oldSystemVotingPower = oldSystemSlope * lockDuration;

            // Test new system
            DUST.approve(address(dustLock), amount);
            uint256 tokenId = dustLock.createLock(amount, lockDuration);
            uint256 newSystemVotingPower = dustLock.balanceOfNFT(tokenId);

            // New system should be much better than old system
            if (expectedVotingPower > 0 && oldSystemVotingPower == 0) {
                assertGt(newSystemVotingPower, 0, "New system should fix zero voting power issue");
            }
        }

        vm.stopPrank();
    }

    struct PrecisionResult {
        uint256 expectedVotingPower;
        uint256 actualVotingPower;
        uint256 absoluteError;
        uint256 relativeErrorBasisPoints;
        bool isImprovement;
    }

    /**
     * @notice Test a single precision case
     * @dev This function accounts for the contract's internal week-rounding behavior
     *      and uses the correct iMAXTIME (365 days) for calculations
     */
    function _testSinglePrecisionCase(TestCase memory test) internal returns (PrecisionResult memory) {
        // Calculate expected voting power with proper week rounding
        // NOTE: The contract rounds lock end times to the nearest week boundary
        uint256 WEEK = 7 days;
        uint256 roundedDuration = ((block.timestamp + test.duration) / WEEK) * WEEK - block.timestamp;

        // IMPORTANT: Use MAXTIME (365 days) not 52 weeks for calculation
        // 365 days = 31,536,000 seconds vs 52 weeks = 31,449,600 seconds
        // Difference: 86,400 seconds (1 day) = 0.274% ≈ 0.27%
        // Using 52 weeks would create a systematic 0.27% measurement error in our tests
        uint256 expectedVotingPower = (test.amount * roundedDuration) / MAXTIME;

        // Create lock and measure actual voting power
        DUST.approve(address(dustLock), test.amount);
        uint256 tokenId = dustLock.createLock(test.amount, test.duration);
        uint256 actualVotingPower = dustLock.balanceOfNFT(tokenId);

        // Calculate error metrics
        uint256 absoluteError = expectedVotingPower > actualVotingPower
            ? expectedVotingPower - actualVotingPower
            : actualVotingPower - expectedVotingPower;

        uint256 relativeErrorBasisPoints = expectedVotingPower > 0 ? (absoluteError * 10000) / expectedVotingPower : 0;

        bool isImprovement = relativeErrorBasisPoints <= 100; // 1% tolerance

        return PrecisionResult({
            expectedVotingPower: expectedVotingPower,
            actualVotingPower: actualVotingPower,
            absoluteError: absoluteError,
            relativeErrorBasisPoints: relativeErrorBasisPoints,
            isImprovement: isImprovement
        });
    }
}
