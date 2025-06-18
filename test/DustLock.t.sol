// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import "./BaseTest.sol";

contract VotingEscrowTest is BaseTest {

    /* ========== TEST MIN LOCK TIME ========== */

    function testCreateLockMinLockTimeStartOfWeek() public {
        // arrange
        DUST.approve(address(dustLock), TOKEN_1 * 2);

        assertEq(block.timestamp, 1 weeks + 1);  // 1 sec after the start of week1

        uint256 startOfCurrentWeek = block.timestamp / WEEK * WEEK;
        assertEq(startOfCurrentWeek, 1 weeks);

        // act/assert
        uint256 tokenId1 = dustLock.createLock(TOKEN_1, MINTIME + WEEK);
        IDustLock.LockedBalance memory lockedTokenId1 = dustLock.locked(tokenId1);
        assertEq(lockedTokenId1.end, startOfCurrentWeek + 5 weeks);

        uint256 tokenId2 = dustLock.createLockFor(TOKEN_1, MINTIME + WEEK, user2);
        IDustLock.LockedBalance memory lockedTokenId2 = dustLock.locked(tokenId2);
        assertEq(lockedTokenId2.end, startOfCurrentWeek + 5 weeks);

        vm.expectRevert(IDustLock.LockDurationTooSort.selector);
        dustLock.createLock(TOKEN_1, MINTIME);

        vm.expectRevert(IDustLock.LockDurationTooSort.selector);
        dustLock.createLockFor(TOKEN_1, MINTIME, user2);
    }

    function testCreateLockMinLockTimeEndOfWeek() public {
        // arrange
        DUST.approve(address(dustLock), TOKEN_1 * 2);

        assertEq(block.timestamp, 1 weeks + 1);
        skipAndRoll(1 weeks - 2);
        assertEq(block.timestamp, 2 weeks - 1); // 1 sec before the start of week2

        uint256 startOfCurrentWeek = block.timestamp / WEEK * WEEK;
        assertEq(startOfCurrentWeek, 1 weeks);

        // act/assert
        uint256 tokenId1 = dustLock.createLock(TOKEN_1, MINTIME + WEEK);
        IDustLock.LockedBalance memory lockedTokenId3 = dustLock.locked(tokenId1);
        assertEq(lockedTokenId3.end, startOfCurrentWeek + 5 weeks);

        uint256 tokenId2 = dustLock.createLockFor(TOKEN_1, MINTIME + WEEK, user2);
        IDustLock.LockedBalance memory lockedTokenId4 = dustLock.locked(tokenId2);
        assertEq(lockedTokenId4.end, startOfCurrentWeek + 5 weeks);

        vm.expectRevert(IDustLock.LockDurationTooSort.selector);
        dustLock.createLock(TOKEN_1, MINTIME);

        vm.expectRevert(IDustLock.LockDurationTooSort.selector);
        dustLock.createLockFor(TOKEN_1, MINTIME, user2);
    }

    function testCreateLockMinLockTimeExactlyAtWeek() public {
        // arrange
        DUST.approve(address(dustLock), TOKEN_1 * 2);

        assertEq(block.timestamp, 1 weeks + 1);
        skipAndRoll(1 weeks - 1);
        assertEq(block.timestamp, 2 weeks); // week2

        uint256 startOfCurrentWeek = block.timestamp / WEEK * WEEK;
        assertEq(startOfCurrentWeek, 2 weeks);

        // act/assert
        uint256 tokenId1 = dustLock.createLock(TOKEN_1, MINTIME);
        IDustLock.LockedBalance memory lockedTokenId3 = dustLock.locked(tokenId1);
        assertEq(lockedTokenId3.end, startOfCurrentWeek + 4 weeks);

        uint256 tokenId2 = dustLock.createLockFor(TOKEN_1, MINTIME , user2);
        IDustLock.LockedBalance memory lockedTokenId4 = dustLock.locked(tokenId2);
        assertEq(lockedTokenId4.end, startOfCurrentWeek + 4 weeks);

        vm.expectRevert(IDustLock.LockDurationTooSort.selector);
        dustLock.createLock(TOKEN_1, MINTIME - 1);

        vm.expectRevert(IDustLock.LockDurationTooSort.selector);
        dustLock.createLockFor(TOKEN_1, MINTIME - 1, user2);
    }

    /* ========== TEST MAX LOCK TIME ========== */

    function testMaxLockTime() public {}

    function testEarlyUnlock() public {}
}