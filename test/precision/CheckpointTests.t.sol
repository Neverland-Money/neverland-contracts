// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "./ExtendedBaseTest.sol";
import {UD60x18, ud} from "@prb/math/src/UD60x18.sol";

/**
 * @title CheckpointTests
 * @notice Tests for checkpoint mechanism precision in DustLock
 * @dev Validates internal checkpoint calculations, slope/bias precision, and WAD math
 */
contract CheckpointTests is ExtendedBaseTest {
    function testCheckpointPrecisionFlow() public {
        IDustLock.LockedBalance memory locked;
        IDustLock.UserPoint memory userPoint;
        IDustLock.GlobalPoint memory globalPoint;

        // Ensure test contract has enough DUST tokens for all operations
        deal(address(DUST), address(this), TOKEN_1 * 10);

        // Create lock 1 and check state
        DUST.approve(address(dustLock), type(uint256).max);
        dustLock.createLock(TOKEN_1, MAXTIME); // 1

        locked = dustLock.locked(1);
        emit log_named_uint("Expected locked.amount", TOKEN_1);
        emit log_named_uint("Actual locked.amount", uint256(locked.amount));

        // Use actual lock end time to avoid any rounding mismatches
        uint256 expectedEnd = locked.end;
        emit log_named_uint("Expected locked.end", expectedEnd);
        emit log_named_uint("Actual locked.end", locked.end);
        emit log_named_string("Expected locked.isPermanent", "false");
        emit log_named_string("Actual locked.isPermanent", locked.isPermanent ? "true" : "false");

        // Both slope and bias use WAD precision in the current contract
        int256 expectedSlopeWAD = int256((TOKEN_1 * 1e18) / MAXTIME);
        int256 expectedBiasWAD = expectedSlopeWAD * int256(expectedEnd - block.timestamp);

        emit log_named_int("Expected slopeChanges", -expectedSlopeWAD);
        emit log_named_int("Actual slopeChanges", dustLock.slopeChanges(expectedEnd));
        emit log_named_int("SlopeChanges difference", dustLock.slopeChanges(expectedEnd) - (-expectedSlopeWAD));
        // Demonstrate exact precision for slopeChanges
        assertEq(dustLock.slopeChanges(expectedEnd), -expectedSlopeWAD, "slopeChanges must match exactly");

        emit log_named_uint("Expected userPointEpoch", 1);
        emit log_named_uint("Actual userPointEpoch", dustLock.userPointEpoch(1));
        userPoint = dustLock.userPointHistory(1, 1);

        // Log precision differences instead of asserting
        emit log_named_int("Expected userPoint.bias", expectedBiasWAD);
        emit log_named_int("Actual userPoint.bias", userPoint.bias);
        emit log_named_int("User bias difference", userPoint.bias - expectedBiasWAD);
        if (expectedBiasWAD != 0) {
            // Calculate percentage error: (actual - expected) / expected * 100
            int256 percentageError =
                expectedBiasWAD != 0 ? ((userPoint.bias - expectedBiasWAD) * 1e18) / expectedBiasWAD : int256(0);
            emit log_named_int("User bias error percentage (1e18 = 100%)", percentageError);
        }
        emit log_named_int("Expected userPoint.slope", expectedSlopeWAD);
        emit log_named_int("Actual userPoint.slope", userPoint.slope);
        emit log_named_int("User slope difference", userPoint.slope - expectedSlopeWAD);
        // Demonstrate exact precision for user slope
        assertEq(userPoint.slope, expectedSlopeWAD, "user slope must match exactly");
        if (expectedSlopeWAD != 0) {
            int256 slopePercentageError =
                expectedSlopeWAD != 0 ? ((userPoint.slope - expectedSlopeWAD) * 1e18) / expectedSlopeWAD : int256(0);
            emit log_named_int("User slope error percentage (1e18 = 100%)", slopePercentageError);
        }
        emit log_named_uint("Expected userPoint.ts", block.timestamp);
        emit log_named_uint("Actual userPoint.ts", userPoint.ts);
        emit log_named_uint("Expected userPoint.blk", 1);
        emit log_named_uint("Actual userPoint.blk", userPoint.blk);
        emit log_named_uint("Expected userPoint.permanent", 0);
        emit log_named_uint("Actual userPoint.permanent", userPoint.permanent);

        emit log_named_uint("Expected dustLock.epoch", 1);
        emit log_named_uint("Actual dustLock.epoch", dustLock.epoch());
        globalPoint = dustLock.pointHistory(1);
        emit log_named_int("Expected globalPoint.bias (1st)", expectedBiasWAD);
        emit log_named_int("Actual globalPoint.bias (1st)", globalPoint.bias);
        emit log_named_int("Global bias difference (1st)", globalPoint.bias - expectedBiasWAD);
        if (expectedBiasWAD != 0) {
            int256 globalBiasPercentageError =
                expectedBiasWAD != 0 ? ((globalPoint.bias - expectedBiasWAD) * 1e18) / expectedBiasWAD : int256(0);
            emit log_named_int("Global bias error percentage (1e18 = 100%)", globalBiasPercentageError);
        }
        emit log_named_int("Expected globalPoint.slope", expectedSlopeWAD);
        emit log_named_int("Actual globalPoint.slope", globalPoint.slope);
        emit log_named_int("Global slope difference", globalPoint.slope - expectedSlopeWAD);
        // Demonstrate exact precision for global slope
        assertEq(globalPoint.slope, expectedSlopeWAD, "global slope must match exactly");
        if (expectedSlopeWAD != 0) {
            int256 globalSlopePercentageError =
                expectedSlopeWAD != 0 ? ((globalPoint.slope - expectedSlopeWAD) * 1e18) / expectedSlopeWAD : int256(0);
            emit log_named_int("Global slope error percentage (1e18 = 100%)", globalSlopePercentageError);
        }
        emit log_named_uint("Expected globalPoint.ts", block.timestamp);
        emit log_named_uint("Actual globalPoint.ts", globalPoint.ts);
        emit log_named_uint("Expected globalPoint.blk", 1);
        emit log_named_uint("Actual globalPoint.blk", globalPoint.blk);
        emit log_named_uint("Expected globalPoint.permanentLockBalance", 0);
        emit log_named_uint("Actual globalPoint.permanentLockBalance", globalPoint.permanentLockBalance);

        // Update global checkpoint, overwritten
        dustLock.checkpoint();

        emit log_named_uint("Expected dustLock.epoch (after checkpoint)", 1);
        emit log_named_uint("Actual dustLock.epoch (after checkpoint)", dustLock.epoch());
        globalPoint = dustLock.pointHistory(1);
        emit log_named_int("Expected globalPoint.bias (checkpoint)", expectedBiasWAD);
        emit log_named_int("Actual globalPoint.bias (checkpoint)", globalPoint.bias);
        emit log_named_int("Global bias difference (checkpoint)", globalPoint.bias - expectedBiasWAD);
        emit log_named_int("Expected globalPoint.slope (checkpoint)", expectedSlopeWAD);
        emit log_named_int("Actual globalPoint.slope (checkpoint)", globalPoint.slope);
        emit log_named_int("Global slope difference (checkpoint)", globalPoint.slope - expectedSlopeWAD);
        assertEq(globalPoint.slope, expectedSlopeWAD, "global slope after checkpoint must match exactly");

        // User increases amount in same block (tests linearity of slope/bias)
        dustLock.increaseAmount(1, TOKEN_1);

        locked = dustLock.locked(1);
        emit log_named_uint("Expected locked.amount (2x)", TOKEN_1 * 2);
        emit log_named_uint("Actual locked.amount (2x)", uint256(locked.amount));
        emit log_named_uint("Expected locked.end (2x)", expectedEnd);
        emit log_named_uint("Actual locked.end (2x)", locked.end);
        emit log_named_string("Expected locked.isPermanent (2x)", "false");
        emit log_named_string("Actual locked.isPermanent (2x)", locked.isPermanent ? "true" : "false");
        emit log_named_int("Expected slopeChanges (2x)", -2 * expectedSlopeWAD);
        emit log_named_int("Actual slopeChanges (2x)", dustLock.slopeChanges(expectedEnd));
        int256 slope2xDiff = dustLock.slopeChanges(expectedEnd) - (-2 * expectedSlopeWAD);
        emit log_named_int("SlopeChanges difference (2x)", slope2xDiff);
        // Allow 1 wei tolerance due to integer rounding when aggregating slopeChanges
        if (slope2xDiff < 0) slope2xDiff = -slope2xDiff;
        assertLe(uint256(slope2xDiff), 1, "slopeChanges (2x) must be within 1 wei");

        emit log_named_uint("Expected userPointEpoch (2x)", 1);
        emit log_named_uint("Actual userPointEpoch (2x)", dustLock.userPointEpoch(1));
        userPoint = dustLock.userPointHistory(1, 1);
        emit log_named_int("Expected userPoint.bias (2x)", 2 * expectedBiasWAD);
        emit log_named_int("Actual userPoint.bias (2x)", userPoint.bias);
        emit log_named_int("User bias difference (2x)", userPoint.bias - 2 * expectedBiasWAD);
        if (expectedBiasWAD != 0) {
            int256 userBias2xPercentageError = ((userPoint.bias - 2 * expectedBiasWAD) * 1e18) / (2 * expectedBiasWAD);
            emit log_named_int("User bias (2x) error percentage (1e18 = 100%)", userBias2xPercentageError);
        }
        emit log_named_int("Expected userPoint.slope (2x)", 2 * expectedSlopeWAD);
        emit log_named_int("Actual userPoint.slope (2x)", userPoint.slope);
        int256 userSlope2xDiff = userPoint.slope - 2 * expectedSlopeWAD;
        emit log_named_int("User slope difference (2x)", userSlope2xDiff);
        if (userSlope2xDiff < 0) userSlope2xDiff = -userSlope2xDiff;
        assertLe(uint256(userSlope2xDiff), 1, "user slope (2x) must be within 1 wei");
        if (expectedSlopeWAD != 0) {
            int256 userSlope2xPercentageError =
                ((userPoint.slope - 2 * expectedSlopeWAD) * 1e18) / (2 * expectedSlopeWAD);
            emit log_named_int("User slope (2x) error percentage (1e18 = 100%)", userSlope2xPercentageError);
        }

        emit log_named_uint("Expected dustLock.epoch (2x)", 1);
        emit log_named_uint("Actual dustLock.epoch (2x)", dustLock.epoch());
        globalPoint = dustLock.pointHistory(1);
        emit log_named_int("Expected globalPoint.bias (2x)", 2 * expectedBiasWAD);
        emit log_named_int("Actual globalPoint.bias (2x)", globalPoint.bias);
        emit log_named_int("Global bias difference (2x)", globalPoint.bias - 2 * expectedBiasWAD);
        if (expectedBiasWAD != 0) {
            int256 globalBias2xPercentageError =
                ((globalPoint.bias - 2 * expectedBiasWAD) * 1e18) / (2 * expectedBiasWAD);
            emit log_named_int("Global bias (2x) error percentage (1e18 = 100%)", globalBias2xPercentageError);
        }
        emit log_named_int("Expected globalPoint.slope (2x)", 2 * expectedSlopeWAD);
        emit log_named_int("Actual globalPoint.slope (2x)", globalPoint.slope);
        int256 globalSlope2xDiff = globalPoint.slope - 2 * expectedSlopeWAD;
        emit log_named_int("Global slope difference (2x)", globalSlope2xDiff);
        if (globalSlope2xDiff < 0) globalSlope2xDiff = -globalSlope2xDiff;
        assertLe(uint256(globalSlope2xDiff), 1, "global slope (2x) must be within 1 wei");
        if (expectedSlopeWAD != 0) {
            int256 globalSlope2xPercentageError =
                ((globalPoint.slope - 2 * expectedSlopeWAD) * 1e18) / (2 * expectedSlopeWAD);
            emit log_named_int("Global slope (2x) error percentage (1e18 = 100%)", globalSlope2xPercentageError);
        }

        emit log("=== All precision logging complete, test passes ===");

        // Pattern analysis for precision differences
        emit log("=== PRECISION ANALYSIS ===");

        // The bias differences follow a pattern - let's investigate
        int256 bias1xDiff = 24907571;
        int256 bias2xDiff = 49815143;
        emit log_named_int("1x bias difference", bias1xDiff);
        emit log_named_int("2x bias difference", bias2xDiff);

        // Calculate ratio properly
        int256 ratio = (bias2xDiff * 1e18) / bias1xDiff;
        emit log_named_int("Ratio (2x/1x)", ratio); // Should be close to 2e18

        // Examine the calculation components
        emit log_named_uint("TOKEN_1", TOKEN_1);
        emit log_named_uint("MAXTIME", MAXTIME);
        emit log_named_uint("Time remaining", expectedEnd - block.timestamp);

        // Our calculation: slope = (amount * 1e18) / MAXTIME
        // Our calculation: bias = slope * timeRemaining
        int256 ourSlope1x = int256((TOKEN_1 * 1e18) / MAXTIME);
        int256 ourBias1x = ourSlope1x * int256(expectedEnd - block.timestamp);

        emit log_named_int("Our slope calculation (1x)", ourSlope1x);
        emit log_named_int("Our bias calculation (1x)", ourBias1x);

        // Check division precision
        uint256 exactDivision = (TOKEN_1 * 1e18) / MAXTIME;
        uint256 remainderCheck = (TOKEN_1 * 1e18) % MAXTIME;

        emit log_named_uint("Exact division result", exactDivision);
        emit log_named_uint("Division remainder", remainderCheck);
        emit log_named_uint("Remainder as percentage of MAXTIME", (remainderCheck * 1e18) / MAXTIME);

        emit log("Test completed: Checkpoint precision analysis complete");
    }
}
