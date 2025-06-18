// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import "./BaseTest.sol";

contract VotingEscrowTest is BaseTest {

    /* ========== TEST MIN LOCK TIME ========== */

    function _setUp() public override view {
        // Initial time => 1 sec after the start of week1
        assertEq(block.timestamp, 1 weeks + 1);
    }

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

    function testEarlyUnlock() public {}


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