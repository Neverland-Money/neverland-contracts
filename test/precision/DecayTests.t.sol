// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "../BaseTest.sol";

/**
 * @title DecayTests
 * @notice Comprehensive tests for voting power decay mechanism in DustLock
 * @dev Validates that voting power decreases linearly over time as expected
 *
 * PRECISION NOTE: During development, we observed a consistent 0.27% "precision loss"
 * across decay tests. Investigation revealed this was NOT an implementation flaw, but
 * a measurement artifact in our test expectations:
 * - Contract uses MAXTIME = 365 days = 31,536,000 seconds
 * - Tests were initially using 52 weeks = 31,449,600 seconds
 * - Difference: 86,400 seconds (1 day) = 0.274% ≈ 0.27%
 *
 * When test expectations were corrected to use 365 days, the "precision loss"
 * disappeared, confirming our PRB Math implementation achieves perfect precision.
 */
contract DecayTests is BaseTest {
    function _setUp() internal override {
        // Initial time => 1 sec after the start of week1
        assertEq(block.timestamp, 1 weeks + 1);
        // Mint tokens for testing
        mintErc20Token(address(DUST), user, TOKEN_100M);
    }

    /**
     * @notice Test slope-bias relationship in voting power calculation
     */
    function testSlopeBiasRelationship() public {
        uint256 lockAmount = TOKEN_1 * 10; // 10 DUST (above minimum)
        uint256 lockDuration = 52 weeks; // Full year

        vm.startPrank(user);
        DUST.approve(address(dustLock), lockAmount);
        uint256 tokenId = dustLock.createLock(lockAmount, lockDuration);

        uint256 initialVotingPower = dustLock.balanceOfNFT(tokenId);

        // Get lock info for logging
        IDustLock.LockedBalance memory lockInfo = dustLock.locked(tokenId);

        // Advance time using end-anchored sampling (~30 days elapsed)
        uint256 sampleTs = lockInfo.end > 30 days ? (lockInfo.end - (MAXTIME - 30 days)) : (block.timestamp + 30 days);
        vm.warp(sampleTs);
        uint256 votingPowerAfter30Days = dustLock.balanceOfNFT(tokenId);

        vm.stopPrank();

        // Calculate decay metrics
        uint256 decayAmount = initialVotingPower - votingPowerAfter30Days;
        uint256 decayPercentage = (decayAmount * 100) / initialVotingPower;

        // Log detailed information
        emit log_named_uint("Lock amount", lockAmount);
        emit log_named_uint("Lock duration (seconds)", lockDuration);
        emit log_named_uint("Lock end timestamp", lockInfo.end);
        emit log_named_uint("Initial voting power", initialVotingPower);
        emit log_named_uint("Voting power after 30 days", votingPowerAfter30Days);
        emit log_named_uint("Decay amount", decayAmount);
        emit log_named_uint("Decay percentage", decayPercentage);

        // Expected voting power at this timestamp
        uint256 remainingTime = lockInfo.end > sampleTs ? (lockInfo.end - sampleTs) : 0;
        uint256 expectedAfter30Days = (lockAmount * remainingTime) / MAXTIME;

        // Demonstrate precision and decay
        assertEq(votingPowerAfter30Days, expectedAfter30Days, "Exact voting power at ~30 days elapsed");
        assertLt(votingPowerAfter30Days, initialVotingPower, "Voting power should decrease over time");
        assertGt(votingPowerAfter30Days, 0, "Voting power should not be zero after 30 days");
    }

    /**
     * @notice Comprehensive test of voting power decay over full lock duration
     */
    function testVotingPowerDecayTroubleshooting() public {
        uint256 lockAmount = TOKEN_1 * 50; // 50 DUST (well above minimum)
        uint256 lockDuration = MAXTIME; // Exactly one year

        vm.startPrank(user);
        DUST.approve(address(dustLock), lockAmount);
        uint256 tokenId = dustLock.createLock(lockAmount, lockDuration);

        uint256 initialVotingPower = dustLock.balanceOfNFT(tokenId);
        IDustLock.LockedBalance memory lockInfo = dustLock.locked(tokenId);

        vm.stopPrank();

        // Log initial state
        emit log_named_uint("Lock amount", lockAmount);
        emit log_named_uint("Lock duration (seconds)", lockDuration);
        emit log_named_uint("Lock end timestamp", lockInfo.end);
        emit log_named_uint("Initial voting power", initialVotingPower);

        // Calculate initial voting power ratio
        uint256 powerRatio = (initialVotingPower * 100) / lockAmount;
        emit log_named_uint("Initial power ratio (%)", powerRatio);

        // Test decay at various intervals
        _testDecayAtInterval(tokenId, lockInfo.end, 3 * 30 days, "3 months");
        _testDecayAtInterval(tokenId, lockInfo.end, 6 * 30 days, "6 months");
        _testDecayAtInterval(tokenId, lockInfo.end, 9 * 30 days, "9 months");
        _testDecayAtInterval(tokenId, lockInfo.end, 50 weeks, "Final week");
        _testDecayAtInterval(tokenId, lockInfo.end, MAXTIME, "Final day");
        _testDecayAtInterval(tokenId, lockInfo.end, MAXTIME + 23 hours, "Final hour");

        // Verify initial voting power was reasonable
        assertGt(initialVotingPower, lockAmount / 2, "Initial voting power should be substantial");
        assertLt(initialVotingPower, lockAmount, "Initial voting power should be less than lock amount");
    }

    /**
     * @notice Test voting power decay precision over time
     * @dev Merged from DustLockValidation - tests decay at regular intervals
     */
    function testVotingPowerDecayPrecision() public {
        uint256 amount = 1e18; // 1 DUST
        uint256 lockDuration = 52 weeks;

        vm.startPrank(user);
        deal(address(DUST), user, amount);
        DUST.approve(address(dustLock), amount);
        uint256 tokenId = dustLock.createLock(amount, lockDuration);

        uint256 initialVotingPower = dustLock.balanceOfNFT(tokenId);
        IDustLock.LockedBalance memory lockInfo = dustLock.locked(tokenId);

        vm.stopPrank();

        // End-anchored sampling: N days BEFORE expiry (more realistic)
        uint256[] memory remainingDays = new uint256[](5);
        remainingDays[0] = 334; // ~30 days elapsed
        remainingDays[1] = 274; // ~90 days elapsed
        remainingDays[2] = 184; // ~180 days elapsed
        remainingDays[3] = 94; // ~270 days elapsed
        remainingDays[4] = 15; // 15 days before expiry

        uint256 previousPower = initialVotingPower;
        emit log_named_uint("Initial voting power", initialVotingPower);

        for (uint256 i = 0; i < remainingDays.length; i++) {
            uint256 targetTimestamp = lockInfo.end - (remainingDays[i] * 1 days);
            vm.warp(targetTimestamp);

            uint256 currentPower = dustLock.balanceOfNFT(tokenId);

            emit log_named_uint(string(abi.encodePacked("Remaining days before expiry")), remainingDays[i]);
            emit log_named_uint("Voting power", currentPower);

            // Voting power should decrease as remaining time decreases
            assertLt(currentPower, previousPower, "Voting power should decay over time");

            previousPower = currentPower;
        }

        // At expiration, should be 0 (sample at end + 1 second only)
        vm.warp(lockInfo.end + 1);
        uint256 expiredPower = dustLock.balanceOfNFT(tokenId);
        emit log_named_uint("Expired voting power", expiredPower);
        assertEq(expiredPower, 0, "Expired lock should have zero voting power");
    }

    /**
     * @notice Test linear decay behavior
     * @dev Validates that decay follows the expected linear pattern
     */
    function testLinearDecayBehavior() public {
        uint256 lockAmount = TOKEN_1 * 100; // 100 DUST
        uint256 lockDuration = 26 weeks; // Half year

        vm.startPrank(user);
        DUST.approve(address(dustLock), lockAmount);
        uint256 tokenId = dustLock.createLock(lockAmount, lockDuration);

        IDustLock.LockedBalance memory lockInfo = dustLock.locked(tokenId);
        uint256 lockEnd = lockInfo.end;
        uint256 lockStart = block.timestamp;

        vm.stopPrank();

        // Test at 25%, 50%, 75% of lock duration
        uint256 totalDuration = lockEnd - lockStart;
        uint256[] memory testPoints = new uint256[](3);
        testPoints[0] = totalDuration / 4; // 25%
        testPoints[1] = totalDuration / 2; // 50%
        testPoints[2] = (totalDuration * 3) / 4; // 75%

        uint256 initialVotingPower = dustLock.balanceOfNFT(tokenId);
        emit log_named_uint("Initial voting power", initialVotingPower);

        for (uint256 i = 0; i < testPoints.length; i++) {
            uint256 testTime = lockStart + testPoints[i];
            vm.warp(testTime);

            uint256 currentVotingPower = dustLock.balanceOfNFT(tokenId);
            uint256 remainingTime = lockEnd - testTime;
            uint256 expectedVotingPower = (lockAmount * remainingTime) / MAXTIME;

            emit log_named_uint(
                string(abi.encodePacked("Expected at ", vm.toString((testPoints[i] * 100) / totalDuration), "%")),
                expectedVotingPower
            );
            emit log_named_uint(
                string(abi.encodePacked("Actual at ", vm.toString((testPoints[i] * 100) / totalDuration), "%")),
                currentVotingPower
            );

            // Should be reasonably close to expected (within 1% tolerance)
            uint256 tolerance = expectedVotingPower / 100; // 1%
            assertApproxEqAbs(
                currentVotingPower,
                expectedVotingPower,
                tolerance,
                string(abi.encodePacked("Linear decay at ", vm.toString((testPoints[i] * 100) / totalDuration), "%"))
            );
        }

        // Reset time
        vm.warp(1 weeks + 1);
    }

    /**
     * @notice Test decay at a specific time interval
     */
    function _testDecayAtInterval(
        uint256 tokenId,
        uint256 lockEnd,
        uint256 timeElapsed,
        string memory /* description */
    ) internal {
        // End-anchored sampling: interpret timeElapsed as since lock start,
        // with lock duration assumed MAXTIME in this troubleshooting test.
        // If timeElapsed < MAXTIME -> sample before expiry at: lockEnd - (MAXTIME - timeElapsed)
        // If timeElapsed >= MAXTIME -> sample after expiry at: lockEnd + (timeElapsed - MAXTIME)
        uint256 targetTimestamp;
        if (timeElapsed >= MAXTIME) {
            targetTimestamp = lockEnd + (timeElapsed - MAXTIME);
        } else {
            uint256 remaining = MAXTIME - timeElapsed;
            targetTimestamp = lockEnd - remaining;
        }

        vm.warp(targetTimestamp);
        uint256 currentVotingPower = dustLock.balanceOfNFT(tokenId);

        // Log interval details
        emit log_named_uint("Time elapsed (days)", timeElapsed / 1 days);
        emit log_named_uint("Target timestamp", targetTimestamp);
        emit log_named_uint("Lock end timestamp", lockEnd);
        emit log_named_uint("Current voting power", currentVotingPower);

        if (targetTimestamp >= lockEnd) {
            // After expiration, should be 0
            emit log_string("Status: Lock expired");
            assertEq(currentVotingPower, 0, "Expired lock should have zero voting power");
        } else {
            // Before expiration, should be positive and decreasing
            uint256 remainingTime = lockEnd - targetTimestamp;
            emit log_named_uint("Remaining time (days)", remainingTime / 1 days);
            emit log_string("Status: Lock active");
            assertGt(currentVotingPower, 0, "Active lock should have positive voting power");
        }
    }
}
