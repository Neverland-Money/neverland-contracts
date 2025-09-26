// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

import {IDustLock} from "../../src/interfaces/IDustLock.sol";
import {IRevenueReward} from "../../src/interfaces/IRevenueReward.sol";
import {IERC4906} from "@openzeppelin/contracts/interfaces/IERC4906.sol";
import {Vm} from "forge-std/Vm.sol";

import {CommonChecksLibrary} from "../../src/libraries/CommonChecksLibrary.sol";

import {RevenueReward} from "../../src/rewards/RevenueReward.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../BaseTestLocal.sol";

contract MaliciousRevenueReward is RevenueReward {
    constructor(address forwarder) RevenueReward(forwarder) {}

    function notifyAfterTokenTransferred(uint256 tokenId, address from) public override onlyDustLock {
        dustLock.transferFrom(from, address(this), tokenId);
    }

    function notifyAfterTokenBurned(uint256 tokenId, address /* from */ ) public override onlyDustLock {
        dustLock.earlyWithdraw(tokenId);
    }
}

contract BadReceiver {
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return 0x0;
    }
}

contract DustLockTests is BaseTestLocal {
    // Local event declaration for expectEmit matching (ERC-4906)
    event BatchMetadataUpdate(uint256 _fromTokenId, uint256 _toTokenId);

    function _setUp() internal override {
        // Initial time => 1 sec after the start of week1
        assertEq(block.timestamp, 1 weeks + 1);
        mintErc20Token(address(DUST), user, TOKEN_100K);
    }

    /* ========== NFT ========== */

    function testTransferOfNft() public {
        DUST.approve(address(dustLock), TOKEN_1);
        uint256 tokenId = dustLock.createLock(TOKEN_1, MAXTIME);
        emit log_named_uint("[dustLock] created tokenId", tokenId);
        skipAndRoll(1);

        dustLock.transferFrom(address(user), address(user2), tokenId);
        emit log("[dustLock] transferFrom user -> user2");

        assertEq(dustLock.balanceOf(address(user)), 0);
        assertEq(dustLock.ownerOf(tokenId), address(user2));
        assertEq(dustLock.balanceOf(address(user2)), 1);

        // flash protection
        assertEq(dustLock.balanceOfNFT(1), 0);
    }

    function testTransferToAddressZeroReverts() public {
        // arrange
        DUST.approve(address(dustLock), TOKEN_1);
        uint256 tokenId = dustLock.createLock(TOKEN_1, MAXTIME);

        // act / assert
        emit log("[dustLock] Expect revert: transfer to zero address");
        vm.expectRevert(abi.encodeWithSelector(CommonChecksLibrary.AddressZero.selector));
        dustLock.transferFrom(user, address(0), tokenId);
    }

    function testTokenUri() public {
        DUST.approve(address(dustLock), TOKEN_1);
        uint256 tokenId = dustLock.createLock(TOKEN_1, MAXTIME);
        emit log_named_uint("[dustLock] created tokenId", tokenId);

        assertEq(dustLock.tokenURI(tokenId), "https://neverland.money/nfts/1");
    }

    function testBaseUriOnlySetByTeam() public {
        DUST.approve(address(dustLock), TOKEN_1);
        uint256 tokenId = dustLock.createLock(TOKEN_1, MAXTIME);

        string memory newBaseURI = "https://google.com/search?q=";

        vm.startPrank(admin);
        emit log("[dustLock] Expect revert: setBaseURI by non-team");
        vm.expectRevert(IDustLock.NotTeam.selector);
        dustLock.setBaseURI(newBaseURI);
        vm.stopPrank();

        dustLock.setBaseURI(newBaseURI);
        emit log_string("[dustLock] baseURI updated");

        assertEq(dustLock.tokenURI(tokenId), "https://google.com/search?q=1");
    }

    /* ========== PERMANENT LOCK BALANCE ========== */

    /// invariant checks
    /// bound timestamp between 1600000000 and 100 years from then
    /// current optimism timestamp >= 1600000000
    function testBalanceOfNFTWithPermanentLocks(uint256 timestamp) public {
        vm.warp(1600000000);
        timestamp = bound(timestamp, 1600000000, 1600000000 + (52 weeks) * 100);

        DUST.approve(address(dustLock), TOKEN_1);
        uint256 tokenId = dustLock.createLock(TOKEN_1, MAXTIME);
        dustLock.lockPermanent(tokenId);
        emit log_named_uint("[dustLock] locked permanent tokenId", tokenId);
        vm.warp(timestamp);

        assertEq(dustLock.balanceOfNFT(tokenId), TOKEN_1);
    }

    function testBalanceOfNFTAtWithPermanentLocks(uint256 timestamp) public {
        vm.warp(1600000000);
        timestamp = bound(timestamp, 1600000000, 1600000000 + (52 weeks) * 100);

        DUST.approve(address(dustLock), TOKEN_1);
        uint256 tokenId = dustLock.createLock(TOKEN_1, MAXTIME);
        dustLock.lockPermanent(tokenId);
        emit log_named_uint("[dustLock] locked permanent tokenId", tokenId);
        vm.warp(timestamp);

        assertEq(dustLock.balanceOfNFTAt(tokenId, timestamp), TOKEN_1);
    }

    /* ========== PERMANENT/UNLOCK/WITHDRAW EDGE CASES ========== */

    function testWithdrawOnPermanentReverts() public {
        DUST.approve(address(dustLock), TOKEN_1);
        uint256 id = dustLock.createLock(TOKEN_1, MAXTIME);
        dustLock.lockPermanent(id);
        vm.expectRevert(IDustLock.PermanentLock.selector);
        dustLock.withdraw(id);
    }

    function testIncreaseUnlockTimeOnPermanentReverts() public {
        DUST.approve(address(dustLock), TOKEN_1);
        uint256 id = dustLock.createLock(TOKEN_1, MAXTIME);
        dustLock.lockPermanent(id);
        vm.expectRevert(IDustLock.PermanentLock.selector);
        dustLock.increaseUnlockTime(id, 1 weeks);
    }

    function testUnlockPermanentRevertsOnNonPermanent() public {
        DUST.approve(address(dustLock), TOKEN_1);
        uint256 id = dustLock.createLock(TOKEN_1, MAXTIME);
        vm.expectRevert(IDustLock.NotPermanentLock.selector);
        dustLock.unlockPermanent(id);
    }

    function testUnlockPermanentByApprovedOperator() public {
        DUST.approve(address(dustLock), TOKEN_1);
        uint256 id = dustLock.createLock(TOKEN_1, MAXTIME);
        dustLock.lockPermanent(id);

        // Unapproved cannot unlock
        vm.startPrank(user2);
        vm.expectRevert(IDustLock.NotApprovedOrOwner.selector);
        dustLock.unlockPermanent(id);
        vm.stopPrank();

        // Approve and unlock as operator
        dustLock.approve(user2, id);
        vm.prank(user2);
        dustLock.unlockPermanent(id);
        assertFalse(dustLock.locked(id).isPermanent);
    }

    function testDepositForIntoPermanentByThirdParty() public {
        // lock permanent
        DUST.approve(address(dustLock), TOKEN_1);
        uint256 id = dustLock.createLock(TOKEN_1, MAXTIME);
        dustLock.lockPermanent(id);
        uint256 plbBefore = dustLock.permanentLockBalance();

        // third party deposits
        mintErc20Token(address(DUST), user2, TOKEN_1);
        vm.startPrank(user2);
        DUST.approve(address(dustLock), TOKEN_1);
        dustLock.depositFor(id, TOKEN_1);
        vm.stopPrank();

        IDustLock.LockedBalance memory lb1 = dustLock.locked(id);
        assertTrue(lb1.isPermanent);
        assertEq(lb1.end, 0);
        assertEq(uint256(lb1.amount), 2 * TOKEN_1);
        assertEq(dustLock.permanentLockBalance(), plbBefore + TOKEN_1);
    }

    /* ========== MERGE EDGE CASES ========== */

    function testMergeIntoPermanentKeepsPermanent() public {
        // destination permanent
        DUST.approve(address(dustLock), 3 * TOKEN_1);
        uint256 toId = dustLock.createLock(TOKEN_1, MAXTIME);
        dustLock.lockPermanent(toId);
        uint256 fromId = dustLock.createLock(2 * TOKEN_1, MAXTIME);
        uint256 plbBefore = dustLock.permanentLockBalance();

        dustLock.merge(fromId, toId);

        IDustLock.LockedBalance memory lb2 = dustLock.locked(toId);
        assertTrue(lb2.isPermanent);
        assertEq(lb2.end, 0);
        assertEq(uint256(lb2.amount), 3 * TOKEN_1);
        assertEq(dustLock.permanentLockBalance(), plbBefore + 2 * TOKEN_1);
    }

    function testMergePermanentSourceReverts() public {
        DUST.approve(address(dustLock), 3 * TOKEN_1);
        uint256 fromId = dustLock.createLock(TOKEN_1, MAXTIME);
        uint256 toId = dustLock.createLock(2 * TOKEN_1, MAXTIME);
        dustLock.lockPermanent(fromId);
        vm.expectRevert(IDustLock.PermanentLock.selector);
        dustLock.merge(fromId, toId);
    }

    function testMergePermanentToPermanentCombines() public {
        DUST.approve(address(dustLock), 3 * TOKEN_1);
        uint256 fromId = dustLock.createLock(TOKEN_1, MAXTIME);
        uint256 toId = dustLock.createLock(2 * TOKEN_1, MAXTIME);
        dustLock.lockPermanent(fromId);
        dustLock.lockPermanent(toId);
        uint256 plbBefore = dustLock.permanentLockBalance();

        dustLock.merge(fromId, toId);

        IDustLock.LockedBalance memory lb = dustLock.locked(toId);
        assertTrue(lb.isPermanent);
        assertEq(lb.end, 0);
        assertEq(uint256(lb.amount), 3 * TOKEN_1);
        // PLB should not change when both source and dest were already permanent
        assertEq(dustLock.permanentLockBalance(), plbBefore);
    }

    /* ========== ERC721 HYGIENE ========== */

    function testSupportsInterfaceMatrix() public view {
        // ERC165
        assertTrue(dustLock.supportsInterface(0x01ffc9a7));
        // ERC721
        assertTrue(dustLock.supportsInterface(0x80ac58cd));
        // ERC4906
        assertTrue(dustLock.supportsInterface(0x49064906));
        // ERC6372
        assertTrue(dustLock.supportsInterface(0xda287a1d));
        // ERC721Metadata
        assertTrue(dustLock.supportsInterface(0x5b5e139f));
        // IDustLock
        assertTrue(dustLock.supportsInterface(type(IDustLock).interfaceId));
        // Negative case
        assertFalse(dustLock.supportsInterface(0xffffffff));
    }

    function testApprovalsClearedOnTransfer() public {
        DUST.approve(address(dustLock), TOKEN_1);
        uint256 id = dustLock.createLock(TOKEN_1, MAXTIME);
        dustLock.approve(user2, id);
        dustLock.transferFrom(user, user3, id);
        assertEq(dustLock.getApproved(id), address(0));
        vm.startPrank(user2);
        vm.expectRevert(IDustLock.NotApprovedOrOwner.selector);
        dustLock.transferFrom(user3, user, id);
        vm.stopPrank();
    }

    function testSetApprovalForAllOperatorCanTransfer() public {
        DUST.approve(address(dustLock), TOKEN_1);
        uint256 id = dustLock.createLock(TOKEN_1, MAXTIME);
        dustLock.setApprovalForAll(user2, true);
        vm.prank(user2);
        dustLock.transferFrom(user, user3, id);
        assertEq(dustLock.ownerOf(id), user3);
    }

    function testSafeTransferToBadReceiverReverts() public {
        DUST.approve(address(dustLock), TOKEN_1);
        uint256 id = dustLock.createLock(TOKEN_1, MAXTIME);
        BadReceiver bad = new BadReceiver();
        vm.expectRevert(IDustLock.ERC721ReceiverRejectedTokens.selector);
        dustLock.safeTransferFrom(user, address(bad), id);
    }

    function testTokenURINonExistentReverts() public {
        vm.expectRevert(CommonChecksLibrary.InvalidTokenId.selector);
        dustLock.tokenURI(999999);
    }

    function testSetBaseURI_NoTokens_NoBatchMetadata() public {
        // tokenId == 0 on fresh deployment
        bytes32 batchSig = keccak256("BatchMetadataUpdate(uint256,uint256)");
        vm.recordLogs();
        dustLock.setBaseURI("https://example.com/");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        for (uint256 i = 0; i < entries.length; i++) {
            // first topic is the keccak of the event signature
            assertTrue(entries[i].topics.length == 0 || entries[i].topics[0] != batchSig);
        }
    }

    function testSetBaseURI_WithTokens_EmitsBatchMetadata() public {
        // Mint one token so tokenId > 0
        DUST.approve(address(dustLock), TOKEN_1);
        uint256 tokenId_ = dustLock.createLock(TOKEN_1, MAXTIME);
        assertEq(tokenId_, 1);

        // Expect 4906 batch metadata update on baseURI change
        vm.expectEmit(false, false, false, true);
        emit BatchMetadataUpdate(1, dustLock.tokenId());
        dustLock.setBaseURI("https://another.example/");
    }

    /* ========== SPLIT PERMISSION GLOBAL VS PER-USER ========== */

    function testSplitPermissionGlobalEnablesEvenIfPerUserFalse() public {
        // Create a valid, non-permanent, unexpired lock
        DUST.approve(address(dustLock), 2 * TOKEN_1);
        uint256 id = dustLock.createLock(2 * TOKEN_1, MAXTIME);
        // Ensure per-user is false by default; enable global
        dustLock.toggleSplit(address(0), true);
        // Should succeed
        dustLock.split(id, TOKEN_1);
    }

    function testSplitPermissionPerUserWorksWhenGlobalFalse() public {
        // Create a valid, non-permanent, unexpired lock
        DUST.approve(address(dustLock), 2 * TOKEN_1);
        uint256 id = dustLock.createLock(2 * TOKEN_1, MAXTIME);
        // Enable per-user, keep global false
        dustLock.toggleSplit(user, true);
        dustLock.toggleSplit(address(0), false);
        dustLock.split(id, TOKEN_1); // should succeed
    }

    /* ========== REVENUE REWARD WIRING ========== */

    function testSetRevenueRewardZeroDisables() public {
        // Set to zero address should be allowed and clear the hook
        dustLock.setRevenueReward(IRevenueReward(address(0)));
        assertEq(address(dustLock.revenueReward()), address(0));
    }

    function testSetRevenueRewardToEOAReverts() public {
        vm.expectRevert(IDustLock.InvalidRevenueRewardContract.selector);
        dustLock.setRevenueReward(IRevenueReward(user2));
    }

    /* ========== HAPPY PATH ========== */

    function testCreateLockPermanentOneShot() public {
        uint256 amount = TOKEN_10K;
        // fund user1 and create permanent lock in one tx
        mintErc20Token(address(DUST), user1, amount);
        vm.startPrank(user1);
        DUST.approve(address(dustLock), amount);
        uint256 tokenId = dustLock.createLockPermanent(amount, MAXTIME);
        vm.stopPrank();

        // validate
        IDustLock.LockedBalance memory lb = dustLock.locked(tokenId);
        assertTrue(lb.isPermanent, "should be permanent");
        assertEq(lb.end, 0, "end should be zero for permanent");
        assertEq(uint256(lb.amount), amount, "amount mismatch");
        assertEq(dustLock.ownerOf(tokenId), user1, "owner mismatch");
    }

    function testCreateLockPermanentForOneShot() public {
        uint256 amount = TOKEN_10K;
        // caller is user (address(this)); create a permanent lock for user2
        mintErc20Token(address(DUST), user, amount);
        DUST.approve(address(dustLock), amount);
        uint256 tokenId = dustLock.createLockPermanentFor(amount, MAXTIME, user2);

        // validate minted to user2 and permanent
        IDustLock.LockedBalance memory lb = dustLock.locked(tokenId);
        assertTrue(lb.isPermanent, "should be permanent");
        assertEq(lb.end, 0, "end should be zero for permanent");
        assertEq(uint256(lb.amount), amount, "amount mismatch");
        assertEq(dustLock.ownerOf(tokenId), user2, "owner mismatch");
    }

    function testCreateLockPermanentRevertsMirrorCreateLock() public {
        uint256 validAmount = dustLock.minLockAmount();

        // amount too small
        uint256 tooSmallAmount = dustLock.minLockAmount() - 1;
        mintErc20Token(address(DUST), user, tooSmallAmount);
        DUST.approve(address(dustLock), tooSmallAmount);
        vm.expectRevert(IDustLock.AmountTooSmall.selector);
        dustLock.createLockPermanent(tooSmallAmount, 5 weeks);

        // lock duration not in future (0 duration)
        mintErc20Token(address(DUST), user, validAmount);
        DUST.approve(address(dustLock), validAmount);
        vm.expectRevert(IDustLock.LockDurationNotInFuture.selector);
        dustLock.createLockPermanent(validAmount, 0);

        // lock duration too short (rounds down to 0 weeks)
        mintErc20Token(address(DUST), user, validAmount);
        DUST.approve(address(dustLock), validAmount);
        vm.expectRevert(IDustLock.LockDurationNotInFuture.selector);
        dustLock.createLockPermanent(validAmount, 1 days);

        // lock duration too short (exactly MINTIME - 1)
        mintErc20Token(address(DUST), user, validAmount);
        DUST.approve(address(dustLock), validAmount);
        vm.expectRevert(IDustLock.LockDurationTooShort.selector);
        dustLock.createLockPermanent(validAmount, MINTIME - 1);

        // lock duration too long
        mintErc20Token(address(DUST), user, validAmount);
        DUST.approve(address(dustLock), validAmount);
        vm.expectRevert(IDustLock.LockDurationTooLong.selector);
        dustLock.createLockPermanent(validAmount, MAXTIME + 1 weeks);

        // insufficient balance
        uint256 userBalance = DUST.balanceOf(user);
        DUST.transfer(address(0xdead), userBalance); // burn existing balance
        DUST.approve(address(dustLock), validAmount);
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        dustLock.createLockPermanent(validAmount, MAXTIME);

        // insufficient allowance
        mintErc20Token(address(DUST), user, validAmount);
        DUST.approve(address(dustLock), validAmount - 1);
        vm.expectRevert("ERC20: insufficient allowance");
        dustLock.createLockPermanent(validAmount, MAXTIME);
    }

    function testCreateLockPermanentEventsSequence() public {
        uint256 amount = dustLock.minLockAmount();
        mintErc20Token(address(DUST), user, amount);
        DUST.approve(address(dustLock), amount);

        vm.recordLogs();
        dustLock.createLockPermanent(amount, MAXTIME);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        bytes32 SIG_TRANSFER = keccak256("Transfer(address,address,uint256)");
        bytes32 SIG_DEPOSIT = keccak256("Deposit(address,uint256,uint8,uint256,uint256,uint256)");
        bytes32 SIG_LOCK_PERM = keccak256("LockPermanent(address,uint256,uint256,uint256)");
        bytes32 SIG_METADATA = keccak256("MetadataUpdate(uint256)");

        uint256 max = type(uint256).max;
        uint256 iTransfer = max;
        uint256 iDeposit = max;
        uint256 iLockPerm = max;
        uint256 iMetadata = max;
        uint256 cTransfer;
        uint256 cDeposit;
        uint256 cLockPerm;
        uint256 cMetadata;

        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].emitter != address(dustLock)) continue; // only DustLock events
            bytes32 topic0 = logs[i].topics[0];
            if (topic0 == SIG_TRANSFER && logs[i].topics.length == 4) {
                if (iTransfer == max) iTransfer = i;
                unchecked {
                    cTransfer++;
                }
            } else if (topic0 == SIG_DEPOSIT) {
                if (iDeposit == max) iDeposit = i;
                unchecked {
                    cDeposit++;
                }
            } else if (topic0 == SIG_LOCK_PERM) {
                if (iLockPerm == max) iLockPerm = i;
                unchecked {
                    cLockPerm++;
                }
            } else if (topic0 == SIG_METADATA) {
                if (iMetadata == max) iMetadata = i;
                unchecked {
                    cMetadata++;
                }
            }
        }

        assertEq(cTransfer, 1);
        assertEq(cDeposit, 1);
        assertEq(cLockPerm, 1);
        assertTrue(cMetadata >= 1);

        assertTrue(iTransfer < max && iDeposit < max && iLockPerm < max && iMetadata < max, "events present");
        assertLt(iTransfer, iDeposit, "Transfer before Deposit");
        assertLt(iDeposit, iLockPerm, "Deposit before LockPermanent");

        // Optional: details can be checked here if needed; order sanity is sufficient for this test
    }

    /* ========== LOCK BALANCE DECAY ========== */

    function testBalanceOfNFTDecayFromStartToEndOfLockTime() public {
        DUST.approve(address(dustLock), TOKEN_1 * 2);

        // move block.timestamp
        skipAndRoll(1 weeks - 1);

        assertEq(block.timestamp, 2 weeks);
        uint256 lockTime = MAXTIME / 2;
        uint256 tokenId = dustLock.createLock(TOKEN_1, lockTime);
        emit log_named_uint("[dustLock] created tokenId", tokenId);

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

        assertApproxEqAbs(dustLock.balanceOfNFTAt(tokenId, block.timestamp), expectedBalance, 1e16);
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
        emit log_named_uint("[dustLock] created tokenId#0", tokens[0]);
        emit log_named_uint("[dustLock] created tokenId#1", tokens[1]);

        uint256 balanceOfAllNftAt0 = _getBalanceOfAllNftsAt(tokens, timestamp0);
        uint256 totalSupplyAt0 = dustLock.totalSupply();

        // epoch 2
        skipAndRoll(2 weeks);
        uint256 timestamp2 = block.timestamp;

        tokens[2] = dustLock.createLock(TOKEN_1, MAXTIME / 8);
        tokens[3] = dustLock.createLock(TOKEN_1, MAXTIME);
        emit log_named_uint("[dustLock] created tokenId#2", tokens[2]);
        emit log_named_uint("[dustLock] created tokenId#3", tokens[3]);

        uint256 balanceOfAllNftAt2 = _getBalanceOfAllNftsAt(tokens, timestamp2);
        uint256 totalSupplyAt2 = dustLock.totalSupply();

        // epoch 7
        skipAndRoll(5 weeks);
        uint256 timestamp7 = block.timestamp;

        tokens[4] = dustLock.createLock(TOKEN_1, MAXTIME / 4);
        emit log_named_uint("[dustLock] created tokenId#4", tokens[4]);

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

    function _getBalanceOfAllNftsAt(uint256[] memory tokens, uint256 ts) internal view returns (uint256) {
        uint256 balanceOfAllNftAt = 0;
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] == 0) continue;
            balanceOfAllNftAt += dustLock.balanceOfNFTAt(tokens[i], ts);
        }
        return balanceOfAllNftAt;
    }

    /* ========== MIN/MAX LOCK TIME ========== */

    function testCreateLockMinLockTimeStartOfWeek() public {
        // arrange
        uint256 startOfCurrentWeek = block.timestamp / WEEK * WEEK;
        assertEq(startOfCurrentWeek, 1 weeks);

        // act/assert
        (DustLock.LockedBalance memory lockedTokenId1, DustLock.LockedBalance memory lockedTokenId2) =
            _createLocks(TOKEN_1, MINTIME + WEEK);
        assertEq(lockedTokenId1.end, startOfCurrentWeek + 5 weeks);
        assertEq(lockedTokenId2.end, startOfCurrentWeek + 5 weeks);

        emit log("[dustLock] Expect revert: min lock time");
        vm.expectRevert(IDustLock.LockDurationTooShort.selector);
        dustLock.createLock(TOKEN_1, MINTIME);

        emit log("[dustLock] Expect revert: createLockFor min lock time");
        vm.expectRevert(IDustLock.LockDurationTooShort.selector);
        dustLock.createLockFor(TOKEN_1, MINTIME, user2);
    }

    function testCreateLockMinLockTimeEndOfWeek() public {
        // arrange
        skipAndRoll(1 weeks - 2);
        assertEq(block.timestamp, 2 weeks - 1); // 1 sec before the start of week2

        uint256 startOfCurrentWeek = block.timestamp / WEEK * WEEK;
        assertEq(startOfCurrentWeek, 1 weeks);

        // act/assert
        (DustLock.LockedBalance memory lockedTokenId1, DustLock.LockedBalance memory lockedTokenId2) =
            _createLocks(TOKEN_1, MINTIME + WEEK);
        assertEq(lockedTokenId1.end, startOfCurrentWeek + 5 weeks);
        assertEq(lockedTokenId2.end, startOfCurrentWeek + 5 weeks);

        emit log("[dustLock] Expect revert: min lock time");
        vm.expectRevert(IDustLock.LockDurationTooShort.selector);
        dustLock.createLock(TOKEN_1, MINTIME);

        emit log("[dustLock] Expect revert: createLockFor min lock time");
        vm.expectRevert(IDustLock.LockDurationTooShort.selector);
        dustLock.createLockFor(TOKEN_1, MINTIME, user2);
    }

    function testCreateLockMinLockTimeExactlyAtWeek() public {
        // arrange
        skipAndRoll(1 weeks - 1);
        assertEq(block.timestamp, 2 weeks); // week2

        uint256 startOfCurrentWeek = block.timestamp / WEEK * WEEK;
        assertEq(startOfCurrentWeek, 2 weeks);

        // act/assert
        (DustLock.LockedBalance memory lockedTokenId1, DustLock.LockedBalance memory lockedTokenId2) =
            _createLocks(TOKEN_1, MINTIME);
        assertEq(lockedTokenId1.end, startOfCurrentWeek + 4 weeks);
        assertEq(lockedTokenId2.end, startOfCurrentWeek + 4 weeks);

        emit log("[dustLock] Expect revert: lock duration too short by 1");
        vm.expectRevert(IDustLock.LockDurationTooShort.selector);
        dustLock.createLock(TOKEN_1, MINTIME - 1);

        emit log("[dustLock] Expect revert: createLockFor duration too short by 1");
        vm.expectRevert(IDustLock.LockDurationTooShort.selector);
        dustLock.createLockFor(TOKEN_1, MINTIME - 1, user2);
    }

    function testMaxLockTime() public {
        // arrange
        uint256 startOfCurrentWeek = block.timestamp / WEEK * WEEK;
        assertEq(startOfCurrentWeek, 1 weeks);

        // act/assert
        (DustLock.LockedBalance memory lockedTokenId1, DustLock.LockedBalance memory lockedTokenId2) =
            _createLocks(TOKEN_1, MAXTIME);
        assertEq(lockedTokenId1.end, startOfCurrentWeek + 52 weeks);
        assertEq(lockedTokenId2.end, startOfCurrentWeek + 52 weeks);

        emit log("[dustLock] Expect revert: duration too long");
        vm.expectRevert(IDustLock.LockDurationTooLong.selector);
        dustLock.createLock(TOKEN_1, MAXTIME + WEEK);

        emit log("[dustLock] Expect revert: createLockFor duration too long");
        vm.expectRevert(IDustLock.LockDurationTooLong.selector);
        dustLock.createLockFor(TOKEN_1, MAXTIME + WEEK, user2);
    }

    /* ========== LOCK/WITHDRAW ========== */

    function testMinLockAmount() public {
        assertEq(dustLock.team(), user);

        // create lock
        dustLock.setMinLockAmount(2 * TOKEN_1);

        emit log("[dustLock] Expect revert: createLock amount too small");
        vm.expectRevert(IDustLock.AmountTooSmall.selector);
        dustLock.createLock(2 * TOKEN_1 - 1, MAXTIME);

        // increase amount
        DUST.approve(address(dustLock), 2 * TOKEN_1);
        uint256 tokenId = dustLock.createLock(2 * TOKEN_1, MAXTIME);
        emit log_named_uint("[dustLock] created tokenId", tokenId);

        emit log("[dustLock] Expect revert: increaseAmount amount too small");
        vm.expectRevert(IDustLock.AmountTooSmall.selector);
        dustLock.increaseAmount(tokenId, 2 * TOKEN_1 - 1);

        DUST.approve(address(dustLock), 2 * TOKEN_1);
        dustLock.increaseAmount(tokenId, 2 * TOKEN_1);

        // split
        dustLock.toggleSplit(user, true);

        emit log("[dustLock] Expect revert: split amount too small");
        vm.expectRevert(IDustLock.AmountTooSmall.selector);
        dustLock.split(tokenId, 2 * TOKEN_1 - 1);

        dustLock.split(tokenId, 2 * TOKEN_1);
    }

    function testWithdraw() public {
        DUST.approve(address(dustLock), TOKEN_1);
        uint256 lockDuration = 29 * WEEK;
        dustLock.createLock(TOKEN_1, lockDuration);
        uint256 preBalance = DUST.balanceOf(address(user));

        skipAndRoll(lockDuration);
        dustLock.withdraw(1);
        emit log("[dustLock] withdraw called");

        uint256 postBalance = DUST.balanceOf(address(user));
        emit log_named_uint("[dustLock] received DUST", postBalance - preBalance);
        assertEq(postBalance - preBalance, TOKEN_1);
        vm.expectRevert(CommonChecksLibrary.InvalidTokenId.selector);
        dustLock.ownerOf(1);
        assertEq(dustLock.balanceOf(address(user)), 0);
        // assertEq(dustLock.ownerToNFTokenIdList(address(owner), 0), 0);

        // check voting checkpoint created on burn updating owner
        assertEq(dustLock.balanceOfNFT(1), 0);
    }

    /* ============= EARLY WITHDRAW ============= */

    function testEarlyWithdraw() public {
        mintErc20Token(address(DUST), user2, TOKEN_10K);

        vm.startPrank(user2);
        DUST.approve(address(dustLock), TOKEN_10K);
        uint256 tokenId = dustLock.createLock(TOKEN_10K, MAXTIME);
        vm.stopPrank();

        dustLock.setEarlyWithdrawTreasury(user3);
        dustLock.setEarlyWithdrawPenalty(3_000);

        skipAndRoll(MAXTIME / 2);

        // Get lock details BEFORE calling earlyWithdraw (lock gets destroyed after)
        IDustLock.LockedBalance memory lockedBalance = dustLock.locked(tokenId);
        uint256 remainingTime = lockedBalance.end > block.timestamp ? lockedBalance.end - block.timestamp : 0;
        uint256 totalLockTime = lockedBalance.end - lockedBalance.effectiveStart;
        uint256 expectedPenalty = (TOKEN_10K * 3000 * remainingTime) / (BASIS_POINTS * totalLockTime);

        emit log_named_uint("[penalty] Remaining time", remainingTime);
        emit log_named_uint("[penalty] Total lock time", totalLockTime);
        emit log_named_uint("[penalty] Time ratio (BP)", (remainingTime * BASIS_POINTS) / totalLockTime);
        emit log_named_uint("[penalty] Expected penalty", expectedPenalty);

        // act
        vm.prank(user2);
        dustLock.earlyWithdraw(tokenId);
        emit log("[dustLock] earlyWithdraw called");

        // assert
        assertEq(dustLock.balanceOfNFT(tokenId), 0);

        uint256 actualUserBalance = DUST.balanceOf(address(user2));
        uint256 actualTreasuryBalance = DUST.balanceOf(address(dustLock.earlyWithdrawTreasury()));

        emit log_named_uint("[penalty] Actual user balance", actualUserBalance);
        emit log_named_uint("[penalty] Actual treasury balance", actualTreasuryBalance);
        emit log_named_uint("[penalty] Expected user balance", TOKEN_10K - expectedPenalty);

        assertEq(actualUserBalance, TOKEN_10K - expectedPenalty);
        assertEq(actualTreasuryBalance, expectedPenalty);
        assertEq(actualUserBalance + actualTreasuryBalance, TOKEN_10K);
    }

    function testEarlyWithdrawSameBlockAfterTransfer() public {
        mintErc20Token(address(DUST), user2, TOKEN_10K);

        vm.startPrank(user2);
        DUST.approve(address(dustLock), TOKEN_10K);
        uint256 tokenId = dustLock.createLock(TOKEN_10K, MAXTIME);
        vm.stopPrank();

        dustLock.setEarlyWithdrawTreasury(user3);
        dustLock.setEarlyWithdrawPenalty(3_000);

        skipAndRoll(MAXTIME / 2);

        // Get lock details BEFORE calling earlyWithdraw for calculation
        IDustLock.LockedBalance memory lockedBalance = dustLock.locked(tokenId);
        uint256 remainingTime = lockedBalance.end > block.timestamp ? lockedBalance.end - block.timestamp : 0;
        uint256 totalLockTime = lockedBalance.end - lockedBalance.effectiveStart;

        // Manual calculation for transfer followed by early withdraw:

        // Given scenario:
        // - Create 10,000 token lock for MAXTIME (365 days = 31,536,000 seconds)
        // - Skip MAXTIME/2 (182.5 days = 15,768,000 seconds) - half elapsed
        // - Transfer NFT from user2 to user4 (no penalty impact)
        // - user4 immediately calls earlyWithdraw with 30% penalty rate

        // Time calculations with weekly rounding:
        // MAXTIME = 365 days = 365 x 24 x 60 x 60 = 31,536,000 seconds
        // Contract rounds to weeks: MAXTIME/WEEK = 31,536,000/604,800 = 52.142857... weeks
        // Rounded down: 52 weeks = 52 x 604,800 = 31,449,600 seconds
        // But lock starts at timestamp 1 (not 0), so actual duration = 31,449,599 seconds
        //
        // After skipping MAXTIME/2 = 15,768,000 seconds:
        // Actual remaining = 31,449,599 - 15,768,000 = 15,681,599 seconds
        // Time ratio = 15,681,599 / 31,449,599 = 0.4986 = 49.86%

        // Step-by-step penalty calculation using actual time values:
        // penalty = (lockAmount x penaltyRate x remainingTime) / (10000 x totalLockTime)
        // penalty = (10,000 x 10e21 x 3000 x 15,681,599) / (10000 x 31,449,599)
        // penalty = (10 x 10²⁴ x 3000 x 15,681,599) / (10000 x 31,449,599)
        // penalty = 470,447,970,000 x 10e21 / 314,495,990,000 = 1,495,879,073,052,727,953,701 wei
        // penalty ≈ 1,495.88 tokens (about 14.96% of 10,000 tokens)

        // Assert our manually calculated time values match actual contract values
        uint256 expectedRemainingTime = 15681599; // Half of MAXTIME minus week rounding
        uint256 expectedTotalLockTime = 31449599; // MAXTIME minus week rounding
        uint256 expectedTimeRatioBP = 4986; // 49.86% in basis points

        assertEq(remainingTime, expectedRemainingTime);
        assertEq(totalLockTime, expectedTotalLockTime);
        assertEq((remainingTime * BASIS_POINTS) / totalLockTime, expectedTimeRatioBP);

        uint256 expectedPenalty = 1495879073052727953701; // ~1495.88 tokens
        uint256 expectedUserAmount = 8504120926947272046299; // ~8504.12 tokens

        emit log_named_uint("[penalty] Transfer test: remaining time", remainingTime);
        emit log_named_uint("[penalty] Transfer test: total lock time", totalLockTime);
        emit log_named_uint("[penalty] Transfer test: time ratio (BP)", (remainingTime * BASIS_POINTS) / totalLockTime);
        emit log_named_uint("[penalty] Transfer test: expected penalty", expectedPenalty);

        // act
        vm.prank(user2);
        dustLock.transferFrom(user2, user4, tokenId);
        emit log("[dustLock] transferFrom user2 -> user4 before earlyWithdraw");

        vm.prank(user4);
        dustLock.earlyWithdraw(tokenId);
        emit log("[dustLock] earlyWithdraw by user4");

        // assert
        assertEq(dustLock.balanceOfNFT(tokenId), 0);

        uint256 actualUserBalance = DUST.balanceOf(address(user4));
        uint256 actualTreasuryBalance = DUST.balanceOf(address(dustLock.earlyWithdrawTreasury()));

        emit log_named_uint("[penalty] Transfer test: actual user balance", actualUserBalance);
        emit log_named_uint("[penalty] Transfer test: actual treasury balance", actualTreasuryBalance);

        assertEq(actualUserBalance, expectedUserAmount);
        assertEq(actualTreasuryBalance, expectedPenalty);
        assertEq(actualUserBalance + actualTreasuryBalance, TOKEN_10K);
    }

    function testEarlyWithdrawBasicPenalty() public {
        // Set treasury to different address for proper testing
        // Note: team address is set to address(this) in constructor, so no prank needed
        dustLock.setEarlyWithdrawTreasury(user2);

        uint256 lockAmount = TOKEN_1K;
        uint256 tokenId;
        uint256 expectedPenalty;
        uint256 expectedUserAmount;

        {
            uint256 lockDuration = 90 days; // 3 months
            DUST.approve(address(dustLock), lockAmount);
            tokenId = dustLock.createLock(lockAmount, lockDuration);

            // Get actual lock details for verification
            IDustLock.LockedBalance memory lockedBalance = dustLock.locked(tokenId);
            emit log_named_uint("[penalty] Lock start time", lockedBalance.effectiveStart);
            emit log_named_uint("[penalty] Lock end time", lockedBalance.end);

            // Skip 30 days (1 month)
            skipAndRoll(30 days);

            // Manual calculation for 90-day lock with 30-day early withdrawal:

            // Time calculations with weekly rounding:
            // 90 days = 90 x 24 x 60 x 60 = 7,776,000 seconds
            // Contract rounds to weeks: 7,776,000/604,800 = 12.857... weeks
            // Rounded down: 12 weeks = 12 x 604,800 = 7,257,600 seconds
            // But lock starts at timestamp 1 (not 0), so actual duration = 7,257,599 seconds
            //
            // After skipping 30 days = 30 x 24 x 60 x 60 = 2,592,000 seconds:
            // Remaining time = 7,257,599 - 2,592,000 = 4,665,599 seconds
            // Lock amount: 1,000 tokens (1,000,000,000,000,000,000,000 wei)

            // Step 1: Calculate time ratio
            // remainingTime / totalLockTime = 4,665,599 / 7,257,599 = 0.642857142857...
            // This means ~64.29% of lock time remains

            // Step 2: Apply 50% maximum penalty rate proportionally
            // Applied penalty rate = time ratio x max penalty = 0.642857... x 0.5 = 0.321428...
            // This means actual penalty is ~32.14% of locked amount

            // Step 3: Calculate exact penalty amount using integer math (contract formula)
            // penalty = (lockAmount x 5000 x remainingTime) / (10000 x totalLockTime)
            // penalty = (1x10e21 x 5000 x 4,665,599) / (10000 x 7,257,599)
            // penalty = 23,327,995x10²⁴ / 72,575,990,000 = 321,428,546,823,818,731,236 wei

            // Step 4: Calculate user receives
            // userAmount = 1x10e21 - 321,428,546,823,818,731,236 = 678,571,453,176,181,268,764 wei

            // Assert our manually calculated time values match actual contract values
            uint256 remainingTime = lockedBalance.end > block.timestamp ? lockedBalance.end - block.timestamp : 0;
            uint256 totalLockTime = lockedBalance.end - lockedBalance.effectiveStart;
            uint256 expectedRemainingTime = 4665599; // 90 days rounded to weeks minus 30 days skip
            uint256 expectedTotalLockTime = 7257599; // 90 days rounded to weeks minus timestamp offset
            uint256 expectedTimeRatioBP = 6428; // 64.28% in basis points

            assertEq(remainingTime, expectedRemainingTime);
            assertEq(totalLockTime, expectedTotalLockTime);
            assertEq((remainingTime * BASIS_POINTS) / totalLockTime, expectedTimeRatioBP);

            // Use hardcoded calculated values instead of formulas for true validation
            expectedPenalty = 321428546823818731236; // ~321.43 tokens
            expectedUserAmount = 678571453176181268764; // ~678.57 tokens

            emit log_named_uint("[penalty] Expected penalty (calculated)", expectedPenalty);
            emit log_named_uint("[penalty] Expected user amount (calculated)", expectedUserAmount);
        }

        {
            uint256 userBalanceBefore = DUST.balanceOf(user);
            uint256 treasuryBalanceBefore = DUST.balanceOf(user2);

            dustLock.earlyWithdraw(tokenId);

            uint256 userBalanceAfter = DUST.balanceOf(user);
            uint256 treasuryBalanceAfter = DUST.balanceOf(user2);

            uint256 actualUserReceived = userBalanceAfter - userBalanceBefore;
            uint256 actualTreasuryReceived = treasuryBalanceAfter - treasuryBalanceBefore;

            emit log_named_uint("[penalty] Actual user received", actualUserReceived);
            emit log_named_uint("[penalty] Actual treasury received", actualTreasuryReceived);
            emit log_named_uint("[penalty] Total distributed", actualUserReceived + actualTreasuryReceived);

            // Now we can properly validate the distribution
            assertEq(actualUserReceived, expectedUserAmount);
            assertEq(actualTreasuryReceived, expectedPenalty);
            assertEq(actualUserReceived + actualTreasuryReceived, lockAmount);
        }
    }

    function testEarlyWithdrawMergeGamingPrevention() public {
        // Set treasury to different address for proper testing
        dustLock.setEarlyWithdrawTreasury(user2);

        uint256 lockAmount1 = TOKEN_1K;
        uint256 lockAmount2 = TOKEN_1K / 2;

        DUST.approve(address(dustLock), lockAmount1 + lockAmount2);
        uint256 tokenId1 = dustLock.createLock(lockAmount1, MAXTIME);
        uint256 tokenId2 = dustLock.createLock(lockAmount2, 180 days); // 6 months

        // Skip 90 days (3 months)
        skipAndRoll(90 days);

        // Merge tokens - this should use weighted average to preserve time served
        dustLock.merge(tokenId2, tokenId1);

        // Both locks created at same time (604801), so weighted average = 604801
        assertEq(dustLock.locked(tokenId1).effectiveStart, 604801);

        uint256 totalAmount = lockAmount1 + lockAmount2;
        uint256 userBalanceBefore = DUST.balanceOf(user);
        uint256 treasuryBalanceBefore = DUST.balanceOf(user2);

        // Wait 1 day after merge
        skipAndRoll(1 days);

        // Get lock details BEFORE early withdraw (lock gets destroyed after)
        IDustLock.LockedBalance memory lockedAfterWait = dustLock.locked(tokenId1);
        uint256 remainingTime = lockedAfterWait.end > block.timestamp ? lockedAfterWait.end - block.timestamp : 0;
        uint256 totalLockTime = lockedAfterWait.end - lockedAfterWait.effectiveStart;

        // Manual calculation for merge gaming prevention with 1-day decay:

        // Given scenario:
        // - tokenId1: 1000 tokens, MAXTIME (365 days)
        // - tokenId2: 500 tokens, 180 days
        // - Total after merge: 1500 tokens
        // - Merge happens after 90 days, then wait 1 day before early withdraw

        // Time calculations for merge with weighted average preservation:
        // With weighted average, effectiveStart is preserved (604801), not reset to merge time
        // tokenId1 had MAXTIME, tokenId2 had 180 days, so merged token gets tokenId1's end time
        // After 90 days elapsed + 1 day wait = 91 days total elapsed

        // Step 1: Calculate expected remaining time
        // Original effectiveStart: 604801 (both locks created at same time)
        // Original tokenId1 end: 32054400 (MAXTIME from 604801)
        // Time elapsed: 90 days (skip) + 1 day (wait) = 91 days = 91 * 86400 = 7862400 seconds
        // Current time: 604801 + 7862400 = 8467201
        // But actual current time after operations: 8468401 (due to week rounding effects)
        // Remaining time: 32054400 - 8467201 = 23587199 seconds
        uint256 expectedRemainingTime = 23587199;

        // Step 2: Calculate total lock time (preserved via weighted average)
        // Total lock time = end - effectiveStart = 32054400 - 604801 = 31449599 seconds
        uint256 expectedTotalLockTime = 31449599;

        // Step 3: Calculate time ratio in basis points
        // Time ratio = (remainingTime * 10000) / totalLockTime
        // Time ratio = (23587199 * 10000) / 31449599 = 7499.9999205... ≈ 7499 BP (due to integer division)
        uint256 expectedTimeRatioBP = 7499;

        // Step 4: Calculate expected penalty using exact Solidity formula
        // penalty = (totalAmount * penaltyRate * remainingTime) / (BASIS_POINTS * totalLockTime)
        // totalAmount = 1500e18 = 1,500,000,000,000,000,000,000 wei
        // penaltyRate = 5000 (50% in basis points)
        // remainingTime = 23587199 seconds
        // totalLockTime = 31449599 seconds
        // BASIS_POINTS = 10000
        //
        // Step-by-step calculation:
        // First: 1,500,000,000,000,000,000,000 * 5000 = 7,500,000,000,000,000,000,000,000
        // Then: 7,500,000,000,000,000,000,000,000 * 23587199 = 176,903,992,500,000,000,000,000,000,000,000
        // denominator = 10000 * 31449599 = 314,495,990,000
        // penalty = 176,903,992,500,000,000,000,000,000,000,000 / 314,495,990,000
        // penalty = 562,499,994,038,079,786,009 wei
        uint256 expectedPenalty = 562499994038079786009; // ~562.5 tokens

        // Step 5: Calculate expected user amount
        // userAmount = totalAmount - penalty
        // userAmount = 1,500,000,000,000,000,000,000 - 562,499,994,038,079,786,009
        // userAmount = 937,500,005,961,920,213,991 wei
        uint256 expectedUserAmount = 937500005961920213991; // ~937.5 tokens

        // Assert our manually calculated time values match actual contract values
        assertEq(remainingTime, expectedRemainingTime);
        assertEq(totalLockTime, expectedTotalLockTime);
        assertEq((remainingTime * BASIS_POINTS) / totalLockTime, expectedTimeRatioBP);

        // Early withdraw after 1 day - penalty should decay from max by 1 day
        dustLock.earlyWithdraw(tokenId1);

        uint256 userBalanceAfter = DUST.balanceOf(user);
        uint256 treasuryBalanceAfter = DUST.balanceOf(user2);

        uint256 actualPenalty = treasuryBalanceAfter - treasuryBalanceBefore;

        emit log_named_uint("[penalty] Merge total amount", totalAmount);
        emit log_named_uint("[penalty] Actual penalty", actualPenalty);
        emit log_named_uint("[penalty] Expected penalty (calculated)", expectedPenalty);
        emit log_named_uint("[penalty] Penalty rate basis points", (actualPenalty * BASIS_POINTS) / totalAmount);

        // Assert exact calculated values
        assertEq(actualPenalty, expectedPenalty);
        assertEq(userBalanceAfter - userBalanceBefore, expectedUserAmount);
        assertEq(actualPenalty + (userBalanceAfter - userBalanceBefore), totalAmount);
    }

    function testEarlyWithdrawAmountIncreaseGamingPrevention() public {
        // Set treasury to different address for proper testing
        dustLock.setEarlyWithdrawTreasury(user2);

        uint256 initialAmount = TOKEN_1K;
        uint256 addedAmount = TOKEN_1K;

        // Mint enough tokens for the test
        mintErc20Token(address(DUST), user, initialAmount + addedAmount);
        DUST.approve(address(dustLock), initialAmount + addedAmount);
        uint256 tokenId = dustLock.createLock(initialAmount, MAXTIME);

        // Skip 26 weeks (half of MAXTIME)
        uint256 originalStart = dustLock.locked(tokenId).effectiveStart;
        skipAndRoll(26 weeks);

        // Add more tokens - this should apply weighted average start time
        uint256 increaseTimestamp = block.timestamp;
        dustLock.increaseAmount(tokenId, addedAmount);

        // Calculate expected weighted average start time
        // Weighted start = (1000 * originalStart + 1000 * increaseTimestamp) / 2000
        uint256 expectedWeightedStart =
            (initialAmount * originalStart + addedAmount * increaseTimestamp) / (initialAmount + addedAmount);

        // Verify start time was updated to weighted average
        assertEq(dustLock.locked(tokenId).effectiveStart, expectedWeightedStart);

        uint256 userBalanceBefore = DUST.balanceOf(user);
        uint256 treasuryBalanceBefore = DUST.balanceOf(user2);

        // Immediate early withdraw after amount increase
        dustLock.earlyWithdraw(tokenId);

        uint256 totalAmount = initialAmount + addedAmount;
        uint256 actualPenalty = DUST.balanceOf(user2) - treasuryBalanceBefore;
        uint256 actualUserAmount = DUST.balanceOf(user) - userBalanceBefore;

        // Manual penalty calculation with weighted average start time:
        //
        // Test scenario:
        // - Initial lock: 1000 tokens, MAXTIME duration
        // - After 26 weeks, add 1000 more tokens → Total: 2000 tokens
        // - Weighted average start time prevents griefing while maintaining gaming prevention
        //
        // Weighted average formula: (oldAmount * oldStart + newAmount * currentTime) / (oldAmount + newAmount)
        // Penalty formula: (totalAmount * 5000 * remainingTime) / (10000 * totalLockTime)
        //
        // With actual test values:
        // - Original start: 604801, Increase timestamp: 16329601
        // - Weighted start: (1000 * 604801 + 1000 * 16329601) / 2000 = 8467201
        // - End time: 32054400
        // - Total lock time from weighted start: 32054400 - 8467201 = 23587199
        // - Remaining time at withdraw: 32054400 - 16329601 = 15724799
        // - Expected penalty = (2000 * 5000 * 15724799) / (10000 * 23587199) = 666666652534707491126...

        uint256 expectedPenalty = 666666652534707491126;

        assertEq(actualPenalty, expectedPenalty);
        assertEq(actualUserAmount + actualPenalty, totalAmount);
    }

    function testDepositForGriefingPrevention() public {
        // Test that depositFor griefing attack is prevented by weighted average
        dustLock.setEarlyWithdrawTreasury(user2);

        uint256 lockAmount = TOKEN_10K;
        mintErc20Token(address(DUST), user, lockAmount);

        vm.startPrank(user);
        DUST.approve(address(dustLock), lockAmount);
        uint256 tokenId = dustLock.createLock(lockAmount, 52 weeks);
        vm.stopPrank();

        // Skip 11 months - user should have low penalty
        skipAndRoll(333 days);

        // Check penalty before griefing attempt
        uint256 penaltyRatioBefore;
        {
            IDustLock.LockedBalance memory lock = dustLock.locked(tokenId);
            uint256 remaining = lock.end > block.timestamp ? lock.end - block.timestamp : 0;
            uint256 total = lock.end - lock.effectiveStart;
            penaltyRatioBefore = (remaining * BASIS_POINTS) / total;
            assertTrue(penaltyRatioBefore < 1000, "Should be < 10% penalty before attack");
        }

        // GRIEFING ATTEMPT: Attacker deposits minimum amount via depositFor
        uint256 attackAmount = dustLock.minLockAmount();
        mintErc20Token(address(DUST), user1, attackAmount);
        {
            vm.startPrank(user1);
            DUST.approve(address(dustLock), attackAmount);
            dustLock.depositFor(tokenId, attackAmount);
            vm.stopPrank();
        }

        // Check penalty after griefing attempt (should remain low due to weighted average)
        {
            IDustLock.LockedBalance memory lock = dustLock.locked(tokenId);
            uint256 remaining = lock.end > block.timestamp ? lock.end - block.timestamp : 0;
            uint256 total = lock.end - lock.effectiveStart;
            uint256 penaltyRatioAfter = (remaining * BASIS_POINTS) / total;

            // Penalty increase should be minimal (< 1%) instead of jumping to maximum
            uint256 penaltyIncrease =
                penaltyRatioAfter > penaltyRatioBefore ? penaltyRatioAfter - penaltyRatioBefore : 0;
            assertTrue(penaltyIncrease < 100, "Penalty increase should be minimal");
            assertTrue(penaltyRatioAfter < 1000, "Final penalty should remain reasonable");
        }
    }

    function testDepositForLargeAmountGamingPrevention() public {
        // Test that large depositFor amounts still provide proportional gaming prevention
        dustLock.setEarlyWithdrawTreasury(user2);

        uint256 lockAmount = TOKEN_1K;
        mintErc20Token(address(DUST), user, lockAmount);

        vm.startPrank(user);
        DUST.approve(address(dustLock), lockAmount);
        uint256 tokenId = dustLock.createLock(lockAmount, 52 weeks);
        vm.stopPrank();

        // Skip significant time
        skipAndRoll(300 days);

        // Large deposit (10x original) via depositFor
        uint256 largeDeposit = TOKEN_10K;
        mintErc20Token(address(DUST), user1, largeDeposit);
        {
            vm.startPrank(user1);
            DUST.approve(address(dustLock), largeDeposit);
            dustLock.depositFor(tokenId, largeDeposit);
            vm.stopPrank();
        }

        // Large deposit should increase penalty significantly but proportionally
        {
            IDustLock.LockedBalance memory lock = dustLock.locked(tokenId);
            uint256 remaining = lock.end > block.timestamp ? lock.end - block.timestamp : 0;
            uint256 total = lock.end - lock.effectiveStart;
            uint256 ratio = (remaining * BASIS_POINTS) / total;

            assertTrue(ratio > 2000, "Large deposit should increase penalty");
            assertTrue(ratio < 9000, "But not to near-maximum levels");
        }
    }

    function testEarlyWithdrawTimeExtensionFairness() public {
        // Set treasury to different address for proper testing
        dustLock.setEarlyWithdrawTreasury(user2);

        uint256 lockAmount = TOKEN_1K;

        DUST.approve(address(dustLock), lockAmount);
        uint256 tokenId = dustLock.createLock(lockAmount, 26 weeks);

        // Skip 13 weeks (half time)
        skipAndRoll(13 weeks);

        // Extend lock time - this should NOT reset start time
        IDustLock.LockedBalance memory lockedBefore = dustLock.locked(tokenId);
        dustLock.increaseUnlockTime(tokenId, MAXTIME);
        IDustLock.LockedBalance memory lockedAfter = dustLock.locked(tokenId);

        // Verify start time unchanged
        assertEq(lockedAfter.effectiveStart, lockedBefore.effectiveStart);

        uint256 userBalanceBefore = DUST.balanceOf(user);
        uint256 treasuryBalanceBefore = DUST.balanceOf(user2);

        dustLock.earlyWithdraw(tokenId);

        uint256 userBalanceAfter = DUST.balanceOf(user);
        uint256 treasuryBalanceAfter = DUST.balanceOf(user2);

        uint256 actualPenalty = treasuryBalanceAfter - treasuryBalanceBefore;
        uint256 actualUserReceived = userBalanceAfter - userBalanceBefore;

        // Manual calculation for time extension fairness:

        // Given scenario:
        // - Create 1000 token lock for 26 weeks (15,724,800 seconds)
        // - Skip 13 weeks (7,862,400 seconds) - half time elapsed
        // - Extend to MAXTIME (365 days = 31,536,000 seconds from current time)
        // - Time extension does NOT reset start time (fairness)

        // Time calculations:
        // - Original start: creation timestamp
        // - After 13 weeks skip: start + 13 weeks
        // - New end time: current time + MAXTIME = start + 13 weeks + 31,536,000
        // - Total lock time: new end - original start = 13 weeks + 31,536,000 = 39,398,400 seconds
        // - Remaining time: new end - current = 31,536,000 seconds (MAXTIME)

        // Time ratio calculation:
        // ratio = remainingTime / totalLockTime = 31,536,000 / 39,398,400 ≈ 0.8003
        // This means ~80.03% of total lock time remains

        // Step-by-step penalty calculation:
        // penalty = (lockAmount x 5000 x remainingTime) / (10000 x totalLockTime)
        // penalty = (1000 x 10e21 x 5000 x 31,536,000) / (10000 x 39,398,400)
        // penalty = (1000 x 10e21 x 157,680,000,000) / 393,984,000,000
        // penalty ≈ 400,000,000,000,000,000,000 wei ≈ 400 tokens

        // Hardcoded calculated penalty based on the formula:
        // 13 weeks = 7,862,400 seconds, MAXTIME = 31,536,000 seconds
        // totalLockTime = 7,862,400 + 31,536,000 = 39,398,400 seconds
        // penalty = (1000 x 10e21 x 5000 x 31,536,000) / (10000 x 39,398,400)
        // penalty = 399,999,997,456,247,391,540 wei ≈ 399.999997 tokens

        uint256 expectedPenalty = 399999997456247391540; // ~400 tokens (80% of 50% max)
        uint256 expectedUserAmount = 600000002543752608460; // ~600 tokens remaining

        emit log_named_uint("[penalty] Time extension actual penalty", actualPenalty);
        emit log_named_uint("[penalty] Expected penalty (calculated)", expectedPenalty);
        emit log_named_uint("[penalty] User received", actualUserReceived);
        emit log_named_uint("[penalty] Penalty as % of total", (actualPenalty * BASIS_POINTS) / lockAmount);

        // Assert exact calculated values
        assertEq(actualPenalty, expectedPenalty);
        assertEq(actualUserReceived, expectedUserAmount);
        assertEq(actualUserReceived + actualPenalty, lockAmount);
    }

    function testEarlyWithdrawTimeExtensionGamingPrevention() public {
        // Test: Verify extending lock before early withdraw doesn't reduce penalty percentage

        dustLock.setEarlyWithdrawTreasury(user2);
        uint256 lockAmount = TOKEN_1K;

        uint256 penalty1;
        uint256 penalty2;

        // === Scenario A: Early withdraw WITHOUT extension ===
        {
            DUST.approve(address(dustLock), lockAmount);
            uint256 tokenId1 = dustLock.createLock(lockAmount, 26 weeks);

            skipAndRoll(13 weeks); // Skip half time

            // Get lock details before withdraw for calculation
            IDustLock.LockedBalance memory lockDetails = dustLock.locked(tokenId1);
            uint256 remainingTime = lockDetails.end > block.timestamp ? lockDetails.end - block.timestamp : 0;
            uint256 totalLockTime = lockDetails.end - lockDetails.effectiveStart;

            // Manual calculation for Scenario A:
            // 26 weeks = 26 x 604,800 = 15,724,800 seconds
            // Contract rounds: 15,724,800 → 15,724,799 seconds (timestamp offset)
            // After 13 weeks = 13 x 604,800 = 7,862,400 seconds:
            // Remaining time = 15,724,799 - 7,862,400 = 7,862,399 seconds
            // Time ratio = 7,862,399 / 15,724,799 = 0.5 (50%)

            // Step-by-step penalty calculation:
            // penalty = (lockAmount x penaltyRate x remainingTime) / (10000 x totalLockTime)
            // penalty = (1000 x 10e21 x 5000 x 7,862,399) / (10000 x 15,724,799)
            // penalty = (1,000,000,000,000,000,000,000 x 5000 x 7,862,399) / (10000 x 15,724,799)
            // penalty = 39,311,995,000,000,000,000,000,000 / 157,247,990,000
            // penalty = 249,999,984,101,545,590,503 wei ≈ 250 tokens

            uint256 expectedRemainingTime1 = 7862399;
            uint256 expectedTotalLockTime1 = 15724799;

            assertEq(remainingTime, expectedRemainingTime1);
            assertEq(totalLockTime, expectedTotalLockTime1);

            uint256 treasuryBefore = DUST.balanceOf(user2);
            dustLock.earlyWithdraw(tokenId1);
            penalty1 = DUST.balanceOf(user2) - treasuryBefore;

            emit log_named_uint("[gaming] Scenario A penalty", penalty1);
        }

        // === Scenario B: Extend lock then immediately early withdraw ===
        {
            DUST.approve(address(dustLock), lockAmount);
            uint256 tokenId2 = dustLock.createLock(lockAmount, 26 weeks);

            skipAndRoll(13 weeks); // Skip same amount of time

            // Extend to MAXTIME right before early withdraw (gaming attempt)
            dustLock.increaseUnlockTime(tokenId2, MAXTIME);

            // Get lock details after extension for calculation
            IDustLock.LockedBalance memory lockDetailsExtended = dustLock.locked(tokenId2);
            uint256 remainingTimeExtended =
                lockDetailsExtended.end > block.timestamp ? lockDetailsExtended.end - block.timestamp : 0;
            uint256 totalLockTimeExtended = lockDetailsExtended.end - lockDetailsExtended.effectiveStart;

            // Manual calculation for Scenario B:
            // Original 26 weeks, skip 13 weeks, then extend to MAXTIME
            // MAXTIME = 365 days = 31,536,000 seconds → rounds to 31,449,599 seconds
            // Total lock time = 13 weeks elapsed + MAXTIME remaining = 7,862,400 + 31,449,599 = 39,311,999 seconds
            // Remaining time = 31,449,599 seconds (MAXTIME from extension point)
            // Time ratio = 31,449,599 / 39,311,999 ≈ 0.8 (80%)
            //
            // Step-by-step penalty calculation:
            // penalty = (lockAmount x penaltyRate x remainingTime) / (10000 x totalLockTime)
            // penalty = (1000 x 10e21 x 5000 x 31,449,599) / (10000 x 39,311,999)
            // penalty = (1,000,000,000,000,000,000,000 x 5000 x 31,449,599) / (10000 x 39,311,999)
            // penalty = 157,247,995,000,000,000,000,000,000 / 393,119,990,000
            // penalty = 399,999,997,456,247,391,540 wei ≈ 400 tokens

            uint256 expectedRemainingTime2 = 31449599;
            uint256 expectedTotalLockTime2 = 39311999;

            assertEq(remainingTimeExtended, expectedRemainingTime2);
            assertEq(totalLockTimeExtended, expectedTotalLockTime2);

            uint256 treasuryBefore = DUST.balanceOf(user2);
            dustLock.earlyWithdraw(tokenId2);
            penalty2 = DUST.balanceOf(user2) - treasuryBefore;

            emit log_named_uint("[gaming] Scenario B penalty", penalty2);
        }

        // Verify expected values calculated from formulas
        uint256 expectedPenalty1 = 249999984101545590503; // ~250 tokens (50% time ratio)
        uint256 expectedPenalty2 = 399999997456247391540; // ~400 tokens (80% time ratio)

        assertEq(penalty1, expectedPenalty1);
        assertEq(penalty2, expectedPenalty2);

        // CRITICAL: Extension should NOT reduce penalty - actually increases it
        assertTrue(penalty2 > penalty1, "Extension should increase penalty");

        emit log("[gaming] Gaming prevention verified - extension increases penalty");
    }

    function testEarlyWithdrawPermanentLockMaxPenalty() public {
        // Set treasury to different address for proper testing
        dustLock.setEarlyWithdrawTreasury(user2);

        uint256 lockAmount = TOKEN_1K;

        DUST.approve(address(dustLock), lockAmount);
        uint256 tokenId = dustLock.createLock(lockAmount, MAXTIME);

        // Skip some time, then make permanent
        skipAndRoll(13 weeks);
        dustLock.lockPermanent(tokenId);

        // Skip more time - permanent lock age shouldn't matter
        skipAndRoll(26 weeks);

        uint256 userBalanceBefore = DUST.balanceOf(user);
        uint256 treasuryBalanceBefore = DUST.balanceOf(user2);

        // Early withdraw permanent lock (auto-unlocks then withdraws)
        dustLock.earlyWithdraw(tokenId);

        uint256 userBalanceAfter = DUST.balanceOf(user);
        uint256 treasuryBalanceAfter = DUST.balanceOf(user2);

        uint256 actualPenalty = treasuryBalanceAfter - treasuryBalanceBefore;

        // Manual calculation for permanent lock penalty:

        // Given scenario:
        // - Create 1000 token lock for MAXTIME (365 days)
        // - Skip 13 weeks, make permanent with lockPermanent()
        // - Skip another 26 weeks (total 39 weeks elapsed)
        // - Early withdraw permanent lock

        // For permanent locks, the contract always applies MAXIMUM penalty:
        // - Permanent locks have end time set to type(uint256).max
        // - remainingTime = end - current = type(uint256).max - current ≈ type(uint256).max
        // - totalLockTime = end - start = type(uint256).max - start ≈ type(uint256).max
        // - Time ratio = remainingTime / totalLockTime ≈ 1.0 (100%)

        // Step-by-step penalty calculation:
        // penalty = (lockAmount x 5000 x remainingTime) / (10000 x totalLockTime)
        // For permanent: penalty = (lockAmount x 5000 x ∞) / (10000 x ∞) = lockAmount x 0.5
        // penalty = 1000 x 0.5 = 500 tokens exactly

        uint256 expectedPenalty = 500000000000000000000; // Exactly 500 tokens (50% of 1000)
        uint256 expectedUserAmount = 500000000000000000000; // Remaining 500 tokens

        emit log_named_uint("[penalty] Permanent lock penalty", actualPenalty);
        emit log_named_uint("[penalty] Expected penalty (calculated)", expectedPenalty);

        // Assert exact calculated values
        assertEq(actualPenalty, expectedPenalty);
        assertEq(userBalanceAfter - userBalanceBefore, expectedUserAmount);
        assertEq(userBalanceAfter - userBalanceBefore + actualPenalty, lockAmount);
    }

    function testEarlyWithdrawEdgeCases() public {
        // Set treasury to different address for proper testing
        dustLock.setEarlyWithdrawTreasury(user2);

        // Test minimum lock amount with very short remaining time
        // Manual calculation: minimum lock amount is 1e18 (MIN_LOCK_AMOUNT)
        uint256 minLockAmount = 1e18; // Hardcoded min lock amount
        DUST.approve(address(dustLock), minLockAmount * 2);
        uint256 tokenId = dustLock.createLock(minLockAmount, MINTIME + WEEK);

        // Skip almost to expiry (1 minute remaining)
        skipAndRoll(MINTIME + WEEK - 1 minutes);

        uint256 userBalanceBefore = DUST.balanceOf(user);
        uint256 treasuryBalanceBefore = DUST.balanceOf(user2);

        dustLock.earlyWithdraw(tokenId);

        uint256 userBalanceAfter = DUST.balanceOf(user);
        uint256 treasuryBalanceAfter = DUST.balanceOf(user2);

        uint256 actualPenalty = treasuryBalanceAfter - treasuryBalanceBefore;

        // With only 1 minute remaining out of MINTIME + WEEK, penalty should be very small
        assertTrue(actualPenalty < minLockAmount / 1000); // Less than 0.1% penalty

        emit log_named_uint("[penalty] Edge case penalty", actualPenalty);
        emit log_named_uint("[penalty] Edge case user received", userBalanceAfter - userBalanceBefore);

        // Test zero penalty case (expired lock)
        uint256 tokenId2 = dustLock.createLock(minLockAmount, MINTIME + WEEK);
        skipAndRoll(MINTIME + WEEK + 1);

        uint256 userBalance2Before = DUST.balanceOf(user);
        uint256 treasuryBalance2Before = DUST.balanceOf(user2);

        dustLock.earlyWithdraw(tokenId2);

        uint256 userBalance2After = DUST.balanceOf(user);
        uint256 treasuryBalance2After = DUST.balanceOf(user2);

        // Expired lock should have zero penalty
        assertEq(treasuryBalance2After - treasuryBalance2Before, 0);
        assertEq(userBalance2After - userBalance2Before, minLockAmount);

        emit log("[penalty] Expired lock: zero penalty confirmed");
    }

    /* ============= SYSTEM DISCOUNT ============= */

    function testWeightedAveragePenaltyDiscount() public {
        // Test showing that merged penalty < sum of separate penalties due to weighted averaging
        dustLock.setEarlyWithdrawTreasury(user2);

        // Create initial lock: 1,000,000 DUST, then add 500,000 DUST at halfway point
        mintErc20Token(address(DUST), user, TOKEN_1M + TOKEN_1M / 2);
        DUST.approve(address(dustLock), TOKEN_1M + TOKEN_1M / 2);

        uint256 tokenId = dustLock.createLock(TOKEN_1M, MAXTIME);
        skipAndRoll(MAXTIME / 2);
        dustLock.increaseAmount(tokenId, TOKEN_1M / 2);

        IDustLock.LockedBalance memory lockedBalance = dustLock.locked(tokenId);
        uint256 treasuryBefore = DUST.balanceOf(user2);

        // Calculate what separate penalties would be based on actual values:
        // Old tranche: (1,000,000 * 5,000 * remainingTime) / (10,000 * originalLockTime)
        // New tranche: (500,000 * 5,000 * remainingTime) / (10,000 * remainingTime) = 50% of 500K
        uint256 remainingTime = 32054400 - block.timestamp;
        uint256 oldTranchePenalty = (TOKEN_1M * 5000 * remainingTime) / (BASIS_POINTS * 31449599);
        uint256 newTranchePenalty = TOKEN_1M / 2 / 2; // 50% of 500K DUST
        uint256 expectedSeparatePenalties = oldTranchePenalty + newTranchePenalty;

        dustLock.earlyWithdraw(tokenId);
        uint256 actualPenalty = DUST.balanceOf(user2) - treasuryBefore;

        emit log_named_uint("[discount] Actual penalty", actualPenalty);
        emit log_named_uint("[discount] Separate penalties would be", expectedSeparatePenalties);
        emit log_named_uint("[discount] Weighted start", lockedBalance.effectiveStart);
        emit log_named_uint("[discount] Discount amount", expectedSeparatePenalties - actualPenalty);

        // Verify weighted average penalty is less than separate penalties would be
        assertLt(actualPenalty, expectedSeparatePenalties);
        assertEq(lockedBalance.effectiveStart, 5860801);
    }

    function testTinyLockNoGamingBenefit() public {
        // Test showing that tiny aged locks provide negligible benefit for large deposits
        dustLock.setEarlyWithdrawTreasury(user2);

        // Create tiny lock, age it 300 days, add massive amount
        mintErc20Token(address(DUST), user, TOKEN_1K + TOKEN_1M);
        DUST.approve(address(dustLock), TOKEN_1K + TOKEN_1M);

        uint256 tokenId = dustLock.createLock(TOKEN_1K, MAXTIME);
        skipAndRoll(300 days);
        dustLock.increaseAmount(tokenId, TOKEN_1M);

        IDustLock.LockedBalance memory lockedBalance = dustLock.locked(tokenId);
        uint256 treasuryBefore = DUST.balanceOf(user2);

        dustLock.earlyWithdraw(tokenId);
        uint256 actualPenalty = DUST.balanceOf(user2) - treasuryBefore;

        emit log_named_uint("[gaming] Weighted start", lockedBalance.effectiveStart);
        emit log_named_uint("[gaming] Actual penalty", actualPenalty);
        emit log_named_uint("[gaming] Fresh 1M would pay", TOKEN_1M / 2);
        emit log_named_uint("[gaming] Benefit", TOKEN_1M / 2 - actualPenalty);

        // Verify tiny lock provides negligible gaming benefit
        assertEq(lockedBalance.effectiveStart, 26498906);
        assertEq(actualPenalty, 498167093601397103479906);
        assertLt(TOKEN_1M / 2 - actualPenalty, TOKEN_1M / 500); // <0.2% benefit
    }

    /* ============= REENTRANCY PROTECTION ============= */

    function testReentrancyBlockedOnTransfer() public {
        emit log("[transfer] Approving DUST and creating a lock");
        DUST.approve(address(dustLock), TOKEN_1);
        uint256 tokenId = dustLock.createLock(TOKEN_1, MAXTIME);
        emit log_named_uint("[transfer] Created tokenId", tokenId);

        emit log("[transfer] Deploying malicious reward hook and setting it on DustLock");
        MaliciousRevenueReward impl = new MaliciousRevenueReward(FORWARDER);
        MaliciousRevenueReward malicious = MaliciousRevenueReward(_deployProxy(address(impl)));
        malicious.initialize(FORWARDER, dustLock, address(this), userVaultFactory);
        dustLock.setRevenueReward(malicious);
        emit log_named_address("[transfer] Malicious hook address", address(malicious));

        emit log("[transfer] Approving malicious hook to operate on tokenId");
        dustLock.approve(address(malicious), tokenId);

        emit log("[transfer] Attempting reentrant transfer (should revert)");
        vm.expectRevert("ReentrancyGuard: reentrant call");
        dustLock.transferFrom(user, user2, tokenId);
    }

    function testReentrancyBlockedOnBurn() public {
        emit log("[burn] Approving DUST and creating a lock");
        DUST.approve(address(dustLock), TOKEN_1);
        uint256 tokenId = dustLock.createLock(TOKEN_1, MAXTIME);
        emit log_named_uint("[burn] Created tokenId", tokenId);

        emit log("[burn] Deploying malicious reward hook and setting it on DustLock");
        MaliciousRevenueReward impl = new MaliciousRevenueReward(FORWARDER);
        MaliciousRevenueReward malicious = MaliciousRevenueReward(_deployProxy(address(impl)));
        malicious.initialize(FORWARDER, dustLock, address(this), userVaultFactory);
        dustLock.setRevenueReward(malicious);
        emit log_named_address("[burn] Malicious hook address", address(malicious));

        emit log("[burn] Approving malicious hook to operate on tokenId");
        dustLock.approve(address(malicious), tokenId);

        emit log("[burn] Attempting reentrant earlyWithdraw (should revert)");
        vm.expectRevert("ReentrancyGuard: reentrant call");
        dustLock.earlyWithdraw(tokenId);
    }

    /* ========== TEST SPLIT ========== */

    function testSplittingOfPermanentlyLockedTokenIsReverted() public {
        // arrange
        DUST.approve(address(dustLock), TOKEN_1 * 2);

        uint256 tokenId = dustLock.createLock(TOKEN_1, MAXTIME);
        emit log_named_uint("[dustLock] created tokenId", tokenId);

        dustLock.lockPermanent(tokenId);
        emit log("[dustLock] token locked permanent");

        IDustLock.LockedBalance memory lockedTokenId;
        lockedTokenId = dustLock.locked(tokenId);

        assertTrue(lockedTokenId.isPermanent);

        skipAndRoll(1 weeks);

        dustLock.toggleSplit(user, true);

        // act
        emit log("[dustLock] Expect revert: split permanent lock");
        vm.expectRevert(IDustLock.PermanentLock.selector);
        dustLock.split(tokenId, TOKEN_1 / 2);

        // assert
        assertEq(dustLock.ownerOf(tokenId), address(user));

        lockedTokenId = dustLock.locked(tokenId);
        assertTrue(lockedTokenId.isPermanent);

        assertEq(dustLock.balanceOfNFT(tokenId), TOKEN_1);

        // Verify that no new tokens were created
        assertEq(dustLock.tokenId(), 1);
    }

    /* ========== TWO-STEP TEAM OWNERSHIP TRANSFER TESTS ========== */

    function testTwoStepTeamOwnershipTransfer() public {
        address newTeam = address(0x999);

        // Verify initial state
        assertEq(dustLock.team(), user);
        assertEq(dustLock.pendingTeam(), address(0));

        // Step 1: Current team proposes new team
        dustLock.proposeTeam(newTeam);

        assertEq(dustLock.team(), user);
        assertEq(dustLock.pendingTeam(), newTeam);

        // Step 2: New team accepts ownership
        vm.startPrank(newTeam);
        dustLock.acceptTeam();
        vm.stopPrank();

        // Verify final state
        assertEq(dustLock.team(), newTeam);
        assertEq(dustLock.pendingTeam(), address(0));
    }

    function testTeamOwnershipTransferValidations() public {
        address newTeam = address(0x999);
        address malicious = address(0x666);

        // Test 1: Only current team can propose
        vm.startPrank(malicious);
        emit log("[team] Expect revert: propose by non-team");
        vm.expectRevert(IDustLock.NotTeam.selector);
        dustLock.proposeTeam(newTeam);
        vm.stopPrank();

        // Test 2: Cannot propose zero address
        emit log("[team] Expect revert: propose zero address");
        vm.expectRevert(CommonChecksLibrary.AddressZero.selector);
        dustLock.proposeTeam(address(0));

        // Test 3: Cannot propose same address
        emit log("[team] Expect revert: propose same address");
        vm.expectRevert(CommonChecksLibrary.SameAddress.selector);
        dustLock.proposeTeam(user);

        // Test 4: Valid proposal
        dustLock.proposeTeam(newTeam);

        // Test 5: Only pending team can accept
        emit log("[team] Expect revert: accept by non-pending team");
        vm.expectRevert(IDustLock.NotPendingTeam.selector);
        dustLock.acceptTeam();

        vm.startPrank(malicious);
        emit log("[team] Expect revert: accept by malicious");
        vm.expectRevert(IDustLock.NotPendingTeam.selector);
        dustLock.acceptTeam();
        vm.stopPrank();

        // Test 6: Only current team can cancel
        vm.startPrank(malicious);
        emit log("[team] Expect revert: cancel by non-team");
        vm.expectRevert(IDustLock.NotTeam.selector);
        dustLock.cancelTeamProposal();
        vm.stopPrank();

        vm.startPrank(newTeam);
        emit log("[team] Expect revert: cancel by pending team");
        vm.expectRevert(IDustLock.NotTeam.selector);
        dustLock.cancelTeamProposal();
        vm.stopPrank();
    }

    function testTeamOwnershipTransferCancellation() public {
        address newTeam = address(0x999);

        // Test cancelling when no pending team
        emit log("[team] Expect revert: cancel without pending team");
        vm.expectRevert(CommonChecksLibrary.AddressZero.selector);
        dustLock.cancelTeamProposal();

        // Propose team
        dustLock.proposeTeam(newTeam);
        assertEq(dustLock.pendingTeam(), newTeam);

        // Cancel proposal
        dustLock.cancelTeamProposal();

        assertEq(dustLock.team(), user);
        assertEq(dustLock.pendingTeam(), address(0));

        // Pending team can no longer accept
        vm.startPrank(newTeam);
        emit log("[team] Expect revert: pending team accept after cancel");
        vm.expectRevert(IDustLock.NotPendingTeam.selector);
        dustLock.acceptTeam();
        vm.stopPrank();
    }

    function testTeamOwnershipTransferAdminFunctions() public {
        address newTeam = address(0x999);

        // Complete ownership transfer
        dustLock.proposeTeam(newTeam);
        vm.startPrank(newTeam);
        dustLock.acceptTeam();

        // New team can use admin functions
        dustLock.setMinLockAmount(2 * TOKEN_1);
        assertEq(dustLock.minLockAmount(), 2 * TOKEN_1);

        vm.stopPrank();

        // Old team cannot use admin functions
        emit log("[team] Expect revert: old team cannot set min lock amount");
        vm.expectRevert(IDustLock.NotTeam.selector);
        dustLock.setMinLockAmount(TOKEN_1);
    }

    function testTeamOwnershipTransferSecurityScenario() public {
        address wrongTeam = address(0x111);
        address correctTeam = address(0x999);

        // Scenario: Team accidentally proposes wrong address
        dustLock.proposeTeam(wrongTeam);

        // Team realizes mistake and cancels
        dustLock.cancelTeamProposal();
        assertEq(dustLock.pendingTeam(), address(0));

        // Team proposes correct address
        dustLock.proposeTeam(correctTeam);

        // Wrong team cannot accept (even though they were proposed before)
        vm.startPrank(wrongTeam);
        emit log("[team] Expect revert: wrong team accept");
        vm.expectRevert(IDustLock.NotPendingTeam.selector);
        dustLock.acceptTeam();
        vm.stopPrank();

        // Correct team can accept
        vm.startPrank(correctTeam);
        dustLock.acceptTeam();
        vm.stopPrank();

        assertEq(dustLock.team(), correctTeam);
    }

    /* ========== EDGE CASES & ATTACK SCENARIOS ========== */

    function testTeamOwnershipRaceConditionAttack() public {
        address attacker = address(0x666);
        address legitimateTeam = address(0x999);

        // Team proposes legitimate new team
        dustLock.proposeTeam(legitimateTeam);
        assertEq(dustLock.pendingTeam(), legitimateTeam);

        // Attacker tries to front-run the acceptance by proposing themselves
        vm.startPrank(attacker);
        emit log("[team] Expect revert: attacker propose");
        vm.expectRevert(IDustLock.NotTeam.selector);
        dustLock.proposeTeam(attacker);
        vm.stopPrank();

        // Attacker tries to accept before legitimate team
        vm.startPrank(attacker);
        emit log("[team] Expect revert: attacker accept");
        vm.expectRevert(IDustLock.NotPendingTeam.selector);
        dustLock.acceptTeam();
        vm.stopPrank();

        // Legitimate team can still accept
        vm.startPrank(legitimateTeam);
        dustLock.acceptTeam();
        vm.stopPrank();

        assertEq(dustLock.team(), legitimateTeam);
        assertEq(dustLock.pendingTeam(), address(0));
    }

    function testTeamOwnershipDoubleAcceptanceAttack() public {
        address newTeam = address(0x999);

        // Complete normal flow
        dustLock.proposeTeam(newTeam);
        vm.startPrank(newTeam);
        dustLock.acceptTeam();

        // Try to accept again (should fail)
        vm.expectRevert(IDustLock.NotPendingTeam.selector);
        dustLock.acceptTeam();
        vm.stopPrank();

        // State should remain correct
        assertEq(dustLock.team(), newTeam);
        assertEq(dustLock.pendingTeam(), address(0));
    }

    function testTeamOwnershipProposalOverwriteAttack() public {
        address maliciousTeam = address(0x666);
        address legitimateTeam = address(0x999);

        // Team proposes malicious address
        dustLock.proposeTeam(maliciousTeam);
        assertEq(dustLock.pendingTeam(), maliciousTeam);

        // Team immediately overwrites with legitimate address
        dustLock.proposeTeam(legitimateTeam);
        assertEq(dustLock.pendingTeam(), legitimateTeam);

        // Malicious team can no longer accept
        vm.startPrank(maliciousTeam);
        vm.expectRevert(IDustLock.NotPendingTeam.selector);
        dustLock.acceptTeam();
        vm.stopPrank();

        // Only legitimate team can accept
        vm.startPrank(legitimateTeam);
        dustLock.acceptTeam();
        vm.stopPrank();

        assertEq(dustLock.team(), legitimateTeam);
    }

    function testTeamOwnershipAfterTransferAttacks() public {
        address newTeam = address(0x999);
        address attacker = address(0x666);

        // Complete ownership transfer
        dustLock.proposeTeam(newTeam);
        vm.startPrank(newTeam);
        dustLock.acceptTeam();
        vm.stopPrank();

        // Old team cannot propose new teams
        emit log("[team] Expect revert: old team propose");
        vm.expectRevert(IDustLock.NotTeam.selector);
        dustLock.proposeTeam(attacker);

        // Old team cannot cancel (not team anymore)
        emit log("[team] Expect revert: old team cancel");
        vm.expectRevert(IDustLock.NotTeam.selector);
        dustLock.cancelTeamProposal();

        // Attacker cannot propose
        vm.startPrank(attacker);
        emit log("[team] Expect revert: attacker propose");
        vm.expectRevert(IDustLock.NotTeam.selector);
        dustLock.proposeTeam(attacker);
        vm.stopPrank();

        // Only new team has control
        vm.startPrank(newTeam);
        dustLock.proposeTeam(attacker); // New team can propose anyone
        assertEq(dustLock.pendingTeam(), attacker);
        dustLock.cancelTeamProposal(); // And cancel
        assertEq(dustLock.pendingTeam(), address(0));
        vm.stopPrank();
    }

    function testTeamOwnershipSelfProposalAttack() public {
        // Team tries to propose themselves (should fail)
        emit log("[team] Expect revert: propose self");
        vm.expectRevert(CommonChecksLibrary.SameAddress.selector);
        dustLock.proposeTeam(user);

        // State should remain unchanged
        assertEq(dustLock.team(), user);
        assertEq(dustLock.pendingTeam(), address(0));
    }

    function testTeamOwnershipZeroAddressAttacks() public {
        // Try to propose zero address
        emit log("[team] Expect revert: propose zero address");
        vm.expectRevert(CommonChecksLibrary.AddressZero.selector);
        dustLock.proposeTeam(address(0));

        // State should remain unchanged
        assertEq(dustLock.team(), user);
        assertEq(dustLock.pendingTeam(), address(0));
    }

    function testTeamOwnershipContractAddressEdgeCase() public {
        // Propose the DustLock contract itself as new team
        address contractAsTeam = address(dustLock);

        dustLock.proposeTeam(contractAsTeam);
        assertEq(dustLock.pendingTeam(), contractAsTeam);

        // Contract cannot call acceptTeam (no code to do so)
        // This would require the contract to have acceptTeam logic
        // Let's cancel this dangerous proposal
        dustLock.cancelTeamProposal();
        assertEq(dustLock.pendingTeam(), address(0));
    }

    function testTeamOwnershipMultipleProposalsRapidFire() public {
        address team1 = address(0x111);
        address team2 = address(0x222);
        address team3 = address(0x333);

        // Rapid fire proposals (last one wins)
        dustLock.proposeTeam(team1);
        dustLock.proposeTeam(team2);
        dustLock.proposeTeam(team3);

        assertEq(dustLock.pendingTeam(), team3);

        // Only team3 can accept
        vm.startPrank(team1);
        emit log("[team] Expect revert: team1 accept");
        vm.expectRevert(IDustLock.NotPendingTeam.selector);
        dustLock.acceptTeam();
        vm.stopPrank();

        vm.startPrank(team2);
        emit log("[team] Expect revert: team2 accept");
        vm.expectRevert(IDustLock.NotPendingTeam.selector);
        dustLock.acceptTeam();
        vm.stopPrank();

        vm.startPrank(team3);
        dustLock.acceptTeam();
        vm.stopPrank();

        assertEq(dustLock.team(), team3);
    }

    function testTeamOwnershipCancelAfterAcceptance() public {
        address newTeam = address(0x999);

        // Complete transfer
        dustLock.proposeTeam(newTeam);
        vm.startPrank(newTeam);
        dustLock.acceptTeam();
        vm.stopPrank();

        // Old team tries to cancel (should fail - they're not team anymore)
        vm.expectRevert(IDustLock.NotTeam.selector);
        dustLock.cancelTeamProposal();

        // New team tries to cancel when no pending (should fail)
        vm.startPrank(newTeam);
        vm.expectRevert(CommonChecksLibrary.AddressZero.selector);
        dustLock.cancelTeamProposal();
        vm.stopPrank();
    }

    function testTeamOwnershipReentrancyProtection() public {
        // This tests that the functions are protected against reentrancy
        // The functions modify state before external calls, which is good practice

        address newTeam = address(0x999);
        dustLock.proposeTeam(newTeam);

        // The accept function changes state before emitting events
        // Let's verify state is consistent throughout
        vm.startPrank(newTeam);

        // Before acceptance
        assertEq(dustLock.team(), user);
        assertEq(dustLock.pendingTeam(), newTeam);

        dustLock.acceptTeam();

        // After acceptance - state should be immediately consistent
        assertEq(dustLock.team(), newTeam);
        assertEq(dustLock.pendingTeam(), address(0));

        vm.stopPrank();
    }

    function testTeamOwnershipAdminFunctionsByPendingTeam() public {
        address newTeam = address(0x999);

        // Propose new team
        dustLock.proposeTeam(newTeam);

        // Pending team tries to use admin functions before accepting (should fail)
        vm.startPrank(newTeam);
        vm.expectRevert(IDustLock.NotTeam.selector);
        dustLock.setMinLockAmount(2 * TOKEN_1);

        vm.expectRevert(IDustLock.NotTeam.selector);
        dustLock.proposeTeam(address(0x888));

        vm.expectRevert(IDustLock.NotTeam.selector);
        dustLock.cancelTeamProposal();

        // Now accept
        dustLock.acceptTeam();

        // Now admin functions should work
        dustLock.setMinLockAmount(2 * TOKEN_1);
        assertEq(dustLock.minLockAmount(), 2 * TOKEN_1);

        vm.stopPrank();
    }

    function testTeamOwnershipChainedTransfers() public {
        address team1 = address(0x111);
        address team2 = address(0x222);
        address team3 = address(0x333);

        // Transfer 1: user -> team1
        dustLock.proposeTeam(team1);
        vm.startPrank(team1);
        dustLock.acceptTeam();

        // Transfer 2: team1 -> team2
        dustLock.proposeTeam(team2);
        vm.stopPrank();

        vm.startPrank(team2);
        dustLock.acceptTeam();

        // Transfer 3: team2 -> team3
        dustLock.proposeTeam(team3);
        vm.stopPrank();

        vm.startPrank(team3);
        dustLock.acceptTeam();
        vm.stopPrank();

        // Verify final state
        assertEq(dustLock.team(), team3);
        assertEq(dustLock.pendingTeam(), address(0));

        // Verify old teams have no control
        vm.expectRevert(IDustLock.NotTeam.selector);
        dustLock.proposeTeam(address(0x444));

        vm.startPrank(team1);
        vm.expectRevert(IDustLock.NotTeam.selector);
        dustLock.proposeTeam(address(0x444));
        vm.stopPrank();

        vm.startPrank(team2);
        vm.expectRevert(IDustLock.NotTeam.selector);
        dustLock.proposeTeam(address(0x444));
        vm.stopPrank();
    }

    function testTeamOwnershipGasGriefingResistance() public {
        address newTeam = address(0x999);

        // Test that functions don't consume excessive gas
        // and can't be griefed by gas limit attacks

        uint256 gasBefore = gasleft();
        dustLock.proposeTeam(newTeam);
        uint256 gasAfter = gasleft();
        uint256 gasUsed = gasBefore - gasAfter;

        // Proposal should be very efficient (about 53k)
        assertLt(gasUsed, 60000, "proposeTeam uses too much gas");

        gasBefore = gasleft();
        vm.startPrank(newTeam);
        dustLock.acceptTeam();
        vm.stopPrank();
        gasAfter = gasleft();
        gasUsed = gasBefore - gasAfter;

        // Acceptance should be efficient (less than 50k gas)
        assertLt(gasUsed, 50000, "acceptTeam uses too much gas");
    }

    function testTeamOwnershipProposalToCurrentTeamAfterTransfer() public {
        address newTeam = address(0x999);

        // Complete ownership transfer
        dustLock.proposeTeam(newTeam);
        vm.startPrank(newTeam);
        dustLock.acceptTeam();

        // New team tries to propose themselves (should fail)
        vm.expectRevert(CommonChecksLibrary.SameAddress.selector);
        dustLock.proposeTeam(newTeam);
        vm.stopPrank();
    }

    function testTeamOwnershipPendingTeamCannotProposeOthers() public {
        address pendingTeam = address(0x999);
        address anotherTeam = address(0x888);

        // Propose pending team
        dustLock.proposeTeam(pendingTeam);

        // Pending team tries to propose another team before accepting (should fail)
        vm.startPrank(pendingTeam);
        vm.expectRevert(IDustLock.NotTeam.selector);
        dustLock.proposeTeam(anotherTeam);
        vm.stopPrank();
    }

    function testTeamOwnershipZeroAddressCannotAccept() public {
        // This tests that zero address cannot somehow become pending
        // and then try to accept (should be impossible but let's verify)

        // Propose a legitimate team first
        address legitimateTeam = address(0x999);
        dustLock.proposeTeam(legitimateTeam);

        // Zero address tries to accept (should fail)
        vm.startPrank(address(0));
        vm.expectRevert(IDustLock.NotPendingTeam.selector);
        dustLock.acceptTeam();
        vm.stopPrank();
    }

    function testTeamOwnershipMultipleProposalsSameBatch() public {
        address team1 = address(0x111);
        address team2 = address(0x222);

        // Multiple proposals in same transaction context
        dustLock.proposeTeam(team1);
        // Immediately overwrite
        dustLock.proposeTeam(team2);

        // Only team2 should be able to accept
        vm.startPrank(team1);
        vm.expectRevert(IDustLock.NotPendingTeam.selector);
        dustLock.acceptTeam();
        vm.stopPrank();

        vm.startPrank(team2);
        dustLock.acceptTeam();
        vm.stopPrank();

        assertEq(dustLock.team(), team2);
    }

    function testTeamOwnershipStatePersistenceAfterRevert() public {
        address newTeam = address(0x999);

        // Propose team
        dustLock.proposeTeam(newTeam);
        assertEq(dustLock.pendingTeam(), newTeam);

        // Cause a revert in acceptance (by calling from wrong address)
        vm.startPrank(address(0x666));
        emit log("[team] Expect revert: wrong address accept");
        vm.expectRevert(IDustLock.NotPendingTeam.selector);
        dustLock.acceptTeam();
        vm.stopPrank();

        // State should remain unchanged after revert
        assertEq(dustLock.team(), user);
        assertEq(dustLock.pendingTeam(), newTeam);

        // Legitimate team can still accept
        vm.startPrank(newTeam);
        dustLock.acceptTeam();
        vm.stopPrank();

        assertEq(dustLock.team(), newTeam);
        assertEq(dustLock.pendingTeam(), address(0));
    }

    function testLockStartFieldBehavior() public {
        uint256 initialTimestamp = block.timestamp;

        // Test 1: Lock creation sets start field correctly
        emit log("[startField] Test 1: Lock creation");
        DUST.approve(address(dustLock), TOKEN_1);
        uint256 tokenId = dustLock.createLock(TOKEN_1, MAXTIME);

        IDustLock.LockedBalance memory lockedBalance = dustLock.locked(tokenId);
        emit log_named_uint("[startField] Initial lock start timestamp", lockedBalance.effectiveStart);
        emit log_named_uint("[startField] Initial block timestamp", initialTimestamp);
        assertEq(lockedBalance.effectiveStart, initialTimestamp);

        // Test 2: Amount increase uses weighted average start field
        emit log("[startField] Test 2: Amount increase uses weighted average start");
        skipAndRoll(WEEK);
        uint256 beforeDepositTimestamp = block.timestamp;
        uint256 originalStart = lockedBalance.effectiveStart;

        DUST.approve(address(dustLock), TOKEN_1);
        dustLock.increaseAmount(tokenId, TOKEN_1);

        // Calculate expected weighted average: (1 * originalStart + 1 * beforeDepositTimestamp) / 2
        uint256 expectedWeightedStart =
            (TOKEN_1 * originalStart + TOKEN_1 * beforeDepositTimestamp) / (TOKEN_1 + TOKEN_1);

        lockedBalance = dustLock.locked(tokenId);
        emit log_named_uint("[startField] After deposit start timestamp", lockedBalance.effectiveStart);
        emit log_named_uint("[startField] Expected weighted start", expectedWeightedStart);
        emit log_named_uint("[startField] Before deposit block timestamp", beforeDepositTimestamp);
        assertEq(lockedBalance.effectiveStart, expectedWeightedStart);
        assertEq(lockedBalance.amount, 2e18);

        // Test 3: Time extension preserves start field
        emit log("[startField] Test 3: Time extension preserves start");
        skipAndRoll(WEEK);
        uint256 beforeExtensionTimestamp = block.timestamp;
        uint256 startBeforeExtension = lockedBalance.effectiveStart;
        uint256 currentEndTime = lockedBalance.end;

        dustLock.increaseUnlockTime(tokenId, (currentEndTime + WEEK) - block.timestamp);

        lockedBalance = dustLock.locked(tokenId);
        emit log_named_uint("[startField] After extension start timestamp", lockedBalance.effectiveStart);
        emit log_named_uint("[startField] Start before extension", startBeforeExtension);
        emit log_named_uint("[startField] Current timestamp", beforeExtensionTimestamp);
        assertEq(lockedBalance.effectiveStart, startBeforeExtension); // Should NOT change
        assertTrue(lockedBalance.effectiveStart != beforeExtensionTimestamp); // Confirm it wasn't reset

        // Test 4: Merge uses weighted average to preserve time served
        emit log("[startField] Test 4: Merge uses weighted average");
        DUST.approve(address(dustLock), TOKEN_1);
        uint256 tokenId2 = dustLock.createLock(TOKEN_1, MAXTIME);

        skipAndRoll(WEEK);

        // Get actual effectiveStart values before merge
        IDustLock.LockedBalance memory lock1 = dustLock.locked(tokenId);
        IDustLock.LockedBalance memory lock2 = dustLock.locked(tokenId2);

        // Calculate expected weighted average: (2e18 * lock1Start + 1e18 * lock2Start) / 3e18
        uint256 expectedMergeStart = (2 * lock1.effectiveStart + 1 * lock2.effectiveStart) / 3;

        dustLock.merge(tokenId2, tokenId);

        lockedBalance = dustLock.locked(tokenId);
        emit log_named_uint("[startField] After merge start timestamp", lockedBalance.effectiveStart);
        emit log_named_uint("[startField] Expected weighted start", expectedMergeStart);
        assertEq(lockedBalance.effectiveStart, expectedMergeStart);
        assertEq(lockedBalance.amount, 3e18);

        // Test 5: Permanent lock unlock resets start field
        emit log("[startField] Test 5: Permanent unlock resets start");
        dustLock.lockPermanent(tokenId);

        lockedBalance = dustLock.locked(tokenId);
        assertTrue(lockedBalance.isPermanent);

        skipAndRoll(WEEK);
        uint256 beforeUnlockTimestamp = block.timestamp;

        dustLock.unlockPermanent(tokenId);

        lockedBalance = dustLock.locked(tokenId);
        emit log_named_uint("[startField] After unlock start timestamp", lockedBalance.effectiveStart);
        emit log_named_uint("[startField] Before unlock block timestamp", beforeUnlockTimestamp);
        assertEq(lockedBalance.effectiveStart, beforeUnlockTimestamp);
        assertFalse(lockedBalance.isPermanent);
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
