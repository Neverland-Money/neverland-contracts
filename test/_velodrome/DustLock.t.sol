// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "../BaseTest.sol";
import "../../src/tokens/DustLock.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {IERC721, IERC721Metadata} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import {IERC6372} from "@openzeppelin/contracts/interfaces/IERC6372.sol";

contract DustLockTest is BaseTest {
  event LockPermanent(address indexed _user, uint256 indexed _tokenId, uint256 amount, uint256 _ts);
  event UnlockPermanent(address indexed _user, uint256 indexed _tokenId, uint256 amount, uint256 _ts);
  event BatchMetadataUpdate(uint256 _fromTokenId, uint256 _toTokenId);
  event Merge(
    address indexed _sender,
    uint256 indexed _from,
    uint256 indexed _to,
    uint256 _amountFrom,
    uint256 _amountTo,
    uint256 _amountFinal,
    uint256 _locktime,
    uint256 _ts
  );
  event MetadataUpdate(uint256 _tokenId);
  event NotifyReward(address indexed from, address indexed reward, uint256 indexed epoch, uint256 amount);
  event Split(
    uint256 indexed _from,
    uint256 indexed _tokenId1,
    uint256 indexed _tokenId2,
    address _sender,
    uint256 _splitAmount1,
    uint256 _splitAmount2,
    uint256 _locktime,
    uint256 _ts
  );

  function testInitialState() public {
    assertEq(dustLock.team(), address(user));
  }

  function testSupportInterfaces() public {
    assertTrue(dustLock.supportsInterface(type(IERC165).interfaceId));
    assertTrue(dustLock.supportsInterface(type(IERC721).interfaceId));
    assertTrue(dustLock.supportsInterface(0x49064906)); // 4906 is events only, so uses a custom interface id
    assertTrue(dustLock.supportsInterface(type(IERC6372).interfaceId));
  }

  function testDepositFor() public {
    DUST.approve(address(dustLock), TOKEN_1);
    uint256 tokenId = dustLock.createLock(TOKEN_1, MAXTIME);

    IDustLock.LockedBalance memory preLocked = dustLock.locked(tokenId);
    DUST.approve(address(dustLock), TOKEN_1);
    vm.expectEmit(false, false, false, true, address(dustLock));
    emit MetadataUpdate(tokenId);
    dustLock.depositFor(tokenId, TOKEN_1);
    IDustLock.LockedBalance memory postLocked = dustLock.locked(tokenId);

    assertEq(uint256(uint128(postLocked.end)), uint256(uint128(preLocked.end)));
    assertEq(uint256(uint128(postLocked.amount)) - uint256(uint128(preLocked.amount)), TOKEN_1);
  }

  function testIncreaseAmount() public {
    DUST.approve(address(dustLock), TOKEN_1);
    uint256 tokenId = dustLock.createLock(TOKEN_1, MAXTIME);

    IDustLock.LockedBalance memory preLocked = dustLock.locked(tokenId);
    DUST.approve(address(dustLock), TOKEN_1);
    vm.expectEmit(false, false, false, true, address(dustLock));
    emit MetadataUpdate(tokenId);
    dustLock.increaseAmount(tokenId, TOKEN_1);
    IDustLock.LockedBalance memory postLocked = dustLock.locked(tokenId);

    assertEq(uint256(uint128(postLocked.end)), uint256(uint128(preLocked.end)));
    assertEq(uint256(uint128(postLocked.amount)) - uint256(uint128(preLocked.amount)), TOKEN_1);
  }

  function testIncreaseUnlockTime() public {
    DUST.approve(address(dustLock), TOKEN_1);
    uint256 tokenId = dustLock.createLock(TOKEN_1, 4 weeks);

    skip((1 weeks) / 2);

    IDustLock.LockedBalance memory preLocked = dustLock.locked(tokenId);
    vm.expectEmit(false, false, false, true, address(dustLock));
    emit MetadataUpdate(tokenId);
    dustLock.increaseUnlockTime(tokenId, MAXTIME);
    IDustLock.LockedBalance memory postLocked = dustLock.locked(tokenId);

    uint256 expectedLockTime = ((block.timestamp + MAXTIME) / WEEK) * WEEK;
    assertEq(uint256(uint128(postLocked.end)), expectedLockTime);
    assertEq(uint256(uint128(postLocked.amount)), uint256(uint128(preLocked.amount)));
  }

  function testCreateLockOutsideAllowedZones() public {
    DUST.approve(address(dustLock), 1e25);
    vm.expectRevert(IDustLock.LockDurationTooLong.selector);
    dustLock.createLock(1e21, MAXTIME + 1 weeks);
  }

  function testIncreaseAmountWithNormalLock() public {
    // timestamp: 604801
    DUST.approve(address(dustLock), TOKEN_1);
    uint256 tokenId = dustLock.createLock(TOKEN_1, MAXTIME);
    skipAndRoll(1);

    DUST.approve(address(dustLock), TOKEN_1);
    dustLock.increaseAmount(tokenId, TOKEN_1);

    // check locked balance state is updated correctly
    IDustLock.LockedBalance memory locked = dustLock.locked(tokenId);
    assertEq(convert(locked.amount), TOKEN_1 * 2);
    assertEq(locked.end, 126403200);
    assertEq(locked.isPermanent, false);

    // check user point updates correctly
    assertEq(dustLock.userPointEpoch(tokenId), 2);
    IDustLock.UserPoint memory userPoint = dustLock.userPointHistory(tokenId, 2);
    assertEq(convert(userPoint.bias), 1994520516124422418); // (TOKEN_1 * 2 / MAXTIME) * (126403200 - 604802)
    assertEq(convert(userPoint.slope), 15854895991); // TOKEN_1 * 2 / MAXTIME
    assertEq(userPoint.ts, 604802);
    assertEq(userPoint.blk, 2);
    assertEq(userPoint.permanent, 0);

    // check global point updates correctly
    assertEq(dustLock.epoch(), 2);
    IDustLock.GlobalPoint memory globalPoint = dustLock.pointHistory(2);
    assertEq(convert(globalPoint.bias), 1994520516124422418);
    assertEq(convert(globalPoint.slope), 15854895991);
    assertEq(globalPoint.ts, 604802);
    assertEq(globalPoint.blk, 2);
    assertEq(globalPoint.permanentLockBalance, 0);

    assertEq(dustLock.supply(), TOKEN_1 * 2);
    assertEq(dustLock.slopeChanges(126403200), -15854895991);
  }

  function testIncreaseAmountWithPermanentLock() public {
    DUST.approve(address(dustLock), TOKEN_1);
    uint256 tokenId = dustLock.createLock(TOKEN_1, MAXTIME);
    dustLock.lockPermanent(tokenId);
    skipAndRoll(1);

    DUST.approve(address(dustLock), TOKEN_1);
    dustLock.increaseAmount(tokenId, TOKEN_1);

    // check locked balance state is updated correctly
    IDustLock.LockedBalance memory locked = dustLock.locked(tokenId);
    assertEq(convert(locked.amount), TOKEN_1 * 2);
    assertEq(locked.end, 0);
    assertEq(locked.isPermanent, true);

    // check user point updates correctly
    assertEq(dustLock.userPointEpoch(tokenId), 2);
    IDustLock.UserPoint memory userPoint = dustLock.userPointHistory(tokenId, 2);
    assertEq(convert(userPoint.bias), 0);
    assertEq(convert(userPoint.slope), 0);
    assertEq(userPoint.ts, 604802);
    assertEq(userPoint.blk, 2);
    assertEq(userPoint.permanent, TOKEN_1 * 2);

    // check global point updates correctly
    assertEq(dustLock.epoch(), 2);
    IDustLock.GlobalPoint memory globalPoint = dustLock.pointHistory(2);
    assertEq(convert(globalPoint.bias), 0);
    assertEq(convert(globalPoint.slope), 0);
    assertEq(globalPoint.ts, 604802);
    assertEq(globalPoint.blk, 2);
    assertEq(globalPoint.permanentLockBalance, TOKEN_1 * 2);
    assertEq(dustLock.supply(), TOKEN_1 * 2);
  }

  function testCannotIncreaseUnlockTimeWithPermanentLock() public {
    DUST.approve(address(dustLock), TOKEN_1);
    uint256 tokenId = dustLock.createLock(TOKEN_1, MAXTIME);
    dustLock.lockPermanent(tokenId);
    skipAndRoll(1);

    vm.expectRevert(IDustLock.PermanentLock.selector);
    dustLock.increaseUnlockTime(tokenId, MAXTIME);
  }

  function testTransferFrom() public {
    DUST.approve(address(dustLock), TOKEN_1);
    uint256 tokenId = dustLock.createLock(TOKEN_1, MAXTIME);
    skipAndRoll(1);

    dustLock.transferFrom(address(user), address(user2), tokenId);

    assertEq(dustLock.balanceOf(address(user)), 0);
    // assertEq(escrow.userToNFTokenIdList(address(user), 0), 0);
    assertEq(dustLock.ownerOf(tokenId), address(user2));
    assertEq(dustLock.balanceOf(address(user2)), 1);
    // assertEq(escrow.userToNFTokenIdList(address(user2), 0), tokenId);

    // flash protection
    assertEq(dustLock.balanceOfNFT(1), 0);
  }

  function testBurnFromApproved() public {
    DUST.approve(address(dustLock), 1e25);
    uint256 tokenId = dustLock.createLock(1e21, MAXTIME);
    skipAndRoll(MAXTIME + 1);
    dustLock.approve(address(user2), tokenId);
    vm.prank(address(user2));
    // should not revert
    dustLock.withdraw(tokenId);
  }

  function testCannotWithdrawPermanentLock() public {
    DUST.approve(address(dustLock), TOKEN_1);
    uint256 tokenId = dustLock.createLock(TOKEN_1, MAXTIME);
    dustLock.lockPermanent(tokenId);
    skipAndRoll(1);

    vm.expectRevert(IDustLock.PermanentLock.selector);
    dustLock.withdraw(tokenId);
  }

  function testCannotWithdrawBeforeLockExpiry() public {
    DUST.approve(address(dustLock), TOKEN_1);
    uint256 lockDuration = 7 * 24 * 3600; // 1 week
    uint256 tokenId = dustLock.createLock(TOKEN_1, lockDuration);
    skipAndRoll(1);

    vm.expectRevert(IDustLock.LockNotExpired.selector);
    dustLock.withdraw(tokenId);
  }

  function testWithdraw() public {
    DUST.approve(address(dustLock), TOKEN_1);
    uint256 lockDuration = 7 * 24 * 3600; // 1 week
    dustLock.createLock(TOKEN_1, lockDuration);
    uint256 preBalance = DUST.balanceOf(address(user));

    skipAndRoll(lockDuration);
    dustLock.withdraw(1);

    uint256 postBalance = DUST.balanceOf(address(user));
    assertEq(postBalance - preBalance, TOKEN_1);
    assertEq(dustLock.ownerOf(1), address(0));
    assertEq(dustLock.balanceOf(address(user)), 0);
    // assertEq(escrow.userToNFTokenIdList(address(user), 0), 0);
  }

  function testConfirmSupportsInterfaceWorksWithAssertedInterfaces() public {
    // Check that it supports all the asserted interfaces.
    bytes4 ERC165_INTERFACE_ID = 0x01ffc9a7;
    bytes4 ERC721_INTERFACE_ID = 0x80ac58cd;

    assertTrue(dustLock.supportsInterface(ERC165_INTERFACE_ID));
    assertTrue(dustLock.supportsInterface(ERC721_INTERFACE_ID));
  }

  function testCheckSupportsInterfaceHandlesUnsupportedInterfacesCorrectly() public {
    bytes4 ERC721_FAKE = 0x780e9d61;
    assertFalse(dustLock.supportsInterface(ERC721_FAKE));
  }

  function testCannotMergeSameVeNFT() public {
    DUST.approve(address(dustLock), type(uint256).max);
    uint256 tokenId = dustLock.createLock(TOKEN_1, MAXTIME);

    vm.expectRevert(IDustLock.SameNFT.selector);
    dustLock.merge(tokenId, tokenId);
  }

  function testCannotMergeFromVeNFTWithNoApprovalOrOwnership() public {
    DUST.approve(address(dustLock), type(uint256).max);
    uint256 userTokenId = dustLock.createLock(TOKEN_1, MAXTIME);

    vm.startPrank(address(user2));
    DUST.approve(address(dustLock), type(uint256).max);
    uint256 user2TokenId = dustLock.createLock(TOKEN_1, MAXTIME);
    vm.stopPrank();

    vm.expectRevert(IDustLock.NotApprovedOrOwner.selector);
    dustLock.merge(user2TokenId, userTokenId);
  }

  function testCannotMergeToVeNFTWithNoApprovalOrOwnership() public {
    DUST.approve(address(dustLock), type(uint256).max);
    uint256 userTokenId = dustLock.createLock(TOKEN_1, MAXTIME);

    vm.startPrank(address(user2));
    DUST.approve(address(dustLock), type(uint256).max);
    uint256 user2TokenId = dustLock.createLock(TOKEN_1, MAXTIME);
    vm.stopPrank();

    vm.expectRevert(IDustLock.NotApprovedOrOwner.selector);
    dustLock.merge(userTokenId, user2TokenId);
  }

  function testMergeWithFromLockTimeGreaterThanToLockTime() public {
    // first veNFT max lock time (4yrs)
    DUST.approve(address(dustLock), type(uint256).max);
    uint256 tokenId = dustLock.createLock(TOKEN_1, MAXTIME);

    // second veNFT only 1 yr lock time
    DUST.approve(address(dustLock), type(uint256).max);
    uint256 tokenId2 = dustLock.createLock(TOKEN_1, 365 days);

    uint256 veloSupply = dustLock.supply();
    uint256 expectedLockTime = dustLock.locked(tokenId).end;
    skip(1);

    vm.expectEmit(true, true, true, true, address(dustLock));
    emit Merge(address(user), tokenId, tokenId2, TOKEN_1, TOKEN_1, TOKEN_1 * 2, expectedLockTime, 604802);
    vm.expectEmit(false, false, false, true, address(dustLock));
    emit MetadataUpdate(tokenId2);
    dustLock.merge(tokenId, tokenId2);

    assertEq(dustLock.balanceOf(address(user)), 1);
    assertEq(dustLock.ownerOf(tokenId), address(0));
    assertEq(dustLock.ownerOf(tokenId2), address(user));
    assertEq(dustLock.supply(), veloSupply);

    IDustLock.UserPoint memory pt = dustLock.userPointHistory(tokenId, 2);
    assertEq(uint256(int256(pt.bias)), 0);
    assertEq(uint256(int256(pt.slope)), 0);
    assertEq(pt.ts, 604802);
    assertEq(pt.blk, 1);

    IDustLock.LockedBalance memory lockedFrom = dustLock.locked(tokenId);
    assertEq(lockedFrom.amount, 0);
    assertEq(lockedFrom.end, 0);

    IDustLock.UserPoint memory pt2 = dustLock.userPointHistory(tokenId2, 2);
    uint256 slope = (TOKEN_1 * 2) / MAXTIME;
    uint256 bias = slope * (expectedLockTime - block.timestamp);
    assertEq(uint256(int256(pt2.bias)), bias);
    assertEq(uint256(int256(pt2.slope)), slope);
    assertEq(pt2.ts, 604802);
    assertEq(pt2.blk, 1);

    IDustLock.LockedBalance memory lockedTo = dustLock.locked(tokenId2);
    assertEq(uint256(uint128(lockedTo.amount)), TOKEN_1 * 2);
    assertEq(uint256(uint128(lockedTo.end)), expectedLockTime);
  }

  function testMergeWithToLockTimeGreaterThanFromLockTime() public {
    // first veNFT max lock time (4yrs)
    DUST.approve(address(dustLock), type(uint256).max);
    uint256 tokenId = dustLock.createLock(TOKEN_1, MAXTIME);

    // second veNFT only 1 yr lock time
    DUST.approve(address(dustLock), type(uint256).max);
    uint256 tokenId2 = dustLock.createLock(TOKEN_1, 365 days);

    uint256 veloSupply = dustLock.supply();
    uint256 expectedLockTime = dustLock.locked(tokenId).end;

    skip(1);

    vm.expectEmit(true, true, true, true, address(dustLock));
    emit Merge(address(user), tokenId2, tokenId, TOKEN_1, TOKEN_1, TOKEN_1 * 2, expectedLockTime, 604802);
    vm.expectEmit(false, false, false, true, address(dustLock));
    emit MetadataUpdate(tokenId);
    dustLock.merge(tokenId2, tokenId);

    assertEq(dustLock.balanceOf(address(user)), 1);
    assertEq(dustLock.ownerOf(tokenId), address(user));
    assertEq(dustLock.ownerOf(tokenId2), address(0));
    assertEq(dustLock.supply(), veloSupply);

    IDustLock.UserPoint memory pt2 = dustLock.userPointHistory(tokenId2, 2);
    assertEq(uint256(int256(pt2.bias)), 0);
    assertEq(uint256(int256(pt2.slope)), 0);
    assertEq(pt2.ts, 604802);
    assertEq(pt2.blk, 1);

    IDustLock.LockedBalance memory lockedFrom = dustLock.locked(tokenId2);
    assertEq(lockedFrom.amount, 0);
    assertEq(lockedFrom.end, 0);

    IDustLock.UserPoint memory pt = dustLock.userPointHistory(tokenId, 2);
    uint256 slope = (TOKEN_1 * 2) / MAXTIME;
    uint256 bias = slope * (expectedLockTime - block.timestamp);
    assertEq(uint256(int256(pt.bias)), bias);
    assertEq(uint256(int256(pt.slope)), slope);
    assertEq(pt.ts, 604802);
    assertEq(pt.blk, 1);

    IDustLock.LockedBalance memory lockedTo = dustLock.locked(tokenId);
    assertEq(uint256(uint128(lockedTo.amount)), TOKEN_1 * 2);
    assertEq(uint256(uint128(lockedTo.end)), expectedLockTime);
  }

  function testMergeWithPermanentTo() public {
    DUST.approve(address(dustLock), type(uint256).max);
    uint256 tokenId = dustLock.createLock(TOKEN_1, MAXTIME);
    assertEq(dustLock.slopeChanges(126403200), -7927447995);
    uint256 tokenId2 = dustLock.createLock(TOKEN_1 * 2, MAXTIME);
    dustLock.lockPermanent(tokenId2);

    skipAndRoll(1);

    dustLock.merge(tokenId, tokenId2);

    assertEq(dustLock.balanceOf(address(user)), 1);
    assertEq(dustLock.ownerOf(tokenId), address(0));
    assertEq(dustLock.ownerOf(tokenId2), address(user));
    assertEq(dustLock.supply(), TOKEN_1 * 3);

    IDustLock.LockedBalance memory locked = dustLock.locked(tokenId);
    assertEq(locked.amount, 0);
    assertEq(locked.end, 0);
    assertEq(locked.isPermanent, false);

    assertEq(dustLock.userPointEpoch(tokenId), 2);
    IDustLock.UserPoint memory userPoint = dustLock.userPointHistory(tokenId, 2);
    assertEq(convert(userPoint.bias), 0);
    assertEq(convert(userPoint.slope), 0);
    assertEq(userPoint.ts, 604802);
    assertEq(userPoint.blk, 2);
    assertEq(userPoint.permanent, 0);

    locked = dustLock.locked(tokenId2);
    assertEq(uint256(uint128(locked.amount)), TOKEN_1 * 3);
    assertEq(uint256(uint128(locked.end)), 0);
    assertEq(locked.isPermanent, true);

    assertEq(dustLock.userPointEpoch(tokenId2), 2);
    userPoint = dustLock.userPointHistory(tokenId2, 2);
    assertEq(convert(userPoint.bias), 0);
    assertEq(convert(userPoint.slope), 0);
    assertEq(userPoint.ts, 604802);
    assertEq(userPoint.blk, 2);
    assertEq(userPoint.permanent, TOKEN_1 * 3);

    assertEq(dustLock.epoch(), 2);
    IDustLock.GlobalPoint memory globalPoint = dustLock.pointHistory(2);
    assertEq(convert(globalPoint.bias), 0);
    assertEq(convert(globalPoint.slope), 0);
    assertEq(globalPoint.ts, 604802);
    assertEq(globalPoint.blk, 2);
    assertEq(globalPoint.permanentLockBalance, TOKEN_1 * 3);

    assertEq(dustLock.slopeChanges(126403200), 0);
    assertEq(dustLock.permanentLockBalance(), TOKEN_1 * 3);
  }

  function testCannotMergeWithPermanantFrom() public {
    DUST.approve(address(dustLock), type(uint256).max);
    uint256 tokenId = dustLock.createLock(TOKEN_1, MAXTIME);
    dustLock.lockPermanent(tokenId);

    DUST.approve(address(dustLock), type(uint256).max);
    uint256 tokenId2 = dustLock.createLock(TOKEN_1, MAXTIME);

    vm.expectRevert(IDustLock.PermanentLock.selector);
    dustLock.merge(tokenId, tokenId2);
  }

  function testMergeWithExpiredFromVeNFT() public {
    // first veNFT max lock time (4yrs)
    DUST.approve(address(dustLock), type(uint256).max);
    uint256 tokenId = dustLock.createLock(TOKEN_1, MAXTIME);

    // second veNFT only 1 week lock time
    DUST.approve(address(dustLock), type(uint256).max);
    uint256 tokenId2 = dustLock.createLock(TOKEN_1, 1 weeks);

    uint256 expectedLockTime = dustLock.locked(tokenId).end;

    // let first veNFT expire
    skip(4 weeks);

    uint256 lock = dustLock.locked(tokenId2).end;
    assertLt(lock, block.timestamp); // check expired

    vm.expectEmit(true, true, true, true, address(dustLock));
    emit Merge(address(user), tokenId2, tokenId, TOKEN_1, TOKEN_1, TOKEN_1 * 2, expectedLockTime, 3024001);
    vm.expectEmit(false, false, false, true, address(dustLock));
    emit MetadataUpdate(tokenId);
    dustLock.merge(tokenId2, tokenId);

    assertEq(dustLock.balanceOf(address(user)), 1);
    assertEq(dustLock.ownerOf(tokenId), address(user));
    assertEq(dustLock.ownerOf(tokenId2), address(0));

    IDustLock.UserPoint memory pt2 = dustLock.userPointHistory(tokenId2, 2);
    assertEq(uint256(int256(pt2.bias)), 0);
    assertEq(uint256(int256(pt2.slope)), 0);
    assertEq(pt2.ts, 3024001);
    assertEq(pt2.blk, 1);

    IDustLock.LockedBalance memory lockedFrom = dustLock.locked(tokenId2);
    assertEq(lockedFrom.amount, 0);
    assertEq(lockedFrom.end, 0);

    IDustLock.UserPoint memory pt = dustLock.userPointHistory(tokenId, 2);
    uint256 slope = (TOKEN_1 * 2) / MAXTIME;
    uint256 bias = slope * (expectedLockTime - block.timestamp);
    assertEq(uint256(int256(pt.bias)), bias);
    assertEq(uint256(int256(pt.slope)), slope);
    assertEq(pt.ts, 3024001);
    assertEq(pt.blk, 1);

    IDustLock.LockedBalance memory lockedTo = dustLock.locked(tokenId);
    assertEq(uint256(uint128(lockedTo.amount)), TOKEN_1 * 2);
    assertEq(uint256(uint128(lockedTo.end)), expectedLockTime);
  }

  function testCannotMergeWithExpiredToVeNFT() public {
    // first veNFT max lock time (4yrs)
    DUST.approve(address(dustLock), type(uint256).max);
    uint256 tokenId = dustLock.createLock(TOKEN_1, MAXTIME);

    // second veNFT only 1 week lock time
    DUST.approve(address(dustLock), type(uint256).max);
    uint256 tokenId2 = dustLock.createLock(TOKEN_1, 1 weeks);

    // let second veNFT expire
    skip(4 weeks);

    vm.expectRevert(IDustLock.LockExpired.selector);
    dustLock.merge(tokenId, tokenId2);
  }

  function testCannotSplitIfNoOwnerAfterSplit() public {
    dustLock.toggleSplit(address(0), true);
    DUST.approve(address(dustLock), type(uint256).max);
    uint256 tokenId = dustLock.createLock(TOKEN_1, MAXTIME);
    dustLock.split(tokenId, TOKEN_1 / 2);
    vm.expectRevert(IDustLock.SplitNoOwner.selector);
    dustLock.split(tokenId, TOKEN_1 / 4);
  }

  function testCannotSplitIfNoOwnerAfterWithdraw() public {
    DUST.approve(address(dustLock), type(uint256).max);
    uint256 tokenId = dustLock.createLock(TOKEN_1, MAXTIME);
    skipAndRoll(MAXTIME + 1);
    dustLock.withdraw(tokenId);
    vm.expectRevert(IDustLock.SplitNoOwner.selector);
    dustLock.split(tokenId, TOKEN_1 / 2);
  }

  function testCannotSplitIfNoOwnerAfterMerge() public {
    DUST.approve(address(dustLock), type(uint256).max);
    uint256 tokenId = dustLock.createLock(TOKEN_1, MAXTIME);
    uint256 tokenId2 = dustLock.createLock(TOKEN_1, MAXTIME);
    dustLock.merge(tokenId, tokenId2);
    vm.expectRevert(IDustLock.SplitNoOwner.selector);
    dustLock.split(tokenId, TOKEN_1 / 4);
  }

  function testCannotSplitOverflow() public {
    dustLock.toggleSplit(address(0), true);

    DUST.approve(address(dustLock), type(uint256).max);
    dustLock.createLock(TOKEN_1, MAXTIME);

    vm.startPrank(address(user2));
    DUST.approve(address(dustLock), type(uint256).max);
    uint256 tokenId2 = dustLock.createLock(1e6, MAXTIME);
    // Creates the create overflow amount
    uint256 escrowBalance = DUST.balanceOf(address(dustLock));
    uint256 overflowAmount = uint256(int256(int128(-(int256(escrowBalance)))));
    assertGt(overflowAmount, uint256(uint128(type(int128).max)));

    vm.expectRevert(SafeCastLibrary.SafeCastOverflow.selector);
    dustLock.split(tokenId2, overflowAmount);
  }

  function testCannotToggleSplitForAllIfNotTeam() public {
    vm.prank(address(user2));
    vm.expectRevert(IDustLock.NotTeam.selector);
    dustLock.toggleSplit(address(0), true);
  }

  function testToggleSplitForAll() public {
    assertFalse(dustLock.canSplit(address(0)));

    dustLock.toggleSplit(address(0), true);
    assertTrue(dustLock.canSplit(address(0)));

    dustLock.toggleSplit(address(0), false);
    assertFalse(dustLock.canSplit(address(0)));

    dustLock.toggleSplit(address(0), true);
    assertTrue(dustLock.canSplit(address(0)));
  }

  function testCannotToggleSplitIfNotTeam() public {
    vm.prank(address(user2));
    vm.expectRevert(IDustLock.NotTeam.selector);
    dustLock.toggleSplit(address(user), true);
  }

  function testToggleSplit() public {
    assertFalse(dustLock.canSplit(address(user)));

    dustLock.toggleSplit(address(user), true);
    assertTrue(dustLock.canSplit(address(user)));

    dustLock.toggleSplit(address(user), false);
    assertFalse(dustLock.canSplit(address(user)));

    dustLock.toggleSplit(address(user), true);
    assertTrue(dustLock.canSplit(address(user)));
  }

  function testCannotSplitWithZeroAmount() public {
    dustLock.toggleSplit(address(0), true);
    DUST.approve(address(dustLock), type(uint256).max);
    uint256 userTokenId = dustLock.createLock(TOKEN_1, MAXTIME);

    vm.expectRevert(IDustLock.ZeroAmount.selector);
    dustLock.split(userTokenId, 0);
  }

  function testCannotSplitVeNFTWithNoApprovalOrOwnership() public {
    dustLock.toggleSplit(address(0), true);
    DUST.approve(address(dustLock), type(uint256).max);
    uint256 userTokenId = dustLock.createLock(TOKEN_1, MAXTIME);

    vm.expectRevert(IDustLock.NotApprovedOrOwner.selector);
    vm.prank(address(user2));
    dustLock.split(userTokenId, TOKEN_1 / 2);
  }

  function testCannotSplitWithExpiredVeNFT() public {
    dustLock.toggleSplit(address(0), true);
    // create veNFT with one week locktime
    DUST.approve(address(dustLock), type(uint256).max);
    uint256 tokenId = dustLock.createLock(TOKEN_1, 1 weeks);

    // let second veNFT expire
    skip(1 weeks + 1);

    vm.expectRevert(IDustLock.LockExpired.selector);
    dustLock.split(tokenId, TOKEN_1 / 2);
  }

  function testCannotSplitWithAmountTooBig() public {
    dustLock.toggleSplit(address(0), true);
    DUST.approve(address(dustLock), type(uint256).max);
    uint256 tokenId = dustLock.createLock(TOKEN_1, MAXTIME);

    vm.expectRevert(IDustLock.AmountTooBig.selector);
    dustLock.split(tokenId, TOKEN_1);
  }

  function testCannotSplitIfNotPermissioned() public {
    DUST.approve(address(dustLock), type(uint256).max);
    dustLock.createLock(TOKEN_1, MAXTIME);

    vm.expectRevert(IDustLock.SplitNotAllowed.selector);
    dustLock.split(1, TOKEN_1 / 4);
  }

  function testSplitWhenToggleSplitOnReceivedNFT() public {
    skip(1 weeks / 2);

    dustLock.toggleSplit(address(user), true);

    vm.startPrank(address(user2));
    DUST.approve(address(dustLock), type(uint256).max);
    uint256 tokenId = dustLock.createLock(TOKEN_1, MAXTIME);
    dustLock.transferFrom(address(user2), address(user), tokenId);
    vm.stopPrank();

    skipAndRoll(1);
    dustLock.split(tokenId, TOKEN_1 / 4);
  }

  function testSplitWhenToggleSplitByApproved() public {
    skip(1 weeks / 2);

    dustLock.toggleSplit(address(user), true);

    DUST.approve(address(dustLock), type(uint256).max);
    uint256 tokenId = dustLock.createLock(TOKEN_1, MAXTIME);
    dustLock.approve(address(user2), tokenId);
    skipAndRoll(1);

    vm.prank(address(user2));
    dustLock.split(tokenId, TOKEN_1 / 4);
  }

  function testSplitWhenToggleSplitDoesNotTransfer() public {
    skip(1 weeks / 2);

    dustLock.toggleSplit(address(user), true);

    DUST.approve(address(dustLock), type(uint256).max);
    uint256 tokenId = dustLock.createLock(TOKEN_1, MAXTIME);
    dustLock.transferFrom(address(user), address(user2), tokenId);

    skipAndRoll(1);
    vm.expectRevert(IDustLock.SplitNotAllowed.selector);
    vm.prank(address(user2));
    dustLock.split(tokenId, TOKEN_1 / 4);
  }

  function testSplitOwnershipFromuser() public {
    skip(1 weeks / 2);

    dustLock.toggleSplit(address(user), true);
    DUST.approve(address(dustLock), type(uint256).max);
    dustLock.createLock(TOKEN_1, MAXTIME);

    vm.expectEmit(true, true, true, true, address(dustLock));
    emit Split(1, 2, 3, address(user), (TOKEN_1 * 3) / 4, TOKEN_1 / 4, 127008000, 907201);
    (uint256 splitTokenId1, uint256 splitTokenId2) = dustLock.split(1, TOKEN_1 / 4);
    assertEq(dustLock.ownerOf(splitTokenId1), address(user));
    assertEq(dustLock.ownerOf(splitTokenId2), address(user));
    assertEq(dustLock.ownerOf(1), address(0));
  }

  function testSplitOwnershipFromApproved() public {
    skip(1 weeks / 2);

    dustLock.toggleSplit(address(user), true);
    DUST.approve(address(dustLock), type(uint256).max);
    dustLock.createLock(TOKEN_1, MAXTIME);
    dustLock.approve(address(user2), 1);

    vm.prank(address(user2));
    vm.expectEmit(true, true, true, true, address(dustLock));
    emit Split(1, 2, 3, address(user2), (TOKEN_1 * 3) / 4, TOKEN_1 / 4, 127008000, 907201);
    (uint256 splitTokenId1, uint256 splitTokenId2) = dustLock.split(1, TOKEN_1 / 4);
    assertEq(dustLock.ownerOf(splitTokenId1), address(user));
    assertEq(dustLock.ownerOf(splitTokenId2), address(user));
    assertEq(dustLock.ownerOf(1), address(0));
  }

  function testSplitWithPermanentLock() public {
    skip(1 weeks / 2); // timestamp: 907201
    dustLock.toggleSplit(address(0), true);

    DUST.approve(address(dustLock), type(uint256).max);
    dustLock.createLock(TOKEN_1, MAXTIME); // 1
    dustLock.lockPermanent(1);
    skipAndRoll(1);

    dustLock.split(1, TOKEN_1 / 4); // creates ids 2 and 3

    // check id 1
    IDustLock.LockedBalance memory locked = dustLock.locked(1);
    assertEq(convert(locked.amount), 0);
    assertEq(locked.end, 0);
    assertEq(locked.isPermanent, false);

    assertEq(dustLock.userPointEpoch(1), 2);
    IDustLock.UserPoint memory userPoint = dustLock.userPointHistory(1, 2);
    assertEq(convert(userPoint.bias), 0);
    assertEq(convert(userPoint.slope), 0);
    assertEq(userPoint.ts, 907202);
    assertEq(userPoint.blk, 2);
    assertEq(userPoint.permanent, 0);

    // check id 2 (balance: TOKEN_1 * 3 / 4)
    locked = dustLock.locked(2);
    assertEq(convert(locked.amount), (TOKEN_1 * 3) / 4);
    assertEq(locked.end, 0);
    assertEq(locked.isPermanent, true);

    assertEq(dustLock.userPointEpoch(2), 1);
    userPoint = dustLock.userPointHistory(2, 1);
    assertEq(convert(userPoint.bias), 0);
    assertEq(convert(userPoint.slope), 0);
    assertEq(userPoint.ts, 907202);
    assertEq(userPoint.blk, 2);
    assertEq(userPoint.permanent, (TOKEN_1 * 3) / 4);
    assertEq(dustLock.balanceOfNFT(2), (TOKEN_1 * 3) / 4);

    locked = dustLock.locked(3);
    assertEq(convert(locked.amount), TOKEN_1 / 4);
    assertEq(locked.end, 0);
    assertEq(locked.isPermanent, true);

    // check id 3 (balance: TOKEN_1 / 4)
    assertEq(dustLock.userPointEpoch(3), 1);
    userPoint = dustLock.userPointHistory(3, 1);
    assertEq(convert(userPoint.bias), 0);
    assertEq(convert(userPoint.slope), 0);
    assertEq(userPoint.ts, 907202);
    assertEq(userPoint.blk, 2);
    assertEq(userPoint.permanent, TOKEN_1 / 4);
    assertEq(dustLock.balanceOfNFT(3), TOKEN_1 / 4);

    // check global point
    assertEq(dustLock.epoch(), 2);
    IDustLock.GlobalPoint memory globalPoint = dustLock.pointHistory(2);
    assertEq(convert(globalPoint.bias), 0);
    assertEq(convert(globalPoint.slope), 0);
    assertEq(globalPoint.ts, 907202);
    assertEq(globalPoint.blk, 2);
    assertEq(globalPoint.permanentLockBalance, TOKEN_1);

    assertEq(dustLock.permanentLockBalance(), TOKEN_1);
    assertEq(dustLock.totalSupply(), TOKEN_1);
  }

  function testSplitWhenToggleSplit() public {
    skip(1 weeks / 2);

    dustLock.toggleSplit(address(user), true);

    DUST.approve(address(dustLock), type(uint256).max);
    dustLock.createLock(TOKEN_1, MAXTIME); // 1

    // generate new nfts with same amounts / locktime
    dustLock.createLock((TOKEN_1 * 3) / 4, MAXTIME); // 2
    dustLock.createLock(TOKEN_1 / 4, MAXTIME); // 3
    uint256 expectedLockTime = dustLock.locked(1).end;
    uint256 veloSupply = dustLock.supply();

    vm.expectEmit(true, true, true, true, address(dustLock));
    emit Split(1, 4, 5, address(user), (TOKEN_1 * 3) / 4, TOKEN_1 / 4, 127008000, 907201);
    (uint256 splitTokenId1, uint256 splitTokenId2) = dustLock.split(1, TOKEN_1 / 4);
    assertEq(splitTokenId1, 4);
    assertEq(splitTokenId2, 5);
    assertEq(dustLock.supply(), veloSupply);

    // check new veNFTs have correct amount and locktime
    IDustLock.LockedBalance memory lockedOld = dustLock.locked(splitTokenId1);
    assertEq(uint256(uint128(lockedOld.amount)), (TOKEN_1 * 3) / 4);
    assertEq(lockedOld.end, expectedLockTime);
    assertEq(dustLock.ownerOf(splitTokenId1), address(user));

    IDustLock.LockedBalance memory lockedNew = dustLock.locked(splitTokenId2);
    assertEq(uint256(uint128(lockedNew.amount)), TOKEN_1 / 4);
    assertEq(lockedNew.end, expectedLockTime);
    assertEq(dustLock.ownerOf(splitTokenId2), address(user));

    // check modified veNFTs are equivalent to brand new veNFTs created with same amount and locktime
    assertEq(dustLock.balanceOfNFT(splitTokenId1), dustLock.balanceOfNFT(2));
    assertEq(dustLock.balanceOfNFT(splitTokenId2), dustLock.balanceOfNFT(3));

    // Check point history of veNFT that was split from to ensure zero-ed out balance
    IDustLock.LockedBalance memory locked = dustLock.locked(1);
    assertEq(locked.amount, 0);
    assertEq(locked.end, 0);
    uint256 lastEpochStored = dustLock.userPointEpoch(1);
    IDustLock.UserPoint memory point = dustLock.userPointHistory(1, lastEpochStored);
    assertEq(point.bias, 0);
    assertEq(point.slope, 0);
    assertEq(point.ts, 907201);
    assertEq(point.blk, 1);
    assertEq(dustLock.balanceOfNFT(1), 0);

    // compare point history of first split veNFT and 2
    lastEpochStored = dustLock.userPointEpoch(splitTokenId1);
    IDustLock.UserPoint memory origPoint = dustLock.userPointHistory(splitTokenId1, lastEpochStored);
    lastEpochStored = dustLock.userPointEpoch(2);
    IDustLock.UserPoint memory cmpPoint = dustLock.userPointHistory(2, lastEpochStored);
    assertEq(origPoint.bias, cmpPoint.bias);
    assertEq(origPoint.slope, cmpPoint.slope);
    assertEq(origPoint.ts, cmpPoint.ts);
    assertEq(origPoint.blk, cmpPoint.blk);

    // compare point history of second split veNFT and 3
    lastEpochStored = dustLock.userPointEpoch(splitTokenId2);
    IDustLock.UserPoint memory splitPoint = dustLock.userPointHistory(splitTokenId2, lastEpochStored);
    lastEpochStored = dustLock.userPointEpoch(3);
    cmpPoint = dustLock.userPointHistory(3, lastEpochStored);
    assertEq(splitPoint.bias, cmpPoint.bias);
    assertEq(splitPoint.slope, cmpPoint.slope);
    assertEq(splitPoint.ts, cmpPoint.ts);
    assertEq(splitPoint.blk, cmpPoint.blk);
  }

  function testSplitWhenSplitPublic() public {
    skip(1 weeks / 2);

    dustLock.toggleSplit(address(0), true);

    DUST.approve(address(dustLock), type(uint256).max);
    dustLock.createLock(TOKEN_1, MAXTIME); // 1

    // generate new nfts with same amounts / locktime
    dustLock.createLock((TOKEN_1 * 3) / 4, MAXTIME); // 2
    dustLock.createLock(TOKEN_1 / 4, MAXTIME); // 3
    uint256 expectedLockTime = dustLock.locked(1).end;
    uint256 veloSupply = dustLock.supply();

    vm.expectEmit(true, true, true, true, address(dustLock));
    emit Split(1, 4, 5, address(user), (TOKEN_1 * 3) / 4, TOKEN_1 / 4, 127008000, 907201);
    (uint256 splitTokenId1, uint256 splitTokenId2) = dustLock.split(1, TOKEN_1 / 4);
    assertEq(splitTokenId1, 4);
    assertEq(splitTokenId2, 5);
    assertEq(dustLock.supply(), veloSupply);

    // check new veNFTs have correct amount and locktime
    IDustLock.LockedBalance memory lockedOld = dustLock.locked(splitTokenId1);
    assertEq(uint256(uint128(lockedOld.amount)), (TOKEN_1 * 3) / 4);
    assertEq(lockedOld.end, expectedLockTime);
    assertEq(dustLock.ownerOf(splitTokenId1), address(user));

    IDustLock.LockedBalance memory lockedNew = dustLock.locked(splitTokenId2);
    assertEq(uint256(uint128(lockedNew.amount)), TOKEN_1 / 4);
    assertEq(lockedNew.end, expectedLockTime);
    assertEq(dustLock.ownerOf(splitTokenId2), address(user));

    // check modified veNFTs are equivalent to brand new veNFTs created with same amount and locktime
    assertEq(dustLock.balanceOfNFT(splitTokenId1), dustLock.balanceOfNFT(2));
    assertEq(dustLock.balanceOfNFT(splitTokenId2), dustLock.balanceOfNFT(3));

    // Check point history of veNFT that was split from to ensure zero-ed out balance
    IDustLock.LockedBalance memory locked = dustLock.locked(1);
    assertEq(locked.amount, 0);
    assertEq(locked.end, 0);
    uint256 lastEpochStored = dustLock.userPointEpoch(1);
    IDustLock.UserPoint memory point = dustLock.userPointHistory(1, lastEpochStored);
    assertEq(point.bias, 0);
    assertEq(point.slope, 0);
    assertEq(point.ts, 907201);
    assertEq(point.blk, 1);
    assertEq(dustLock.balanceOfNFT(1), 0);

    // compare point history of first split veNFT and 2
    lastEpochStored = dustLock.userPointEpoch(splitTokenId1);
    IDustLock.UserPoint memory origPoint = dustLock.userPointHistory(splitTokenId1, lastEpochStored);
    lastEpochStored = dustLock.userPointEpoch(2);
    IDustLock.UserPoint memory cmpPoint = dustLock.userPointHistory(2, lastEpochStored);
    assertEq(origPoint.bias, cmpPoint.bias);
    assertEq(origPoint.slope, cmpPoint.slope);
    assertEq(origPoint.ts, cmpPoint.ts);
    assertEq(origPoint.blk, cmpPoint.blk);

    // compare point history of second split veNFT and 3
    lastEpochStored = dustLock.userPointEpoch(splitTokenId2);
    IDustLock.UserPoint memory splitPoint = dustLock.userPointHistory(splitTokenId2, lastEpochStored);
    lastEpochStored = dustLock.userPointEpoch(3);
    cmpPoint = dustLock.userPointHistory(3, lastEpochStored);
    assertEq(splitPoint.bias, cmpPoint.bias);
    assertEq(splitPoint.slope, cmpPoint.slope);
    assertEq(splitPoint.ts, cmpPoint.ts);
    assertEq(splitPoint.blk, cmpPoint.blk);
  }

  function testCannotLockPermanentIfNotApprovedOrOwner() public {
    DUST.approve(address(dustLock), TOKEN_1);
    uint256 tokenId = dustLock.createLock(TOKEN_1, MAXTIME);

    skipAndRoll(1);

    vm.expectRevert(IDustLock.NotApprovedOrOwner.selector);
    vm.prank(address(user2));
    dustLock.lockPermanent(tokenId);
  }

  function testCannotLockPermanentWithExpiredLock() public {
    DUST.approve(address(dustLock), TOKEN_1);
    uint256 tokenId = dustLock.createLock(TOKEN_1, 4 weeks);

    skipAndRoll(4 weeks + 1);

    vm.expectRevert(IDustLock.LockExpired.selector);
    dustLock.lockPermanent(tokenId);
  }

  function testCannotLockPermamentWithPermanentLock() public {
    DUST.approve(address(dustLock), TOKEN_1);
    uint256 tokenId = dustLock.createLock(TOKEN_1, MAXTIME);
    dustLock.lockPermanent(tokenId);

    skipAndRoll(1);

    vm.expectRevert(IDustLock.PermanentLock.selector);
    dustLock.lockPermanent(tokenId);
  }

  function testLockPermanent() public {
    // timestamp: 604801
    DUST.approve(address(dustLock), TOKEN_1);
    uint256 tokenId = dustLock.createLock(TOKEN_1, MAXTIME);
    assertEq(dustLock.locked(tokenId).end, 126403200);
    assertEq(dustLock.slopeChanges(0), 0);
    assertEq(dustLock.slopeChanges(126403200), -7927447995); // slope is negative after lock creation

    skipAndRoll(1);

    vm.expectEmit(true, true, false, true, address(dustLock));
    emit LockPermanent(address(user), tokenId, TOKEN_1, 604802);
    dustLock.lockPermanent(tokenId);

    // check locked balance state is updated correctly
    IDustLock.LockedBalance memory locked = dustLock.locked(tokenId);
    assertEq(convert(locked.amount), TOKEN_1);
    assertEq(locked.end, 0);
    assertEq(locked.isPermanent, true);

    // check user point updates correctly
    assertEq(dustLock.userPointEpoch(tokenId), 2);
    IDustLock.UserPoint memory userPoint = dustLock.userPointHistory(tokenId, 2);
    assertEq(convert(userPoint.bias), 0);
    assertEq(convert(userPoint.slope), 0);
    assertEq(userPoint.ts, 604802);
    assertEq(userPoint.blk, 2);
    assertEq(userPoint.permanent, TOKEN_1);

    // check global point updates correctly
    assertEq(dustLock.epoch(), 2);
    IDustLock.GlobalPoint memory globalPoint = dustLock.pointHistory(2);
    assertEq(convert(globalPoint.bias), 0);
    assertEq(convert(globalPoint.slope), 0);
    assertEq(globalPoint.ts, 604802);
    assertEq(globalPoint.blk, 2);
    assertEq(globalPoint.permanentLockBalance, TOKEN_1);

    assertEq(dustLock.slopeChanges(0), 0);
    assertEq(dustLock.slopeChanges(126403200), 0); // no contribution to global slope
    assertEq(dustLock.permanentLockBalance(), TOKEN_1);
  }

  function testCannotUnlockPermanentIfNotApprovedOrOwner() public {
    DUST.approve(address(dustLock), TOKEN_1);
    uint256 tokenId = dustLock.createLock(TOKEN_1, MAXTIME);
    dustLock.lockPermanent(tokenId);
    skipAndRoll(1);

    vm.expectRevert(IDustLock.NotApprovedOrOwner.selector);
    vm.prank(address(user2));
    dustLock.unlockPermanent(tokenId);
  }

  function testCannotUnlockPermanentIfNotPermanentlyLocked() public {
    DUST.approve(address(dustLock), TOKEN_1);
    uint256 tokenId = dustLock.createLock(TOKEN_1, MAXTIME);
    skipAndRoll(1);

    vm.expectRevert(IDustLock.NotPermanentLock.selector);
    dustLock.unlockPermanent(tokenId);
  }

  function testUnlockPermanent() public {
    // timestamp: 604801
    DUST.approve(address(dustLock), TOKEN_1);
    uint256 tokenId = dustLock.createLock(TOKEN_1, MAXTIME);
    assertEq(dustLock.slopeChanges(126403200), -7927447995); // slope is negative after lock creation

    skipAndRoll(1);

    dustLock.lockPermanent(tokenId);
    assertEq(dustLock.slopeChanges(126403200), 0); // slope zero on permanent lock

    skipAndRoll(1);

    vm.expectEmit(true, true, false, true, address(dustLock));
    emit UnlockPermanent(address(user), tokenId, TOKEN_1, 604803);
    dustLock.unlockPermanent(tokenId);

    // check locked balance state is updated correctly
    IDustLock.LockedBalance memory locked = dustLock.locked(tokenId);
    assertEq(convert(locked.amount), TOKEN_1);
    assertEq(locked.end, 126403200);

    // check user point updates correctly
    assertEq(dustLock.userPointEpoch(tokenId), 3);
    IDustLock.UserPoint memory userPoint = dustLock.userPointHistory(tokenId, 3);
    assertEq(convert(userPoint.bias), 997260250071864015); // (TOKEN_1 / MAXTIME) * (126403200 - 604803)
    assertEq(convert(userPoint.slope), 7927447995); // TOKEN_1 / MAXTIME
    assertEq(userPoint.ts, 604803);
    assertEq(userPoint.blk, 3);
    assertEq(userPoint.permanent, 0);

    // check global point updates correctly
    assertEq(dustLock.epoch(), 3);
    IDustLock.GlobalPoint memory globalPoint = dustLock.pointHistory(3);
    assertEq(convert(globalPoint.bias), 997260250071864015);
    assertEq(convert(globalPoint.slope), 7927447995);
    assertEq(globalPoint.ts, 604803);
    assertEq(globalPoint.blk, 3);
    assertEq(globalPoint.permanentLockBalance, 0);

    assertEq(dustLock.slopeChanges(126403200), -7927447995); // slope restored
    assertEq(dustLock.permanentLockBalance(), 0);
  }

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

  function testTotalSupplyWithPermanentLocks(uint256 timestamp) public {
    vm.warp(1600000000);
    timestamp = bound(timestamp, 1600000001, 1600000000 + (52 weeks) * 100);

    DUST.approve(address(dustLock), TOKEN_1);
    uint256 tokenId = dustLock.createLock(TOKEN_1, MAXTIME);
    dustLock.lockPermanent(tokenId);
    vm.warp(timestamp);

    assertEq(dustLock.totalSupply(), TOKEN_1);
  }

  function testTotalSupplyAtWithPermanentLocks(uint256 timestamp) public {
    vm.warp(1600000000);
    timestamp = bound(timestamp, 1600000001, 1600000000 + (52 weeks) * 100);

    DUST.approve(address(dustLock), TOKEN_1);
    uint256 tokenId = dustLock.createLock(TOKEN_1, MAXTIME);
    dustLock.lockPermanent(tokenId);
    vm.warp(timestamp);
  }

  function testBalanceAndSupplyInvariantsWithPermanentLocks(uint256 timestamp) public {
    vm.warp(1600000000);
    timestamp = bound(timestamp, 1600000000, 1600000000 + (52 weeks) * 100);

    DUST.approve(address(dustLock), TOKEN_1);
    uint256 tokenId = dustLock.createLock(TOKEN_1, MAXTIME);
    DUST.approve(address(dustLock), TOKEN_1);
    uint256 tokenId2 = dustLock.createLock(TOKEN_1, MAXTIME);
    dustLock.lockPermanent(tokenId);
    vm.warp(timestamp);

    assertEq(dustLock.balanceOfNFT(tokenId) + dustLock.balanceOfNFT(tokenId2), dustLock.totalSupply());
  }

}
