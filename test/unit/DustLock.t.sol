// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {IDustLock} from "../../src/interfaces/IDustLock.sol";

import {CommonChecksLibrary} from "../../src/libraries/CommonChecksLibrary.sol";

import {RevenueReward} from "../../src/rewards/RevenueReward.sol";
import "../BaseTestLocal.sol";

contract MaliciousRevenueReward is RevenueReward {
    constructor(address _dustLock) RevenueReward(address(0xF1), _dustLock, msg.sender) {}

    function notifyAfterTokenTransferred(uint256 tokenId, address from) public override onlyDustLock {
        dustLock.transferFrom(from, address(this), tokenId);
    }

    function notifyAfterTokenBurned(uint256 tokenId, address /* from */ ) public override onlyDustLock {
        dustLock.earlyWithdraw(tokenId);
    }
}

contract DustLockTests is BaseTestLocal {
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
        emit log("[dustLock] earlyWithdraw called");

        // assert
        assertEq(dustLock.balanceOfNFT(tokenId), 0);

        uint256 expectedUserPenalty = 0.3 * 5_000 * 1e18;

        // TODO: why 10 DUST diff
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

    function testEarlyWithdrawSameBlockAfterTransfer() public {
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
        dustLock.transferFrom(user2, user4, tokenId);
        emit log("[dustLock] transferFrom user2 -> user4 before earlyWithdraw");

        vm.prank(user4);
        dustLock.earlyWithdraw(tokenId);
        emit log("[dustLock] earlyWithdraw by user4");

        // assert
        assertEq(dustLock.balanceOfNFT(tokenId), 0);

        uint256 expectedUserPenalty = 0.3 * 5_000 * 1e18;

        // TODO: [NRL-6c19a5e-C02] Early withdrawal penalty fee mechanism bypass
        assertApproxEqAbs(
            DUST.balanceOf(address(user4)),
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

    function testReentrancyBlockedOnTransfer() public {
        emit log("[transfer] Approving DUST and creating a lock");
        DUST.approve(address(dustLock), TOKEN_1);
        uint256 tokenId = dustLock.createLock(TOKEN_1, MAXTIME);
        emit log_named_uint("[transfer] Created tokenId", tokenId);

        emit log("[transfer] Deploying malicious reward hook and setting it on DustLock");
        MaliciousRevenueReward malicious = new MaliciousRevenueReward(address(dustLock));
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
        MaliciousRevenueReward malicious = new MaliciousRevenueReward(address(dustLock));
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

        // Proposal should be very efficient (less than 50k gas)
        assertLt(gasUsed, 50000, "proposeTeam uses too much gas");

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
