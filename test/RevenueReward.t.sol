// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import "./BaseTest.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {EpochTimeLibrary} from "../src/libraries/EpochTimeLibrary.sol";
import {IRevenueReward} from "../src/interfaces/IRevenueReward.sol";
import "forge-std/console2.sol";

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
        _addReward(admin, mockUSDC, USDC_10K);
        // assert
        assertEq(mockUSDC.balanceOf(address(revenueReward)), USDC_10K);
    }

    function testNotifyRewardAmountFromNonRewardDistributor() public {
        mintErc20Token(address(mockUSDC), user1, USDC_10K);

        vm.startPrank(user1);
        mockUSDC.approve(address(revenueReward), USDC_10K);
        vm.expectRevert(abi.encodeWithSelector(IRevenueReward.NotRewardDistributor.selector));
        revenueReward.notifyRewardAmount(address(mockUSDC), USDC_10K);
        vm.stopPrank();
    }

    function testSettingNewRewardDistributorFromAnyUser() public {
        vm.expectRevert(abi.encodeWithSelector(IRevenueReward.NotRewardDistributor.selector));
        revenueReward.setRewardDistributor(user1);
    }

    function testSettingNewRewardDistributor() public {
        _addReward(admin, mockUSDC, USDC_10K);

        vm.prank(admin);
        revenueReward.setRewardDistributor(user1);

        _addReward(user1, mockUSDC, USDC_10K);
    }

    /* ========== TEST GET REWARD ========== */

    function testSingleUserSingleEpochClaim() public {
        // arrange
        assertEq(block.timestamp, 1 weeks + 1);
        uint256 tokenId = _createLock(user, TOKEN_1, MAXTIME);
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

        assertEq(rewardAmount, USDC_10K);
        assertEq(lastEarnTimeAfter, block.timestamp);
    }

    function testUserSingleEpochClaimAndReclaim() public {
        // arrange
        assertEq(block.timestamp, 1 weeks + 1);
        uint256 tokenId = _createLock(user, TOKEN_1, MAXTIME);
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

        assertEq(rewardAmount, USDC_10K);
        assertEq(lastEarnTimeAfter, block.timestamp);
    }

    function testSingleUserMultiEpochClaim() public {
        // epoch 1
        uint256 tokenId = _createLock(user, TOKEN_1, MAXTIME);
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

        assertEq(rewardAmount, 2 * USDC_10K);
        assertEq(lastEarnTimeAfter, block.timestamp);
    }

    function testUserClaimRewardsUntilTimestamp() public {
        // epoch 1
        assertEq(block.timestamp, 1 weeks + 1);
        uint256 tokenId = _createLock(user, TOKEN_1, MAXTIME);
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
        revenueReward.getRewardUntilTs(tokenId, tokens, 2 weeks + 1);
        // assert
        assertEq(mockUSDC.balanceOf(user), USDC_10K);
        assertEq(revenueReward.lastEarnTime(address(mockUSDC), tokenId), 2 weeks + 1);

        // act
        revenueReward.getRewardUntilTs(tokenId, tokens, 4 weeks + 1);
        // assert
        assertEq(mockUSDC.balanceOf(user), 2 * USDC_10K);
        assertEq(revenueReward.lastEarnTime(address(mockUSDC), tokenId), 4 weeks + 1);

        // act
        revenueReward.getRewardUntilTs(tokenId, tokens, 4 weeks + 1);
        // assert
        assertEq(mockUSDC.balanceOf(user), 2 * USDC_10K);
        assertEq(revenueReward.lastEarnTime(address(mockUSDC), tokenId), 4 weeks + 1);
    }

    function testMultipleUsersWithDifferentBalances() public {
        // arrange
        uint256 user1TokenId = _createLock(user1, TOKEN_1 * 2, MAXTIME);
        uint256 user2TokenId = _createLock(user2, TOKEN_1, MAXTIME);

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

        // Alice should receive approximately twice as much reward as Bob (within small margin for rounding)
        assertApproxEqRel(user1Reward, user2Reward * 2, 0.01e18, "Rewards not proportional to veNFT balances");

        // The sum of rewards should not exceed the total rewards
        assertLe(user1Reward + user2Reward, USDC_10K, "Total claimed exceeds available rewards");
    }

    function testSingleUserForMultipleUnclaimedPastEpochs() public {
        // epoch 1
        uint256 tokenId = _createLock(user, TOKEN_1, MAXTIME);
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

        assertEq(rewardAmount, 2 * USDC_10K);
        assertEq(lastEarnTimeAfter, block.timestamp);
    }

    function testMultipleForMultipleUnclaimedPastEpochs() public {
        // arrange
        uint256 user1TokenId = _createLock(user1, TOKEN_1 * 2, MAXTIME);
        uint256 user2TokenId = _createLock(user2, TOKEN_1, MAXTIME);

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

        // Alice should receive approximately twice as much reward as Bob (within small margin for rounding)
        assertApproxEqRel(user1Reward, user2Reward * 2, 0.01e18);

        // The sum of rewards should not exceed the total rewards
        assertLe(user1Reward + user2Reward, 2 * USDC_10K);
    }

    function testClaimingForSubsetOfTokens() public {
        uint256 tokenId = _createLock(user1, TOKEN_1, MAXTIME);

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
        assertEq(mockUSDC.balanceOf(user1), USDC_10K);
        assertEq(mockDAI.balanceOf(user1), daiBalanceBefore);
        assertGt(revenueReward.lastEarnTime(address(mockUSDC), tokenId), usdcLastEarnTimeBefore);
        assertEq(revenueReward.lastEarnTime(address(mockDAI), tokenId), daiLastEarnTimeBefore);
    }

    function testAttemptingToClaimTwice() public {
        uint256 tokenId = _createLock(user1, TOKEN_1, MAXTIME);
        _addReward(admin, mockUSDC, USDC_10K);

        skipToNextEpoch(1);

        // First claim
        vm.startPrank(user1);
        address[] memory tokens = new address[](1);
        tokens[0] = address(mockUSDC);
        revenueReward.getReward(tokenId, tokens);

        // Record state after first claim
        uint256 balanceAfterFirstClaim = mockUSDC.balanceOf(user1);

        // Second claim immediately after
        revenueReward.getReward(tokenId, tokens);
        vm.stopPrank();

        assertEq(mockUSDC.balanceOf(user1), balanceAfterFirstClaim);
    }

    /* ========== TEST DUST LOCK INTERACTIONS ========== */

    function testAutoClaimedRewardsForEarlyWithdrawnTokens() public {
        // arrange
        assertEq(block.timestamp, 1 weeks + 1);

        uint256 tokenId = _createLock(user, TOKEN_1, MAXTIME);
        _addReward(admin, mockUSDC, USDC_10K); // adds reward at the start of next epoch

        goToEpoch(2);

        // act
        dustLock.earlyWithdraw(tokenId);

        // assert
        assertEq(mockUSDC.balanceOf(user), USDC_10K);
        assertEq(revenueReward.lastEarnTime(address(mockUSDC), tokenId), block.timestamp);
    }

    function testAutoClaimedRewardsForWithdrawnTokens() public {
        // arrange
        assertEq(block.timestamp, 1 weeks + 1);

        uint256 tokenId = _createLock(user, TOKEN_1, MAXTIME);
        _addReward(admin, mockUSDC, USDC_10K); // adds reward at the start of next epoch

        skipAndRoll(MAXTIME);

        // act
        dustLock.withdraw(tokenId);

        // assert
        assertEq(mockUSDC.balanceOf(user), USDC_10K);
        assertEq(revenueReward.lastEarnTime(address(mockUSDC), tokenId), block.timestamp);
    }

    function testAutoClaimedRewardsForTransferredTokens() public {
        // arrange
        assertEq(block.timestamp, 1 weeks + 1);

        uint256 tokenId = _createLock(user, TOKEN_1, MAXTIME);
        _addReward(admin, mockUSDC, USDC_10K); // adds reward at the start of next epoch

        goToEpoch(2);

        // act / assert
        dustLock.transferFrom(user, user2, tokenId);

        address[] memory tokens = new address[](1);
        tokens[0] = address(mockUSDC);

        vm.prank(user2);
        revenueReward.getReward(tokenId, tokens);

        assertEqApprOneWei(mockUSDC.balanceOf(user), USDC_10K);
        assertEqApprOneWei(mockUSDC.balanceOf(user2), 0);
        assertEq(revenueReward.lastEarnTime(address(mockUSDC), tokenId), block.timestamp);

        // act / assert
        _addReward(admin, mockUSDC, 2 * USDC_10K);

        goToEpoch(3);

        vm.prank(user2);
        revenueReward.getReward(tokenId, tokens);

        // assert
        assertEqApprOneWei(mockUSDC.balanceOf(user), USDC_10K);
        assertEqApprOneWei(mockUSDC.balanceOf(user2), 2 * USDC_10K);
        assertEq(revenueReward.lastEarnTime(address(mockUSDC), tokenId), block.timestamp);
    }

    /* ========== TEST SELF REPAYING LOAN ========== */

    function testEnableSelfRepayLoanCantBeSetByNonTokenOwner() public {
        // arrange
        uint256 tokenId = _createLock(user, TOKEN_1, MAXTIME);
        _addReward(admin, mockUSDC, USDC_10K); // adds reward at the start of next epoch

        // act/assert
        vm.startPrank(user2);
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
        revenueReward.enableSelfRepayLoan(tokenId, user2);

        address[] memory tokens = new address[](1);
        tokens[0] = address(mockUSDC);
        revenueReward.getReward(tokenId, tokens);

        // assert
        assertEq(mockUSDC.balanceOf(user), 0);

        uint256 balanceAfter = mockUSDC.balanceOf(user2);
        uint256 rewardAmount = balanceAfter;

        assertEq(rewardAmount, USDC_10K);
    }

    function testDisableSelfRepayLoan() public {
        // epoch 1
        uint256 tokenId = _createLock(user, TOKEN_1, MAXTIME);
        _addReward(admin, mockUSDC, USDC_10K); // adds reward at the start of next epoch

        skipToNextEpoch(1);

        revenueReward.enableSelfRepayLoan(tokenId, user2);

        address[] memory tokens = new address[](1);
        tokens[0] = address(mockUSDC);
        revenueReward.getReward(tokenId, tokens);

        assertEq(mockUSDC.balanceOf(user2), USDC_10K, "user2");

        // epoch2
        skipToNextEpoch(1);
        _addReward(admin, mockUSDC, USDC_10K); // adds reward at the start of next epoch

        skipToNextEpoch(1);

        vm.expectEmit(true, true, true, false, address(revenueReward));
        emit SelfRepayingLoanUpdate(tokenId, ZERO_ADDRESS, false);
        revenueReward.disableSelfRepayLoan(tokenId);

        revenueReward.getReward(tokenId, tokens);

        assertEq(mockUSDC.balanceOf(user), USDC_10K, "user");
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
        revenueReward.recoverTokens();

        assertEq(mockUSDC.balanceOf(admin), 4 * USDC_10K);
        assertEq(mockDAI.balanceOf(admin), 2 * TOKEN_10K);
    }

    function testRecoverNonDistributor() public {
        mintErc20Token(address(mockDAI), admin, 2 * TOKEN_10K);
        vm.prank(admin);
        mockDAI.transfer(address(revenueReward), 2 * TOKEN_10K);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IRevenueReward.NotRewardDistributor.selector));
        revenueReward.recoverTokens();
    }

    /* ========== HELPER FUNCTIONS ========== */

    function _createLock(address _user, uint256 _amount, uint256 _duration) private returns (uint256 tokenId) {
        mintErc20Token(address(DUST), _user, _amount);

        vm.startPrank(_user);
        DUST.approve(address(dustLock), _amount);
        tokenId = dustLock.createLock(_amount, _duration);
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
