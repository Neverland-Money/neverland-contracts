// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import "./BaseTest.sol";
import "forge-std/console2.sol";
import {console2} from "forge-std/console2.sol";

contract DustLockTests is BaseTest {

    /* ========== TEST MIN LOCK TIME ========== */

    function _setUp() internal override {
        // Initial time => 1 sec after the start of week1
        assertEq(block.timestamp, 1 weeks + 1);
        mintErc20Token(address(DUST), user, TOKEN_100K);
    }

    /* ========== TEST NFT ========== */

    function testTransferOfNft() public {
        DUST.approve(address(dustLock), TOKEN_1);
        uint256 tokenId = dustLock.createLock(TOKEN_1, MAXTIME);
        skipAndRoll(1);

        dustLock.transferFrom(address(user), address(user2), tokenId);

        assertEq(dustLock.balanceOf(address(user)), 0);
        assertEq(dustLock.ownerOf(tokenId), address(user2));
        assertEq(dustLock.balanceOf(address(user2)), 1);

        // flash protection
        assertEq(dustLock.balanceOfNFT(1), 0);
    }

    /* ========== TEST PERMANENT LOCK BALANCE ========== */

    /// invariant checks
    /// bound timestamp between 1600000000 and 100 years from then
    /// current optimism timestamp >= 1600000000
    function testBalanceOfNFTWithPermanentLocks(uint256 timestamp) public {
        vm.warp(1600000000);
        timestamp = bound(timestamp, 1600000000, 1600000000 + (52 weeks) * 100);

        DUST.approve(address(dustLock), TOKEN_1);
        uint256 tokenId = dustLock.createLock(TOKEN_1, MAXTIME);
        dustLock.lockPermanent(tokenId);
        vm.warp(timestamp);

        assertEq(dustLock.balanceOfNFT(tokenId), TOKEN_1);
    }

    function testBalanceOfNFTAtWithPermanentLocks(uint256 timestamp) public {
        vm.warp(1600000000);
        timestamp = bound(timestamp, 1600000000, 1600000000 + (52 weeks) * 100);

        DUST.approve(address(dustLock), TOKEN_1);
        uint256 tokenId = dustLock.createLock(TOKEN_1, MAXTIME);
        dustLock.lockPermanent(tokenId);
        vm.warp(timestamp);

        assertEq(dustLock.balanceOfNFTAt(tokenId, timestamp), TOKEN_1);
    }

    /* ========== TEST LOCK BALANCE DECAY ========== */

    function testBalanceOfNFTDecayFromStartToEndOfLockTime() public {
        DUST.approve(address(dustLock), TOKEN_1 * 2);

        // move block.timestamp
        skipAndRoll(1 weeks - 1);

        assertEq(block.timestamp, 2 weeks);
        uint256 lockTime = MAXTIME / 2;
        uint256 tokenId = dustLock.createLock(TOKEN_1, lockTime);

        assertApproxEqAbs(
            dustLock.balanceOfNFTAt(tokenId, block.timestamp),
            TOKEN_1 / 2,
            1e16 // tolerable difference up to 0.01
        );

        // move block.timestamp
        skipAndRoll(12 weeks);

        // Calculate expected balance correctly:
        // 1. Time elapsed: 12 weeks
        // 2. Remaining lock duration: lockTime - 12 weeks
        // 3. MAXTIME is the denominator for decay calculations
        uint256 expectedBalance = TOKEN_1 * (lockTime - 12 weeks) / MAXTIME;

        assertApproxEqAbs(
            dustLock.balanceOfNFTAt(tokenId, block.timestamp),
            expectedBalance,
            1e16
        );

    }

    function testBalanceOfTotalNftSupply() public {
        // arrange
        DUST.approve(address(dustLock), TOKEN_1 * 6);

        uint256[] memory tokens = new uint256[](6);

        // act
        // epoch 0
        uint256 timestamp0 = block.timestamp;

        tokens[0] = dustLock.createLock(TOKEN_1, MAXTIME / 3);
        tokens[1] = dustLock.createLock(TOKEN_1, MAXTIME / 2);

        uint256 balanceOfAllNftAt0 = _getBalanceOfAllNftsAt(tokens, timestamp0);
        uint256 totalSupplyAt0 = dustLock.totalSupply();

        // epoch 2
        skipAndRoll(2 weeks);
        uint256 timestamp2 = block.timestamp;

        tokens[2] = dustLock.createLock(TOKEN_1, MAXTIME / 8);
        tokens[3] = dustLock.createLock(TOKEN_1, MAXTIME);

        uint256 balanceOfAllNftAt2 = _getBalanceOfAllNftsAt(tokens, timestamp2);
        uint256 totalSupplyAt2 = dustLock.totalSupply();

        // epoch 7
        skipAndRoll(5 weeks);
        uint256 timestamp7 = block.timestamp;

        tokens[4] = dustLock.createLock(TOKEN_1, MAXTIME / 4);

        uint256 balanceOfAllNftAt7 = _getBalanceOfAllNftsAt(tokens, timestamp7);
        uint256 totalSupplyAt7 = dustLock.totalSupply();

        // assert
        assertEq(balanceOfAllNftAt0, _getBalanceOfAllNftsAt(tokens, timestamp0));
        assertEq(totalSupplyAt0, dustLock.totalSupplyAt(timestamp0));

        assertEq(balanceOfAllNftAt2, _getBalanceOfAllNftsAt(tokens, timestamp2));
        assertEq(totalSupplyAt2, dustLock.totalSupplyAt(timestamp2));

        assertEq(balanceOfAllNftAt7, _getBalanceOfAllNftsAt(tokens, timestamp7));
        assertEq(totalSupplyAt7, dustLock.totalSupplyAt(timestamp7));

    }

    function _getBalanceOfAllNftsAt(uint256[] memory tokens, uint256 ts) internal view returns(uint256) {
        uint256 balanceOfAllNftAt = 0;
        for (uint256 i = 0; i < tokens.length; i++) {
            if(tokens[i] == 0) continue;
            balanceOfAllNftAt += dustLock.balanceOfNFTAt(tokens[i], ts);
        }
        return balanceOfAllNftAt;
    }


    /* ========== TEST MIN LOCK TIME ========== */

    function testCreateLockMinLockTimeStartOfWeek() public {
        // arrange
        uint256 startOfCurrentWeek = block.timestamp / WEEK * WEEK;
        assertEq(startOfCurrentWeek, 1 weeks);

        // act/assert
        (
            DustLock.LockedBalance memory lockedTokenId1,
            DustLock.LockedBalance memory lockedTokenId2
        ) = _createLocks(TOKEN_1, MINTIME + WEEK);
        assertEq(lockedTokenId1.end, startOfCurrentWeek + 5 weeks);
        assertEq(lockedTokenId2.end, startOfCurrentWeek + 5 weeks);

        vm.expectRevert(IDustLock.LockDurationTooSort.selector);
        dustLock.createLock(TOKEN_1, MINTIME);

        vm.expectRevert(IDustLock.LockDurationTooSort.selector);
        dustLock.createLockFor(TOKEN_1, MINTIME, user2);
    }

    function testCreateLockMinLockTimeEndOfWeek() public {
        // arrange
        skipAndRoll(1 weeks - 2);
        assertEq(block.timestamp, 2 weeks - 1); // 1 sec before the start of week2

        uint256 startOfCurrentWeek = block.timestamp / WEEK * WEEK;
        assertEq(startOfCurrentWeek, 1 weeks);

        // act/assert
        (
            DustLock.LockedBalance memory lockedTokenId1,
            DustLock.LockedBalance memory lockedTokenId2
        ) = _createLocks(TOKEN_1, MINTIME + WEEK);
        assertEq(lockedTokenId1.end, startOfCurrentWeek + 5 weeks);
        assertEq(lockedTokenId2.end, startOfCurrentWeek + 5 weeks);

        vm.expectRevert(IDustLock.LockDurationTooSort.selector);
        dustLock.createLock(TOKEN_1, MINTIME);

        vm.expectRevert(IDustLock.LockDurationTooSort.selector);
        dustLock.createLockFor(TOKEN_1, MINTIME, user2);
    }

    function testCreateLockMinLockTimeExactlyAtWeek() public {
        // arrange
        skipAndRoll(1 weeks - 1);
        assertEq(block.timestamp, 2 weeks); // week2

        uint256 startOfCurrentWeek = block.timestamp / WEEK * WEEK;
        assertEq(startOfCurrentWeek, 2 weeks);

        // act/assert
        (
            DustLock.LockedBalance memory lockedTokenId1,
            DustLock.LockedBalance memory lockedTokenId2
        ) = _createLocks(TOKEN_1, MINTIME);
        assertEq(lockedTokenId1.end, startOfCurrentWeek + 4 weeks);
        assertEq(lockedTokenId2.end, startOfCurrentWeek + 4 weeks);

        vm.expectRevert(IDustLock.LockDurationTooSort.selector);
        dustLock.createLock(TOKEN_1, MINTIME - 1);

        vm.expectRevert(IDustLock.LockDurationTooSort.selector);
        dustLock.createLockFor(TOKEN_1, MINTIME - 1, user2);
    }

    /* ========== TEST MAX LOCK TIME ========== */

    function testMaxLockTime() public {
        // arrange
        uint256 startOfCurrentWeek = block.timestamp / WEEK * WEEK;
        assertEq(startOfCurrentWeek, 1 weeks);

        // act/assert
        (
            DustLock.LockedBalance memory lockedTokenId1,
            DustLock.LockedBalance memory lockedTokenId2
        ) = _createLocks(TOKEN_1, MAXTIME);
        assertEq(lockedTokenId1.end, startOfCurrentWeek + 52 weeks);
        assertEq(lockedTokenId2.end, startOfCurrentWeek + 52 weeks);

        vm.expectRevert(IDustLock.LockDurationTooLong.selector);
        dustLock.createLock(TOKEN_1, MAXTIME + WEEK);

        vm.expectRevert(IDustLock.LockDurationTooLong.selector);
        dustLock.createLockFor(TOKEN_1, MAXTIME + WEEK, user2);
    }

    /* ========== EARLY UNLOCK ========== */

    function testWithdraw() public {
        DUST.approve(address(dustLock), TOKEN_1);
        uint256 lockDuration = 29 * WEEK;
        dustLock.createLock(TOKEN_1, lockDuration);
        uint256 preBalance = DUST.balanceOf(address(user));

        skipAndRoll(lockDuration);
        dustLock.withdraw(1);

        uint256 postBalance = DUST.balanceOf(address(user));
        assertEq(postBalance - preBalance, TOKEN_1);
        assertEq(dustLock.ownerOf(1), address(0));
        assertEq(dustLock.balanceOf(address(user)), 0);
        // assertEq(dustLock.ownerToNFTokenIdList(address(owner), 0), 0);

        // check voting checkpoint created on burn updating owner
        assertEq(dustLock.balanceOfNFT(1), 0);
    }

    function testEarlyWithdraw() public {
        // arrange
        mintErc20Token(address(DUST), user2, TOKEN_10K);

        vm.startPrank(user2);
        DUST.approve(address(dustLock), TOKEN_10K);
        uint256 tokenId = dustLock.createLock(TOKEN_10K, MAXTIME);
        vm.stopPrank();

        dustLock.setEarlyWithdrawTreasury(user3);
        dustLock.setEarlyWithdrawPenalty(3_000);

        skipAndRoll(MAXTIME / 2);

        // act
        vm.prank(user2);
        dustLock.earlyWithdraw(tokenId);

        // assert
        assertEq(dustLock.balanceOfNFT(tokenId), 0);

        uint256 expectedUserPenalty = 0.3 * 5_000 * 1e18;

        assertApproxEqAbs(
            DUST.balanceOf(address(user2)),
            TOKEN_10K - expectedUserPenalty,
            10 * 1e18, // up to 10 DUST diff allowed
            "wrong amount on user"
        );

        assertApproxEqAbs(
            DUST.balanceOf(address(dustLock.earlyWithdrawTreasury())),
            expectedUserPenalty,
            10 * 1e18, // up to 10 DUST diff allowed
            "wrong amount on treasury"
        );
    }


    /* ========== HELPER FUNCTIONS ========== */

    function _createLocks(uint256 amount, uint256 duration)
        internal
        returns (IDustLock.LockedBalance memory lockedTokenId1, IDustLock.LockedBalance memory lockedTokenId2)
    {
        DUST.approve(address(dustLock), amount * 2);

        uint256 tokenId1 = dustLock.createLock(amount, duration);
        lockedTokenId1 = dustLock.locked(tokenId1);

        uint256 tokenId2 = dustLock.createLock(amount, duration);
        lockedTokenId2 = dustLock.locked(tokenId2);
    }

}