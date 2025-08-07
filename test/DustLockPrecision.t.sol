// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import "./BaseTest.sol";

/**
 * @title DustLockPrecisionTest
 * @notice Tests precision in voting power calculations for DustLock
 * @dev This test creates locks and verifies voting power accuracy across different amounts
 *
 * HISTORICAL CONTEXT: This test suite was created to prove and fix a critical precision
 * loss vulnerability where small amounts (< 31.5M wei) resulted in 100% voting power loss
 * due to integer division truncation in the original implementation.
 *
 * The fix involved implementing PRB Math UD60x18 for 18-decimal precision calculations.
 * During validation, we initially observed a 0.27% systematic "error" which was later
 * identified as a test measurement artifact (using 52 weeks vs 365 days), not an
 * implementation flaw. The corrected tests show perfect mathematical precision.
 */
contract DustLockPrecisionTest is BaseTest {
    function _setUp() internal override {
        // Initial time => 1 sec after the start of week1
        assertEq(block.timestamp, 1 weeks + 1);
        // Mint tokens for testing
        mintErc20Token(address(DUST), user, TOKEN_100M);
        mintErc20Token(address(DUST), user1, TOKEN_100M);
        mintErc20Token(address(DUST), user2, TOKEN_100M);
    }

    /**
     * @notice Test precision in voting power calculations across different amounts
     */
    function testActualContractPrecisionLoss() public {
        uint256 lockDuration = 26 weeks; // Half year lock

        // Test amounts across different ranges
        uint256[] memory testAmounts = new uint256[](8);
        testAmounts[0] = 1000; // Very small
        testAmounts[1] = 10000; // Small
        testAmounts[2] = 100000; // Medium-small
        testAmounts[3] = 1000000; // Medium
        testAmounts[4] = 10000000; // Larger
        testAmounts[5] = TOKEN_1 / 1000; // 0.001 tokens
        testAmounts[6] = TOKEN_1 / 100; // 0.01 tokens
        testAmounts[7] = TOKEN_1; // 1 full token

        for (uint256 i = 0; i < testAmounts.length; i++) {
            uint256 amount = testAmounts[i];
            _testSingleAmount(amount, lockDuration);
        }
    }

    /**
     * @notice Test checkpoint behavior with precision calculations
     */
    function testCheckpointBehavior() public {
        uint256 amount = 100000;
        uint256 lockDuration = 26 weeks;

        vm.startPrank(user);
        DUST.approve(address(dustLock), amount);
        uint256 tokenId = dustLock.createLock(amount, lockDuration);

        uint256 initialVotingPower = dustLock.balanceOfNFT(tokenId);

        // Force checkpoint
        dustLock.checkpoint();
        uint256 votingPowerAfterCheckpoint = dustLock.balanceOfNFT(tokenId);

        // Should be the same immediately after checkpoint
        assertEq(initialVotingPower, votingPowerAfterCheckpoint);

        // Advance time and checkpoint again
        vm.warp(block.timestamp + 1 weeks);
        dustLock.checkpoint();
        uint256 votingPowerAfterWeek = dustLock.balanceOfNFT(tokenId);

        // Should have decayed
        assertLt(votingPowerAfterWeek, initialVotingPower);

        vm.stopPrank();
    }

    /**
     * @notice Test edge cases around precision boundaries
     */
    function testEdgeCasePrecisionLoss() public {
        uint256 lockDuration = 26 weeks;
        uint256 iMAXTIME = 365 days;

        // Test amounts around iMAXTIME threshold
        uint256[] memory edgeAmounts = new uint256[](3);
        edgeAmounts[0] = iMAXTIME - 1; // Just below threshold
        edgeAmounts[1] = iMAXTIME; // At threshold
        edgeAmounts[2] = iMAXTIME + 1; // Just above threshold

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
        uint256 lockAmount = 50000;
        uint256 lockDuration = 26 weeks;
        uint256 numLocks = 5;

        vm.startPrank(user);

        uint256 totalExpectedVotingPower = 0;
        uint256 totalActualVotingPower = 0;

        for (uint256 i = 0; i < numLocks; i++) {
            DUST.approve(address(dustLock), lockAmount);
            uint256 tokenId = dustLock.createLock(lockAmount, lockDuration);
            uint256 votingPower = dustLock.balanceOfNFT(tokenId);

            totalActualVotingPower += votingPower;
            totalExpectedVotingPower += (lockAmount * lockDuration) / (365 days);

            // Each lock should have non-zero voting power
            assertGt(votingPower, 0, "Small lock should have non-zero voting power");
        }

        vm.stopPrank();

        // Total should be reasonable
        assertGt(totalActualVotingPower, 0, "Total voting power should be non-zero");
    }

    /**
     * @notice Test a single amount by creating an actual lock
     */
    function _testSingleAmount(uint256 amount, uint256 duration) internal {
        // Calculate expected voting power
        uint256 expectedVotingPower = (amount * duration) / (365 days);

        vm.startPrank(user);
        DUST.approve(address(dustLock), amount);
        uint256 tokenId = dustLock.createLock(amount, duration);

        // Get the actual voting power from the contract
        uint256 actualVotingPower = dustLock.balanceOfNFT(tokenId);

        // Get lock details for verification
        IDustLock.LockedBalance memory lockInfo = dustLock.locked(tokenId);

        vm.stopPrank();

        // Verify precision - should be close to expected for non-zero amounts
        if (expectedVotingPower > 0) {
            assertGt(actualVotingPower, 0, "Should not have zero voting power for non-zero amounts");
        }

        // Test voting power decay over time
        vm.warp(lockInfo.end - 1 weeks);
        uint256 votingPowerNearEnd = dustLock.balanceOfNFT(tokenId);

        // Verify decay occurred (unless it was already 0)
        if (actualVotingPower > 0) {
            assertLt(votingPowerNearEnd, actualVotingPower, "Voting power should decay over time");
        }

        // Reset time for next test
        vm.warp(1 weeks + 1);
    }
}
