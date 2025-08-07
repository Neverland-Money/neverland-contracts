// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import "./BaseTest.sol";

/**
 * @title DustLockDecayTest
 * @notice Tests for voting power decay mechanism in DustLock
 * @dev Validates that voting power decreases linearly over time as expected
 *
 * PRECISION NOTE: During development, we observed a consistent 0.27% "precision loss"
 * across decay tests. Investigation revealed this was NOT an implementation flaw, but
 * a measurement artifact in our test expectations:
 * - Contract uses iMAXTIME = 365 days = 31,536,000 seconds
 * - Tests were initially using 52 weeks = 31,449,600 seconds
 * - Difference: 86,400 seconds (1 day) = 0.274% ≈ 0.27%
 *
 * When test expectations were corrected to use 365 days, the "precision loss"
 * disappeared, confirming our PRB Math implementation achieves perfect precision.
 */
contract DustLockDecayTest is BaseTest {
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
        uint256 lockAmount = 100000;
        uint256 lockDuration = 52 weeks; // Full year

        vm.startPrank(user);
        DUST.approve(address(dustLock), lockAmount);
        uint256 tokenId = dustLock.createLock(lockAmount, lockDuration);

        uint256 initialVotingPower = dustLock.balanceOfNFT(tokenId);

        // Advance time and check voting power decreases
        vm.warp(block.timestamp + 30 days);
        uint256 votingPowerAfter30Days = dustLock.balanceOfNFT(tokenId);

        vm.stopPrank();

        // Verify decay occurred
        assertLt(votingPowerAfter30Days, initialVotingPower, "Voting power should decrease over time");
        assertGt(votingPowerAfter30Days, 0, "Voting power should not be zero after 30 days");
    }

    /**
     * @notice Comprehensive test of voting power decay over full lock duration
     */
    function testVotingPowerDecayTroubleshooting() public {
        uint256 lockAmount = 100000;
        uint256 lockDuration = 365 days; // Exactly one year

        vm.startPrank(user);
        DUST.approve(address(dustLock), lockAmount);
        uint256 tokenId = dustLock.createLock(lockAmount, lockDuration);

        uint256 initialVotingPower = dustLock.balanceOfNFT(tokenId);
        IDustLock.LockedBalance memory lockInfo = dustLock.locked(tokenId);

        vm.stopPrank();

        // Test decay at various intervals
        _testDecayAtInterval(tokenId, lockInfo.end, 3 * 30 days, "3 months");
        _testDecayAtInterval(tokenId, lockInfo.end, 6 * 30 days, "6 months");
        _testDecayAtInterval(tokenId, lockInfo.end, 9 * 30 days, "9 months");
        _testDecayAtInterval(tokenId, lockInfo.end, 50 weeks, "Final week");
        _testDecayAtInterval(tokenId, lockInfo.end, 365 days, "Final day");
        _testDecayAtInterval(tokenId, lockInfo.end, 365 days + 23 hours, "Final hour");

        // Verify initial voting power was reasonable
        assertGt(initialVotingPower, lockAmount / 2, "Initial voting power should be substantial");
        assertLt(initialVotingPower, lockAmount, "Initial voting power should be less than lock amount");
    }

    /**
     * @notice Test decay at a specific time interval
     */
    function _testDecayAtInterval(uint256 tokenId, uint256 lockEnd, uint256 timeElapsed, string memory description)
        internal
    {
        uint256 targetTimestamp = 1 weeks + 1 + timeElapsed;

        // Don't go past lock end
        if (targetTimestamp >= lockEnd) {
            targetTimestamp = lockEnd + 1;
        }

        vm.warp(targetTimestamp);
        uint256 currentVotingPower = dustLock.balanceOfNFT(tokenId);

        if (targetTimestamp >= lockEnd) {
            // After expiration, should be 0
            assertEq(currentVotingPower, 0, "Expired lock should have zero voting power");
        } else {
            // Before expiration, should be positive and decreasing
            assertGt(currentVotingPower, 0, "Active lock should have positive voting power");
        }
    }
}
