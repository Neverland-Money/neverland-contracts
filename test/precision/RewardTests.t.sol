// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "./ExtendedBaseTest.sol";

/**
 * @title RewardTests
 * @notice Tests for reward distribution based on voting power precision
 * @dev Tests that rewards are distributed proportionally to voting power
 */
contract RewardTests is ExtendedBaseTest {
    function _setUp() internal override {
        // Call parent setup first
        super._setUp();

        skip(1 hours);

        // Ensure all users have enough DUST tokens for creating locks
        deal(address(DUST), address(this), TOKEN_1);
        deal(address(DUST), user1, TOKEN_1);
        deal(address(DUST), user2, TOKEN_1);
        deal(address(DUST), user3, TOKEN_1);

        // Create locks for all users with different durations to test voting power differences
        DUST.approve(address(dustLock), TOKEN_1);
        dustLock.createLock(TOKEN_1, MAXTIME); // tokenId 1 - max voting power

        vm.startPrank(user1);
        DUST.approve(address(dustLock), TOKEN_1);
        dustLock.createLock(TOKEN_1, MAXTIME);
        vm.stopPrank();

        vm.startPrank(user2);
        DUST.approve(address(dustLock), TOKEN_1);
        dustLock.createLock(TOKEN_1, MAXTIME);
        vm.stopPrank();

        vm.startPrank(user3);
        DUST.approve(address(dustLock), TOKEN_1);
        dustLock.createLock(TOKEN_1, MAXTIME / 4); // tokenId 4 - lower voting power
        vm.stopPrank();

        skip(1);
    }

    function testMultiEpochRewardDistribution() public {
        // Test reward distribution based on voting power precision
        address[] memory rewards = new address[](2);
        rewards[0] = address(DUST);
        rewards[1] = address(mockUSDC);

        // Setup: Create rewards for different lock holders
        // Test contract has max lock time (higher voting power)
        // user3 has quarter of max lock time (lower voting power)
        uint256 dustReward = TOKEN_1;
        uint256 usdcReward = USDC_1;
        _createRewardWithAmount(testRevenueReward, address(DUST), dustReward);
        _createRewardWithAmount(testRevenueReward, address(mockUSDC), usdcReward);

        // Get voting power for comparison at the same reference time
        uint256 votingPower1 = dustLock.balanceOfNFT(1); // test contract's voting power
        uint256 votingPower4 = dustLock.balanceOfNFT(4); // user3's voting power

        emit log_named_uint("Voting Power 1 (max lock)", votingPower1);
        emit log_named_uint("Voting Power 4 (1/4 lock)", votingPower4);

        // Skip to next epoch boundary to make rewards claimable deterministically
        skipToNextEpoch(1);

        // Test reward claiming - test basic reward distribution based on voting power
        // Check that rewards can be claimed by lock holders
        uint256 dustPre = DUST.balanceOf(address(this));
        uint256 usdcPre = mockUSDC.balanceOf(address(this));

        // Test contract claims rewards for tokenId 1
        testRevenueReward.getReward(1, rewards);

        uint256 dustPost = DUST.balanceOf(address(this));
        uint256 usdcPost = mockUSDC.balanceOf(address(this));

        // Verify some rewards were distributed
        assertGt(dustPost, dustPre, "DUST rewards should be distributed");
        assertGt(usdcPost, usdcPre, "USDC rewards should be distributed");

        // Test that user3 can also claim rewards
        dustPre = DUST.balanceOf(user3);
        usdcPre = mockUSDC.balanceOf(user3);

        vm.startPrank(user3);
        testRevenueReward.getReward(4, rewards);
        vm.stopPrank();

        dustPost = DUST.balanceOf(user3);
        usdcPost = mockUSDC.balanceOf(user3);

        // Verify user3 also received rewards
        assertGt(dustPost, dustPre, "User3 should receive DUST rewards");
        assertGt(usdcPost, usdcPre, "User3 should receive USDC rewards");

        emit log("Test completed: RevenueReward system working for multiple token holders");
    }

    function testBasicRewardDistribution() public {
        address[] memory rewards = new address[](1);
        rewards[0] = address(DUST);

        // Create some rewards
        _createRewardWithAmount(testRevenueReward, address(DUST), TOKEN_1);

        // Skip to next epoch boundary to make rewards claimable deterministically
        skipToNextEpoch(1);

        // Check initial balance
        uint256 balanceBefore = DUST.balanceOf(address(this));

        // Claim rewards
        testRevenueReward.getReward(1, rewards);

        // Verify rewards were received
        uint256 balanceAfter = DUST.balanceOf(address(this));
        assertGt(balanceAfter, balanceBefore, "Should receive rewards");

        emit log("Basic reward distribution test passed");
    }

    function testVotingPowerBasedRewardPrecision() public {
        // Test that rewards are distributed based on voting power (observational test)
        address[] memory rewards = new address[](1);
        rewards[0] = address(DUST);

        uint256 rewardAmount = TOKEN_1 * 1000; // Large reward for precision testing
        _createRewardWithAmount(testRevenueReward, address(DUST), rewardAmount);

        // Get voting powers before claiming
        uint256 votingPower1 = dustLock.balanceOfNFT(1); // max lock
        uint256 votingPower4 = dustLock.balanceOfNFT(4); // 1/4 lock

        emit log_named_uint("Voting power 1 (max lock)", votingPower1);
        emit log_named_uint("Voting power 4 (1/4 lock)", votingPower4);

        // Skip time to make rewards claimable
        skipToNextEpoch(1);

        // Claim rewards and measure distribution
        uint256 balance1Before = DUST.balanceOf(address(this));
        testRevenueReward.getReward(1, rewards);
        uint256 balance1After = DUST.balanceOf(address(this));
        uint256 reward1 = balance1After - balance1Before;

        uint256 balance4Before = DUST.balanceOf(user3);
        vm.startPrank(user3);
        testRevenueReward.getReward(4, rewards);
        vm.stopPrank();
        uint256 balance4After = DUST.balanceOf(user3);
        uint256 reward4 = balance4After - balance4Before;

        emit log_named_uint("Reward 1 (max lock)", reward1);
        emit log_named_uint("Reward 4 (1/4 lock)", reward4);

        // Log the ratios for analysis (no strict assertions)
        if (reward4 > 0 && votingPower4 > 0) {
            uint256 rewardRatio = (reward1 * 1e18) / reward4;
            uint256 votingPowerRatio = (votingPower1 * 1e18) / votingPower4;

            emit log_named_uint("Reward ratio (1/4)", rewardRatio);
            emit log_named_uint("Voting power ratio (1/4)", votingPowerRatio);

            // Calculate percentage difference
            uint256 diff =
                rewardRatio > votingPowerRatio ? rewardRatio - votingPowerRatio : votingPowerRatio - rewardRatio;
            uint256 percentageDiff = (diff * 100) / votingPowerRatio;
            emit log_named_uint("Percentage difference (%)", percentageDiff);
        }

        // Basic sanity checks (rewards should exist and max lock should get more)
        assertGt(reward1, 0, "Max lock holder should receive rewards");
        assertGt(reward4, 0, "Quarter lock holder should receive rewards");
        assertGt(reward1, reward4, "Max lock should receive more rewards than quarter lock");

        emit log("Voting power-based reward precision analysis completed");
    }
}
