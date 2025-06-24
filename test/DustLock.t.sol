// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import "./BaseTest.sol";
import {console2} from "forge-std/console2.sol";

contract VotingEscrowTest is BaseTest {

    /* ========== TEST MIN LOCK TIME ========== */

    function _setUp() public override view {
        // Initial time => 1 sec after the start of week1
        assertEq(block.timestamp, 1 weeks + 1);
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

        // balance at lock time
        skipAndRoll(1 weeks - 1);

        assertEq(block.timestamp, 2 weeks);
        uint256 tokenId = dustLock.createLock(TOKEN_1, MAXTIME);

        // move block.timestamp
        skipAndRoll(MAXTIME / 3);

        assertApproxEqAbs(
            dustLock.balanceOfNFTAt(tokenId, block.timestamp),
            TOKEN_1 * 2 / 3,
            1e16 // tolerable difference up to 0.01
        );

        // increase block.timestamp
        dustLock.increaseAmount(tokenId, TOKEN_1);

        assertApproxEqAbs(
            dustLock.balanceOfNFTAt(tokenId, block.timestamp),
            TOKEN_1 * 2 / 3 + TOKEN_1 * 2 / 3,
            1e16
        );

        // move block.timestamp
        skipAndRoll(MAXTIME / 3);

        assertApproxEqAbs(
            dustLock.balanceOfNFTAt(tokenId, block.timestamp),
            TOKEN_1 * 1 / 3 + TOKEN_1 * 1 / 3,
            1e16
        );
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

    function testEarlyUnlock() public {
        // arrange
        vm.prank(user2);
        DUST.approve(address(dustLock), TOKEN_1);

        vm.prank(user2);
        uint256 tokenId = dustLock.createLock(TOKEN_1, MAXTIME);

        dustLock.setEarlyWithdrawTreasury(user3);
        dustLock.setEarlyWithdrawPenalty(3_000);

        uint256 preBalanceUser2 = DUST.balanceOf(address(user2));
        uint256 preBalanceUser3 = DUST.balanceOf(address(user3));

        skipAndRoll(MAXTIME / 2);

        // act
        vm.prank(user2);
        dustLock.earlyWithdraw(tokenId);

        // assert
        assertEq(dustLock.balanceOfNFT(tokenId), 0);

        uint256 expectedReturns = (3_000 * (TOKEN_1 / 2) / TOKEN_1 / 10_000);
        assertApproxEqAbs(DUST.balanceOf(address(user2)), preBalanceUser2 + expectedReturns, 1e15);

        assertApproxEqAbs(
            DUST.balanceOf(address(dustLock.earlyWithdrawTreasury())),
            preBalanceUser3 + TOKEN_1 - expectedReturns,
            1e15
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