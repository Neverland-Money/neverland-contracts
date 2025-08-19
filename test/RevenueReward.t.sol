// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IRevenueReward} from "../src/interfaces/IRevenueReward.sol";

import "./BaseTest.sol";

contract RevenueRewardsTest is BaseTest {
    MockERC20 mockDAI = new MockERC20("DAI", "DAI", 18);

    // Declare the event locally
    event ClaimRewards(address indexed user, address indexed token, uint256 amount);
    event SelfRepayingLoanUpdate(uint256 indexed token, address rewardReceiver, bool isEnabled);

    function _setUp() internal view override {
        // Initial time => 1 sec after the start of week1
        assertEq(block.timestamp, 1 weeks + 1);
    }

    /* ========== TEST NOTIFY REWARD ========== */

    function testNotifyRewardAmount() public {
        // arrange & act
        emit log("[revenue] Notifying reward amount");
        _addReward(admin, mockUSDC, USDC_10K);
        // assert
        uint256 contractBalance = mockUSDC.balanceOf(address(revenueReward));
        emit log_named_uint("[revenue] RevenueReward balance (USDC)", contractBalance);
        assertEq(contractBalance, USDC_10K);
    }

    function testNotifyRewardAmountFromNonRewardDistributor() public {
        mintErc20Token(address(mockUSDC), user1, USDC_10K);

        vm.startPrank(user1);
        mockUSDC.approve(address(revenueReward), USDC_10K);
        emit log("[revenue] Expect revert: non-distributor notifying reward");
        vm.expectRevert(abi.encodeWithSelector(IRevenueReward.NotRewardDistributor.selector));
        revenueReward.notifyRewardAmount(address(mockUSDC), USDC_10K);
        vm.stopPrank();
    }

    function testSettingNewRewardDistributorFromAnyUser() public {
        emit log("[revenue] Expect revert: setRewardDistributor from non-distributor");
        vm.expectRevert(abi.encodeWithSelector(IRevenueReward.NotRewardDistributor.selector));
        revenueReward.setRewardDistributor(user1);
    }

    function testSettingNewRewardDistributor() public {
        _addReward(admin, mockUSDC, USDC_10K);

        vm.prank(admin);
        emit log_named_address("[revenue] Setting new reward distributor", user1);
        revenueReward.setRewardDistributor(user1);

        _addReward(user1, mockUSDC, USDC_10K);
    }

    /* ========== TEST GET REWARD ========== */

    function testSingleUserSingleEpochClaim() public {
        // arrange
        assertEq(block.timestamp, 1 weeks + 1);
        uint256 tokenId = _createLock(user, TOKEN_1, MAXTIME);
        emit log_named_uint("[claim] tokenId", tokenId);
        _addReward(admin, mockUSDC, USDC_10K); // adds reward at the start of next epoch

        skipToNextEpoch(1);
        assertEq(block.timestamp, 2 weeks + 1);

        assertEq(mockUSDC.balanceOf(user), 0);
        assertEq(revenueReward.lastEarnTime(address(mockUSDC), tokenId), 0);

        // act
        vm.expectEmit(true, true, false, false, address(revenueReward));
        emit ClaimRewards(user, address(mockUSDC), 0); // The actual amount will be dynamic

        address[] memory tokens = new address[](1);
        tokens[0] = address(mockUSDC);
        revenueReward.getReward(tokenId, tokens);

        // assert
        uint256 balanceAfter = mockUSDC.balanceOf(user);
        uint256 lastEarnTimeAfter = revenueReward.lastEarnTime(address(mockUSDC), tokenId);

        uint256 rewardAmount = balanceAfter;
        emit log_named_uint("[claim] USDC claimed", rewardAmount);
        emit log_named_uint("[claim] lastEarnTime", lastEarnTimeAfter);

        assertEqApprThreeWei(rewardAmount, USDC_10K);
        assertEq(lastEarnTimeAfter, block.timestamp);
    }

    function testUserSingleEpochClaimAndReclaim() public {
        // arrange
        assertEq(block.timestamp, 1 weeks + 1);
        uint256 tokenId = _createLock(user, TOKEN_1, MAXTIME);
        emit log_named_uint("[claim/repeat] tokenId", tokenId);
        _addReward(admin, mockUSDC, USDC_10K); // adds reward at the start of next epoch

        skipToNextEpoch(1);
        assertEq(block.timestamp, 2 weeks + 1);

        assertEq(mockUSDC.balanceOf(user), 0);

        // act
        address[] memory tokens = new address[](1);
        tokens[0] = address(mockUSDC);

        revenueReward.getReward(tokenId, tokens);
        revenueReward.getReward(tokenId, tokens);
        revenueReward.getReward(tokenId, tokens);

        // assert
        uint256 balanceAfter = mockUSDC.balanceOf(user);
        uint256 lastEarnTimeAfter = revenueReward.lastEarnTime(address(mockUSDC), tokenId);

        uint256 rewardAmount = balanceAfter;
        emit log_named_uint("[claim/repeat] total USDC claimed", rewardAmount);
        emit log_named_uint("[claim/repeat] lastEarnTime", lastEarnTimeAfter);

        assertEqApprThreeWei(rewardAmount, USDC_10K);
        assertEq(lastEarnTimeAfter, block.timestamp);
    }

    function testSingleUserMultiEpochClaim() public {
        // epoch 1
        uint256 tokenId = _createLock(user, TOKEN_1, MAXTIME);
        emit log_named_uint("[claim/multi-epoch] tokenId", tokenId);
        _addReward(admin, mockUSDC, USDC_10K); // adds reward at the start of next epoch

        // epoch 2
        skipToNextEpoch(1);
        address[] memory tokens = new address[](1);
        tokens[0] = address(mockUSDC);
        revenueReward.getReward(tokenId, tokens);

        // epoch 3
        skipToNextEpoch(1);
        _addReward(admin, mockUSDC, USDC_10K); // adds reward at the start of next epoch

        skipToNextEpoch(1);
        revenueReward.getReward(tokenId, tokens);

        // assert
        uint256 balanceAfter = mockUSDC.balanceOf(user);
        uint256 lastEarnTimeAfter = revenueReward.lastEarnTime(address(mockUSDC), tokenId);

        uint256 rewardAmount = balanceAfter;
        emit log_named_uint("[claim/multi-epoch] cumulative USDC claimed", rewardAmount);

        assertApproxEqAbs(rewardAmount, 2 * USDC_10K, 3);
        assertEq(lastEarnTimeAfter, block.timestamp);
    }

    function testUserClaimRewardsUntilTimestamp() public {
        // epoch 1
        assertEq(block.timestamp, 1 weeks + 1);
        uint256 tokenId = _createLock(user, TOKEN_1, MAXTIME);
        emit log_named_uint("[claim/partial] tokenId", tokenId);
        _addReward(admin, mockUSDC, USDC_10K); // adds reward at the start of next epoch

        // epoch 2
        skipToNextEpoch(1);
        assertEq(block.timestamp, 2 weeks + 1);
        address[] memory tokens = new address[](1);
        tokens[0] = address(mockUSDC);

        // epoch 3
        skipToNextEpoch(1);
        assertEq(block.timestamp, 3 weeks + 1);
        _addReward(admin, mockUSDC, USDC_10K); // adds reward at the start of next epoch

        // epoch 4
        skipToNextEpoch(1);
        assertEq(block.timestamp, 4 weeks + 1);

        // act
        emit log_named_uint("[claim/partial] claiming until", 2 weeks + 1);
        revenueReward.getRewardUntilTs(tokenId, tokens, 2 weeks + 1);
        // assert
        assertApproxEqAbs(mockUSDC.balanceOf(user), USDC_10K, 2);
        assertEq(revenueReward.lastEarnTime(address(mockUSDC), tokenId), 2 weeks + 1);

        // act
        emit log_named_uint("[claim/partial] claiming until", 4 weeks + 1);
        revenueReward.getRewardUntilTs(tokenId, tokens, 4 weeks + 1);
        // assert
        assertApproxEqAbs(mockUSDC.balanceOf(user), 2 * USDC_10K, 3);
        assertEq(revenueReward.lastEarnTime(address(mockUSDC), tokenId), 4 weeks + 1);

        // act
        emit log_named_uint("[claim/partial] claiming until", 4 weeks + 1);
        revenueReward.getRewardUntilTs(tokenId, tokens, 4 weeks + 1);
        // assert
        assertApproxEqAbs(mockUSDC.balanceOf(user), 2 * USDC_10K, 3);
        assertEq(revenueReward.lastEarnTime(address(mockUSDC), tokenId), 4 weeks + 1);
    }

    function testMultipleUsersWithDifferentBalances() public {
        // arrange
        uint256 user1TokenId = _createLock(user1, TOKEN_1 * 2, MAXTIME);
        uint256 user2TokenId = _createLock(user2, TOKEN_1, MAXTIME);
        emit log_named_uint("[claim/multi-user] user1 tokenId", user1TokenId);
        emit log_named_uint("[claim/multi-user] user2 tokenId", user2TokenId);

        _addReward(admin, mockUSDC, USDC_10K);

        skipToNextEpoch(1);
        // Record state before claims
        uint256 user1BalanceBefore = mockUSDC.balanceOf(user1);
        uint256 user2BalanceBefore = mockUSDC.balanceOf(user2);

        // User1 claims
        vm.startPrank(user1);
        address[] memory tokens = new address[](1);
        tokens[0] = address(mockUSDC);
        revenueReward.getReward(user1TokenId, tokens);
        vm.stopPrank();

        // User2 claims
        vm.startPrank(user2);
        revenueReward.getReward(user2TokenId, tokens);
        vm.stopPrank();

        // Assertions
        uint256 user1Reward = mockUSDC.balanceOf(user1) - user1BalanceBefore;
        uint256 user2Reward = mockUSDC.balanceOf(user2) - user2BalanceBefore;

        emit log_named_uint("[claim/multi-user] user1 USDC claimed", user1Reward);
        emit log_named_uint("[claim/multi-user] user2 USDC claimed", user2Reward);
        // Alice should receive approximately twice as much reward as Bob (within small margin for rounding)
        assertApproxEqRel(user1Reward, user2Reward * 2, 1, "Rewards not proportional to veNFT balances");

        // The sum of rewards should not exceed the total rewards
        assertLe(user1Reward + user2Reward, USDC_10K, "Total claimed exceeds available rewards");
    }

    function testSingleUserForMultipleUnclaimedPastEpochs() public {
        // epoch 1
        uint256 tokenId = _createLock(user, TOKEN_1, MAXTIME);
        emit log_named_uint("[claim/unclaimed] tokenId", tokenId);
        _addReward(admin, mockUSDC, USDC_10K); // adds reward at the start of next epoch

        skipToNextEpoch(1);
        address[] memory tokens = new address[](1);
        tokens[0] = address(mockUSDC);
        //revenueReward.getReward(tokenId, tokens);

        // epoch2
        skipToNextEpoch(1);
        _addReward(admin, mockUSDC, USDC_10K); // adds reward at the start of next epoch

        skipToNextEpoch(1);
        revenueReward.getReward(tokenId, tokens);

        // assert
        uint256 balanceAfter = mockUSDC.balanceOf(user);
        uint256 lastEarnTimeAfter = revenueReward.lastEarnTime(address(mockUSDC), tokenId);

        uint256 rewardAmount = balanceAfter;
        emit log_named_uint("[claim/unclaimed] cumulative USDC claimed", rewardAmount);

        assertApproxEqAbs(rewardAmount, 2 * USDC_10K, 3);
        assertEq(lastEarnTimeAfter, block.timestamp);
    }

    function testMultipleForMultipleUnclaimedPastEpochs() public {
        // arrange
        uint256 user1TokenId = _createLock(user1, TOKEN_1 * 2, MAXTIME);
        uint256 user2TokenId = _createLock(user2, TOKEN_1, MAXTIME);
        emit log_named_uint("[claim/unclaimed multi] user1 tokenId", user1TokenId);
        emit log_named_uint("[claim/unclaimed multi] user2 tokenId", user2TokenId);

        _addReward(admin, mockUSDC, USDC_10K);

        skipToNextEpoch(1);
        // Record state before claims
        uint256 user1BalanceBefore = mockUSDC.balanceOf(user1);
        uint256 user2BalanceBefore = mockUSDC.balanceOf(user2);

        skipToNextEpoch(1);
        _addReward(admin, mockUSDC, USDC_10K);

        skipToNextEpoch(1);

        // User1 claims
        vm.startPrank(user1);
        address[] memory tokens = new address[](1);
        tokens[0] = address(mockUSDC);
        revenueReward.getReward(user1TokenId, tokens);
        vm.stopPrank();

        // User2 claims
        vm.startPrank(user2);
        revenueReward.getReward(user2TokenId, tokens);
        vm.stopPrank();

        // Assertions
        uint256 user1Reward = mockUSDC.balanceOf(user1) - user1BalanceBefore;
        uint256 user2Reward = mockUSDC.balanceOf(user2) - user2BalanceBefore;

        emit log_named_uint("[claim/unclaimed multi] user1 USDC claimed", user1Reward);
        emit log_named_uint("[claim/unclaimed multi] user2 USDC claimed", user2Reward);
        // Alice should receive approximately twice as much reward as Bob (within small margin for rounding)
        // Use absolute tolerance instead of relative for better control
        assertApproxEqAbs(user1Reward, user2Reward * 2, 2);

        // The sum of rewards should not exceed the total rewards
        assertLe(user1Reward + user2Reward, 2 * USDC_10K);
    }

    function testClaimingForSubsetOfTokens() public {
        uint256 tokenId = _createLock(user1, TOKEN_1, MAXTIME);
        emit log_named_uint("[claim/subset] tokenId", tokenId);

        // Add rewards for both tokens
        _addReward(admin, mockDAI, TOKEN_10K);
        _addReward(admin, mockUSDC, USDC_10K);

        // Skip to next epoch
        skipToNextEpoch(1);

        // Record state before claim
        uint256 daiBalanceBefore = mockDAI.balanceOf(user1);
        uint256 usdcLastEarnTimeBefore = revenueReward.lastEarnTime(address(mockUSDC), tokenId);
        uint256 daiLastEarnTimeBefore = revenueReward.lastEarnTime(address(mockDAI), tokenId);

        // user1 claims only USDC rewards
        vm.startPrank(user1);
        address[] memory tokens = new address[](1);
        tokens[0] = address(mockUSDC);
        revenueReward.getReward(tokenId, tokens);
        vm.stopPrank();

        // assert
        emit log_named_uint("[claim/subset] USDC claimed", mockUSDC.balanceOf(user1));
        emit log_named_uint("[claim/subset] DAI claimed", mockDAI.balanceOf(user1));
        assertEqApprThreeWei(mockUSDC.balanceOf(user1), USDC_10K);
        assertEqApprThreeWei(mockDAI.balanceOf(user1), daiBalanceBefore);
        assertGt(revenueReward.lastEarnTime(address(mockUSDC), tokenId), usdcLastEarnTimeBefore);
        assertEq(revenueReward.lastEarnTime(address(mockDAI), tokenId), daiLastEarnTimeBefore);
    }

    function testAttemptingToClaimTwice() public {
        uint256 tokenId = _createLock(user1, TOKEN_1, MAXTIME);
        emit log_named_uint("[claim/twice] tokenId", tokenId);
        _addReward(admin, mockUSDC, USDC_10K);

        skipToNextEpoch(1);

        // First claim
        vm.startPrank(user1);
        address[] memory tokens = new address[](1);
        tokens[0] = address(mockUSDC);
        revenueReward.getReward(tokenId, tokens);

        // Record state after first claim
        uint256 balanceAfterFirstClaim = mockUSDC.balanceOf(user1);
        emit log_named_uint("[claim/twice] balance after first claim (USDC)", balanceAfterFirstClaim);

        // Second claim immediately after
        revenueReward.getReward(tokenId, tokens);
        vm.stopPrank();

        assertEq(mockUSDC.balanceOf(user1), balanceAfterFirstClaim);
    }

    function testRewardPrecision() public {
        // arrange
        uint256 userTokenId1 = _createLock(user, TOKEN_1K, MAXTIME);
        uint256 user2TokenId1 = _createLock(user2, TOKEN_100M, MAXTIME);
        emit log_named_uint("[precision] user1 tokenId", userTokenId1);
        emit log_named_uint("[precision] user2 tokenId", user2TokenId1);

        _addReward(admin, mockUSDC, USDC_1);

        skipToNextEpoch(1);

        // act
        address[] memory tokens = new address[](1);
        tokens[0] = address(mockUSDC);

        revenueReward.getReward(userTokenId1, tokens);

        vm.prank(user2);
        revenueReward.getReward(user2TokenId1, tokens);

        // assert

        emit log_named_uint("[precision] user1 USDC claimed", mockUSDC.balanceOf(user));
        emit log_named_uint("[precision] user2 USDC claimed", mockUSDC.balanceOf(user2));
        assertEq(mockUSDC.balanceOf(user), 9);
        assertEq(mockUSDC.balanceOf(user2), 999990);
    }

    function testRewardPrecisionLossAccumulationInMultipleEpochs() public {
        address[] memory tokens = new address[](1);
        tokens[0] = address(mockUSDC);

        // epoch2
        goToEpoch(2);

        _addReward(admin, mockUSDC, USDC_1);

        uint256 userTokenId1 = _createPermanentLock(user, 190 * TOKEN_1, MAXTIME);
        _createPermanentLock(user1, 80 * TOKEN_1M, MAXTIME);

        // epoch3
        goToEpoch(3);

        _addReward(admin, mockUSDC, USDC_1);

        revenueReward.getReward(userTokenId1, tokens); // 1e6 * 190e18 / (80e24 + 190e18) = 2.374994359388396
        assertEq(mockUSDC.balanceOf(user), 2);
        assertEq(revenueReward.tokenRewardsRemainingAccScaled(address(mockUSDC), userTokenId1), 37499435);

        _increaseAmount(user, userTokenId1, 70 * TOKEN_1); // 260
        _createPermanentLock(user3, TOKEN_1M, MAXTIME);

        // epoch4
        goToEpoch(4);

        _addReward(admin, mockUSDC, USDC_1);

        revenueReward.getReward(userTokenId1, tokens); // 1e6 * 260e18 / (80e24 + 1e24 + 260e18) = 3.209866239935526
        assertEq(mockUSDC.balanceOf(user), 2 + 3);
        assertEq(revenueReward.tokenRewardsRemainingAccScaled(address(mockUSDC), userTokenId1), 37499435 + 20986623);

        _increaseAmount(user, userTokenId1, 360 * TOKEN_1); // 620
        _createPermanentLock(user3, 50 * TOKEN_10K, MAXTIME);

        // epoch5
        goToEpoch(5);

        // 1e6 * 620e18 / (80e24 + 1e24 + 50e22 + 620e18)  = 7.607304091674394
        // 37499435 + 20986623 + 60730409 = 119216467
        // extra reward: 119216467 // 1e8 = 1
        // new remaining = 119216467 - 1e8 = 19216467
        revenueReward.getReward(userTokenId1, tokens);
        assertEq(mockUSDC.balanceOf(user), 2 + 3 + 7 + 1);
        assertEq(revenueReward.tokenRewardsRemainingAccScaled(address(mockUSDC), userTokenId1), 19216467);
    }

    /* ========== TEST DUST LOCK INTERACTIONS ========== */

    function testAutoClaimedRewardsForEarlyWithdrawnTokens() public {
        // arrange
        assertEq(block.timestamp, 1 weeks + 1);

        uint256 tokenId = _createLock(user, TOKEN_1, MAXTIME);
        emit log_named_uint("[auto-claim/earlyWithdraw] tokenId", tokenId);
        _addReward(admin, mockUSDC, USDC_10K); // adds reward at the start of next epoch

        goToEpoch(2);

        // act
        emit log("[auto-claim/earlyWithdraw] earlyWithdraw called");
        dustLock.earlyWithdraw(tokenId);

        // assert
        emit log_named_uint("[auto-claim/earlyWithdraw] USDC received", mockUSDC.balanceOf(user));
        assertEqApprThreeWei(mockUSDC.balanceOf(user), USDC_10K);
        assertEq(revenueReward.lastEarnTime(address(mockUSDC), tokenId), block.timestamp);
    }

    function testAutoClaimedRewardsForWithdrawnTokens() public {
        // arrange
        assertEq(block.timestamp, 1 weeks + 1);

        uint256 tokenId = _createLock(user, TOKEN_1, MAXTIME);
        emit log_named_uint("[auto-claim/withdraw] tokenId", tokenId);
        _addReward(admin, mockUSDC, USDC_10K); // adds reward at the start of next epoch

        skipAndRoll(MAXTIME);

        // act
        emit log("[auto-claim/withdraw] withdraw called");
        dustLock.withdraw(tokenId);

        // assert
        emit log_named_uint("[auto-claim/withdraw] USDC received", mockUSDC.balanceOf(user));
        assertEqApprThreeWei(mockUSDC.balanceOf(user), USDC_10K);
        assertEq(revenueReward.lastEarnTime(address(mockUSDC), tokenId), block.timestamp);
    }

    function testAutoClaimedRewardsForTransferredTokens() public {
        // arrange
        assertEq(block.timestamp, 1 weeks + 1);

        uint256 tokenId = _createLock(user, TOKEN_1, MAXTIME);
        emit log_named_uint("[auto-claim/transfer] tokenId", tokenId);
        _addReward(admin, mockUSDC, USDC_10K); // adds reward at the start of next epoch

        goToEpoch(2);

        // act / assert
        emit log("[auto-claim/transfer] transferFrom to user2");
        dustLock.transferFrom(user, user2, tokenId);

        address[] memory tokens = new address[](1);
        tokens[0] = address(mockUSDC);

        vm.prank(user2);
        revenueReward.getReward(tokenId, tokens);

        emit log_named_uint("[auto-claim/transfer] user USDC", mockUSDC.balanceOf(user));
        emit log_named_uint("[auto-claim/transfer] user2 USDC", mockUSDC.balanceOf(user2));
        assertEqApprThreeWei(mockUSDC.balanceOf(user), USDC_10K);
        assertEqApprThreeWei(mockUSDC.balanceOf(user2), 0);
        assertEq(revenueReward.lastEarnTime(address(mockUSDC), tokenId), block.timestamp);

        // act / assert
        _addReward(admin, mockUSDC, 2 * USDC_10K);

        goToEpoch(3);

        vm.prank(user2);
        revenueReward.getReward(tokenId, tokens);

        // assert
        emit log_named_uint("[auto-claim/transfer] user USDC", mockUSDC.balanceOf(user));
        emit log_named_uint("[auto-claim/transfer] user2 USDC", mockUSDC.balanceOf(user2));
        assertEqApprThreeWei(mockUSDC.balanceOf(user), USDC_10K);
        assertEqApprThreeWei(mockUSDC.balanceOf(user2), 2 * USDC_10K);
        assertEq(revenueReward.lastEarnTime(address(mockUSDC), tokenId), block.timestamp);
    }

    /* ========== TEST GET REWARD GAS ========== */

    function testInitialGetRewardGasCosts() public {
        ///*** create a token on epoch 300, get reward on epoch 301 ***//
        goToEpoch(300);

        _addReward(admin, mockUSDC, USDC_10K);
        uint256 tokenId2 = _createLock(user, TOKEN_1, MAXTIME);

        skipNumberOfEpochs(1); // week 301

        address[] memory tokens = new address[](1);
        tokens[0] = address(mockUSDC);

        uint256 gasStart = gasleft();
        revenueReward.getReward(tokenId2, tokens);
        uint256 gasUsed = gasStart - gasleft();
        emit log_named_uint("[gas] getReward (initial)", gasUsed);
        assertLt(gasUsed, 100_000); // About 80K
    }

    function testGetRewardGasCostsForLongUnclaimedDuration() public {
        ///*** getting 300 epochs unclaimed rewards (epoch300 - epoch600) in one tx  ***//
        goToEpoch(300);

        uint256 tokenId1 = _createLock(user, TOKEN_1, MAXTIME);
        dustLock.lockPermanent(tokenId1);

        for (uint256 i = 0; i < 300; i++) {
            _addReward(admin, mockUSDC, USDC_1);
            skipNumberOfEpochs(1);
        }
        assertEq(block.timestamp, 600 weeks);

        dustLock.checkpoint();

        address[] memory tokens = new address[](1);
        tokens[0] = address(mockUSDC);

        uint256 gasStart = gasleft();
        revenueReward.getReward(tokenId1, tokens);
        uint256 gasUsed = gasStart - gasleft();

        assertEq(mockUSDC.balanceOf(user), 300 * 1e6);

        emit log_named_uint("[gas] getReward (300 epochs)", gasUsed);
        assertLt(gasUsed, 6_000_000); // about 5M
    }

    function testGetRewardUntilTsGasCostsForLongUnclaimedDuration() public {
        ///*** getting 300 epochs (epoch300 - epoch 600) unclaimed rewards in multiple txs ***//
        goToEpoch(300);

        uint256 tokenId2 = _createLock(user, TOKEN_1, MAXTIME);
        dustLock.lockPermanent(tokenId2);

        for (uint256 i = 0; i < 300; i++) {
            _addReward(admin, mockUSDC, USDC_1);
            skipNumberOfEpochs(1);
            if (i % 5 == 0) dustLock.checkpoint(); // simulate user activity every 5 epochs
        }
        assertEq(block.timestamp, 600 weeks);

        uint256 gasStart;
        uint256[] memory gasPerGetRewardUntilTs = new uint256[](10);
        uint256 endTs = 300 weeks + 30 weeks;
        address[] memory tokens = new address[](1);
        tokens[0] = address(mockUSDC);

        for (uint256 i = 0; i < 10; i++) {
            gasStart = gasleft();
            revenueReward.getRewardUntilTs(tokenId2, tokens, endTs);
            gasPerGetRewardUntilTs[i] = gasStart - gasleft();
            endTs += 30 weeks;
        }

        for (uint256 i = 0; i < 10; i++) {
            emit log_named_uint(
                string(abi.encodePacked("[gas] getRewardUntilTs[", vm.toString(i), "]")), gasPerGetRewardUntilTs[i]
            );
            assertLt(gasPerGetRewardUntilTs[i], 550_000); // about 450K - 500K
        }
        assertEq(mockUSDC.balanceOf(user), 300 * 1e6);
    }

    /* ========== TEST SELF REPAYING LOAN ========== */

    function testEnableSelfRepayLoanCantBeSetByNonTokenOwner() public {
        // arrange
        uint256 tokenId = _createLock(user, TOKEN_1, MAXTIME);
        _addReward(admin, mockUSDC, USDC_10K); // adds reward at the start of next epoch

        // act/assert
        vm.startPrank(user2);
        emit log("[self-repay] Expect revert: enable by non-owner");
        vm.expectRevert(abi.encodeWithSelector(IRevenueReward.NotOwner.selector));
        revenueReward.enableSelfRepayLoan(tokenId, user2);
        vm.stopPrank();
    }

    function testDisableSelfRepayLoanCantBeSetByNonTokenOwner() public {
        // arrange
        uint256 tokenId = _createLock(user, TOKEN_1, MAXTIME);
        _addReward(admin, mockUSDC, USDC_10K); // adds reward at the start of next epoch

        revenueReward.enableSelfRepayLoan(tokenId, user2);

        // act/assert
        vm.startPrank(user2);
        emit log("[self-repay] Expect revert: disable by non-owner");
        vm.expectRevert(abi.encodeWithSelector(IRevenueReward.NotOwner.selector));
        revenueReward.disableSelfRepayLoan(tokenId);
        vm.stopPrank();
    }

    function testEnableSelfRepayLoan() public {
        // arrange
        assertEq(block.timestamp, 1 weeks + 1);
        uint256 tokenId = _createLock(user, TOKEN_1, MAXTIME);
        _addReward(admin, mockUSDC, USDC_10K); // adds reward at the start of next epoch

        skipToNextEpoch(1);
        assertEq(block.timestamp, 2 weeks + 1);

        // act
        vm.expectEmit(true, true, true, false, address(revenueReward));
        emit SelfRepayingLoanUpdate(tokenId, user2, true);
        emit log_named_uint("[self-repay] tokenId", tokenId);
        emit log_named_address("[self-repay] receiver", user2);
        revenueReward.enableSelfRepayLoan(tokenId, user2);

        address[] memory tokens = new address[](1);
        tokens[0] = address(mockUSDC);
        revenueReward.getReward(tokenId, tokens);

        // assert
        assertEqApprThreeWei(mockUSDC.balanceOf(user), 0);

        uint256 balanceAfter = mockUSDC.balanceOf(user2);
        uint256 rewardAmount = balanceAfter;
        emit log_named_uint("[self-repay] USDC redirected", rewardAmount);

        assertEqApprThreeWei(rewardAmount, USDC_10K);
    }

    function testDisableSelfRepayLoan() public {
        // epoch 1
        uint256 tokenId = _createLock(user, TOKEN_1, MAXTIME);
        _addReward(admin, mockUSDC, USDC_10K); // adds reward at the start of next epoch

        skipToNextEpoch(1);

        emit log_named_uint("[self-repay/disable] tokenId", tokenId);
        revenueReward.enableSelfRepayLoan(tokenId, user2);

        address[] memory tokens = new address[](1);
        tokens[0] = address(mockUSDC);
        revenueReward.getReward(tokenId, tokens);

        assertEqApprThreeWei(mockUSDC.balanceOf(user2), USDC_10K);

        // epoch2
        skipToNextEpoch(1);
        _addReward(admin, mockUSDC, USDC_10K); // adds reward at the start of next epoch

        skipToNextEpoch(1);

        vm.expectEmit(true, true, true, false, address(revenueReward));
        emit SelfRepayingLoanUpdate(tokenId, ZERO_ADDRESS, false);
        emit log("[self-repay/disable] disabling self-repay");
        revenueReward.disableSelfRepayLoan(tokenId);

        revenueReward.getReward(tokenId, tokens);

        emit log_named_uint("[self-repay/disable] USDC to owner", mockUSDC.balanceOf(user));
        assertEqApprThreeWei(mockUSDC.balanceOf(user), USDC_10K);
    }

    /* ========== TEST RECOVER TOKENS ========== */

    function testRecoverMultipleTokens() public {
        _addReward(admin, mockDAI, TOKEN_10K);
        _addReward(admin, mockUSDC, USDC_10K);

        // transfer without notify
        mintErc20Token(address(mockDAI), admin, 2 * TOKEN_10K);
        vm.prank(admin);
        mockDAI.transfer(address(revenueReward), 2 * TOKEN_10K);

        mintErc20Token(address(mockUSDC), admin, 4 * USDC_10K);
        vm.prank(admin);
        mockUSDC.transfer(address(revenueReward), 4 * USDC_10K);

        assertEq(mockUSDC.balanceOf(admin), 0);
        assertEq(mockDAI.balanceOf(admin), 0);

        vm.prank(admin);
        emit log("[revenue/recover] recovering stray tokens");
        revenueReward.recoverTokens();

        emit log_named_uint("[revenue/recover] USDC recovered", mockUSDC.balanceOf(admin));
        emit log_named_uint("[revenue/recover] DAI recovered", mockDAI.balanceOf(admin));
        assertEq(mockUSDC.balanceOf(admin), 4 * USDC_10K);
        assertEq(mockDAI.balanceOf(admin), 2 * TOKEN_10K);
    }

    function testRecoverNonDistributor() public {
        mintErc20Token(address(mockDAI), admin, 2 * TOKEN_10K);
        vm.prank(admin);
        mockDAI.transfer(address(revenueReward), 2 * TOKEN_10K);

        vm.prank(user);
        emit log("[revenue/recover] Expect revert: recover by non-distributor");
        vm.expectRevert(abi.encodeWithSelector(IRevenueReward.NotRewardDistributor.selector));
        revenueReward.recoverTokens();
    }

    /* ========== HELPER FUNCTIONS ========== */

    function _createPermanentLock(address _user, uint256 _amount, uint256 _duration)
        private
        returns (uint256 tokenId)
    {
        tokenId = _createLock(_user, _amount, _duration);
        vm.prank(_user);
        dustLock.lockPermanent(tokenId);
    }

    function _createLock(address _user, uint256 _amount, uint256 _duration) private returns (uint256 tokenId) {
        mintErc20Token(address(DUST), _user, _amount);

        vm.startPrank(_user);
        DUST.approve(address(dustLock), _amount);
        tokenId = dustLock.createLock(_amount, _duration);
        vm.stopPrank();
    }

    function _increaseAmount(address _user, uint256 _tokenId, uint256 _amount) private {
        mintErc20Token(address(DUST), _user, _amount);

        vm.startPrank(_user);
        DUST.approve(address(dustLock), _amount);
        dustLock.increaseAmount(_tokenId, _amount);
        vm.stopPrank();
    }

    function _addReward(address _user, IERC20 _token, uint256 _amount) private {
        mintErc20Token(address(_token), _user, _amount);

        vm.startPrank(_user);
        _token.approve(address(revenueReward), _amount);
        revenueReward.notifyRewardAmount(address(_token), _amount);
        vm.stopPrank();
    }
}
