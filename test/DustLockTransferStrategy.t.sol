// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {
    DustLockTransferStrategy,
    IDustLockTransferStrategy,
    IDustLock
} from "../src/emissions/DustLockTransferStrategy.sol";
import {IDustTransferStrategy} from "../src/interfaces/IDustTransferStrategy.sol";

import {CommonChecksLibrary} from "../src/libraries/CommonChecksLibrary.sol";

import "./BaseTest.sol";

contract DustLockTransferStrategyTest is BaseTest {
    DustLockTransferStrategy public transferStrategy;
    address internal dustVault;
    address internal incentivesController;

    /* ========== SETUP ========== */

    function _setUp() internal override {
        // Set IncentivesController mock and DustVault with DUST tokens
        incentivesController = address(0xc1);
        dustVault = address(0xd5);
        vm.label(incentivesController, "incentivesController");
        vm.label(dustVault, "dustVault");

        address[] memory usersTmp = new address[](1);
        usersTmp[0] = dustVault;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = TOKEN_10M;

        mintErc20Tokens(address(DUST), usersTmp, amounts);

        // Deploy DustLockTransferStrategy
        transferStrategy = new DustLockTransferStrategy(
            incentivesController, // incentivesController
            admin, // rewardsAdmin
            dustVault, // dustVault
            address(dustLock) // dustLock
        );

        // Give 1M token allowance to mint veDUST
        vm.prank(dustVault);
        DUST.approve(address(transferStrategy), TOKEN_1M);
    }

    /* ========== TEST SETUP ========== */

    function testSetup() public view {
        assertEq(transferStrategy.getDustVault(), dustVault);
        assertEq(transferStrategy.getRewardsAdmin(), admin);
        assertEq(transferStrategy.getIncentivesController(), incentivesController);
        assertEq(address(transferStrategy.DUST_LOCK()), address(dustLock));
        assertEq(transferStrategy.DUST_VAULT(), dustVault);
        assertEq(address(transferStrategy.DUST()), address(DUST));
        assertEq(DUST.allowance(dustVault, address(transferStrategy)), TOKEN_1M);
    }

    /* ========== TEST PERFORM TRANSFER ========== */

    function testPerformTransferWithNotIncentivesControllerAsCaller() public {
        vm.prank(user);
        emit log("[transferStrategy] Expect revert: caller not incentivesController");
        vm.expectRevert(IDustTransferStrategy.CallerNotIncentivesController.selector);
        transferStrategy.performTransfer(
            address(0), // to
            address(DUST), // reward
            TOKEN_1, // amount
            0, // lockTime
            0 // tokenId
        );
    }

    function testPerformTransferWithAddressZero() public {
        vm.prank(incentivesController);
        emit log("[transferStrategy] Expect revert: recipient address zero");
        vm.expectRevert(CommonChecksLibrary.InvalidToAddress.selector);
        transferStrategy.performTransfer(
            address(0), // to
            address(DUST), // reward
            TOKEN_1, // amount
            0, // lockTime
            0 // tokenId
        );
    }

    function testPerformTransferWithAmountZero() public {
        uint256 balanceBefore = DUST.balanceOf(dustVault);

        vm.prank(incentivesController);
        transferStrategy.performTransfer(
            user, // to
            address(DUST), // reward
            0, // amount
            0, // lockTime
            0 // tokenId
        );

        emit log_named_uint("[transferStrategy] Vault balance unchanged", DUST.balanceOf(dustVault));
        assertEq(DUST.balanceOf(dustVault), balanceBefore);
    }

    function testPerformTransferWithDifferentDustAddress() public {
        vm.prank(incentivesController);
        emit log("[transferStrategy] Expect revert: invalid reward address (zero)");
        vm.expectRevert(IDustLockTransferStrategy.InvalidRewardAddress.selector);
        transferStrategy.performTransfer(
            user, // to
            address(0), // reward
            TOKEN_1, // amount
            0, // lockTime
            0 // tokenId
        );

        vm.prank(incentivesController);
        emit log("[transferStrategy] Expect revert: invalid reward address (random)");
        vm.expectRevert(IDustLockTransferStrategy.InvalidRewardAddress.selector);
        transferStrategy.performTransfer(
            user, // to
            user2, // reward
            TOKEN_1, // amount
            0, // lockTime
            0 // tokenId
        );
    }

    function testPerformTransferWithEarlyWithdrawal() public {
        uint256 userDustBefore = DUST.balanceOf(user);
        uint256 vaultDustBefore = DUST.balanceOf(dustVault);
        uint256 adminDustBefore = DUST.balanceOf(admin);

        vm.prank(incentivesController);
        transferStrategy.performTransfer(
            user2, // to
            address(DUST), // reward
            TOKEN_1, // amount
            0, // lockTime
            0 // tokenId
        );

        emit log_named_uint("[transferStrategy] user2 received", DUST.balanceOf(user2) - userDustBefore);
        emit log_named_uint("[transferStrategy] admin received", DUST.balanceOf(user) - adminDustBefore);
        emit log_named_uint("[transferStrategy] vault spent", vaultDustBefore - DUST.balanceOf(dustVault));
        assertEq(DUST.balanceOf(user2), userDustBefore + (TOKEN_1 / 2));
        assertEq(DUST.balanceOf(dustVault), vaultDustBefore - TOKEN_1);
        assertEq(DUST.balanceOf(user), adminDustBefore + (TOKEN_1 / 2));
    }

    function testPerformTransferWithLessThanMinLockTime() public {
        vm.prank(incentivesController);
        emit log("[transferStrategy] Expect revert: lock time too short");
        vm.expectRevert(IDustLock.LockDurationTooShort.selector);
        transferStrategy.performTransfer(
            user2, // to
            address(DUST), // reward
            TOKEN_1, // amount
            MINTIME - 1, // lockTime
            0 // tokenId
        );
    }

    function testPerformTransferWithMinLockTime() public {
        uint256 vaultDustBefore = DUST.balanceOf(dustVault);

        vm.prank(incentivesController);
        transferStrategy.performTransfer(
            user2, // to
            address(DUST), // reward
            TOKEN_1, // amount
            MINTIME + WEEK, // lockTime
            0 // tokenId
        );

        emit log_named_uint("[transferStrategy] created tokenId", dustLock.tokenId());
        assertEq(DUST.balanceOf(dustVault), vaultDustBefore - TOKEN_1);
        assertEq(dustLock.ownerOf(dustLock.tokenId()), user2);
        IDustLock.LockedBalance memory lockedBalance = dustLock.locked(dustLock.tokenId());
        emit log_named_uint("[transferStrategy] lock end", lockedBalance.end);
        assertEq(lockedBalance.amount, 1e18);
        // We subtract 1 because of the previous transaction that moved the block.timestamp
        assertEq(lockedBalance.end, block.timestamp - 1 + MINTIME + WEEK);
        assertEq(lockedBalance.isPermanent, false);
    }

    function testPerformTransferWithMaxLockTime() public {
        uint256 vaultDustBefore = DUST.balanceOf(dustVault);

        vm.prank(incentivesController);
        transferStrategy.performTransfer(
            user2, // to
            address(DUST), // reward
            TOKEN_1, // amount
            MAXTIME, // lockTime
            0 // tokenId
        );

        emit log_named_uint("[transferStrategy] created tokenId", dustLock.tokenId());
        assertEq(DUST.balanceOf(dustVault), vaultDustBefore - TOKEN_1);
        assertEq(dustLock.ownerOf(dustLock.tokenId()), user2);
        IDustLock.LockedBalance memory lockedBalance = dustLock.locked(dustLock.tokenId());
        emit log_named_uint("[transferStrategy] lock end", lockedBalance.end);
        assertEq(lockedBalance.amount, 1e18);
        assertApproxEqAbs(lockedBalance.end, block.timestamp + MAXTIME, WEEK);
        assertEq(lockedBalance.isPermanent, false);
    }

    function testPerformTransferWithMergingTokenId() public {
        uint256 vaultDustBefore = DUST.balanceOf(dustVault);

        vm.prank(incentivesController);
        transferStrategy.performTransfer(
            user2, // to
            address(DUST), // reward
            TOKEN_1, // amount
            MAXTIME, // lockTime
            0 // tokenId
        );

        uint256 createLockTokenId = dustLock.tokenId();
        emit log_named_uint("[transferStrategy] created tokenId", createLockTokenId);
        assertEq(dustLock.ownerOf(createLockTokenId), user2);
        IDustLock.LockedBalance memory lockedBalanceFirst = dustLock.locked(createLockTokenId);
        emit log_named_uint("[transferStrategy] initial locked amount", uint256(lockedBalanceFirst.amount));
        assertEq(lockedBalanceFirst.amount, 1e18);
        assertApproxEqAbs(lockedBalanceFirst.end, block.timestamp + MAXTIME, WEEK);
        assertEq(lockedBalanceFirst.isPermanent, false);

        vm.prank(incentivesController);
        transferStrategy.performTransfer(
            user2, // to
            address(DUST), // reward
            TOKEN_1, // amount
            0, // lockTime
            createLockTokenId // tokenId
        );

        assertEq(DUST.balanceOf(dustVault), vaultDustBefore - (2 * TOKEN_1));
        IDustLock.LockedBalance memory lockedBalanceSecond = dustLock.locked(createLockTokenId);
        emit log_named_uint("[transferStrategy] merged locked amount", uint256(lockedBalanceSecond.amount));
        assertEq(lockedBalanceSecond.amount, 2e18);
        assertEq(lockedBalanceFirst.end, lockedBalanceSecond.end);
        assertEq(lockedBalanceSecond.isPermanent, false);
    }

    function testPerformTransferWithMergingNonExistingTokenId() public {
        vm.prank(incentivesController);
        transferStrategy.performTransfer(
            user2, // to
            address(DUST), // reward
            TOKEN_1, // amount
            MAXTIME, // lockTime
            0 // tokenId
        );

        uint256 createLockTokenId = dustLock.tokenId();
        vm.prank(incentivesController);
        emit log("[transferStrategy] Expect revert: merging non-existing tokenId");
        vm.expectRevert(CommonChecksLibrary.InvalidTokenId.selector);
        transferStrategy.performTransfer(
            user2, // to
            address(DUST), // reward
            TOKEN_1, // amount
            0, // lockTime
            createLockTokenId + 1 // tokenId
        );
    }

    function testPerformTransferWithMergingNTokenIdOfDIfferentUser() public {
        vm.prank(dustVault);
        DUST.approve(address(dustLock), TOKEN_1);
        vm.prank(dustVault);
        uint256 tokenId = dustLock.createLock(TOKEN_1, MAXTIME);

        address ownerOfTOkenId = dustLock.ownerOf(tokenId);
        assertEq(ownerOfTOkenId, dustVault);

        // SHould pass
        vm.prank(incentivesController);
        emit log("[transferStrategy] depositFor to owner tokenId (should pass)");
        transferStrategy.performTransfer(
            dustVault, // to
            address(DUST), // reward
            TOKEN_1, // amount
            0, // lockTime
            tokenId // tokenId
        );

        // Should fail
        vm.prank(incentivesController);
        emit log("[transferStrategy] Expect revert: depositFor to non-owner tokenId");
        vm.expectRevert(IDustLockTransferStrategy.NotTokenOwner.selector);
        transferStrategy.performTransfer(
            user2, // to
            address(DUST), // reward
            TOKEN_1, // amount
            0, // lockTime
            tokenId // tokenId
        );
    }

    function testPerformTransferRepeatedCreateLockResetsAllowance() public {
        emit log("[createLock] First performTransfer call (create lock)");
        vm.prank(incentivesController);
        transferStrategy.performTransfer(
            user2, // to
            address(DUST), // reward
            TOKEN_1, // amount
            MAXTIME, // lockTime
            0 // tokenId
        );

        emit log_named_uint(
            "[createLock] Allowance after first call", DUST.allowance(address(transferStrategy), address(dustLock))
        );
        assertEq(DUST.allowance(address(transferStrategy), address(dustLock)), 0);

        emit log("[createLock] Second performTransfer call (create lock again)");
        vm.prank(incentivesController);
        transferStrategy.performTransfer(
            user3, // to
            address(DUST), // reward
            TOKEN_1, // amount
            MAXTIME, // lockTime
            0 // tokenId
        );

        emit log_named_uint(
            "[createLock] Allowance after second call", DUST.allowance(address(transferStrategy), address(dustLock))
        );
        assertEq(DUST.allowance(address(transferStrategy), address(dustLock)), 0);
    }

    function testPerformTransferRepeatedDepositForResetsAllowance() public {
        emit log("[depositFor] Initial performTransfer call (create lock)");
        vm.prank(incentivesController);
        transferStrategy.performTransfer(
            user2, // to
            address(DUST), // reward
            TOKEN_1, // amount
            MAXTIME, // lockTime
            0 // tokenId
        );

        uint256 tokenId = dustLock.tokenId();
        emit log_named_uint("[depositFor] Created tokenId", tokenId);

        emit log("[depositFor] First performTransfer call (depositFor)");
        vm.prank(incentivesController);
        transferStrategy.performTransfer(
            user2, // to
            address(DUST), // reward
            TOKEN_1, // amount
            0, // lockTime
            tokenId // tokenId
        );

        emit log_named_uint(
            "[depositFor] Allowance after first depositFor",
            DUST.allowance(address(transferStrategy), address(dustLock))
        );
        assertEq(DUST.allowance(address(transferStrategy), address(dustLock)), 0);

        emit log("[depositFor] Second performTransfer call (depositFor)");
        vm.prank(incentivesController);
        transferStrategy.performTransfer(
            user2, // to
            address(DUST), // reward
            TOKEN_1, // amount
            0, // lockTime
            tokenId // tokenId
        );

        emit log_named_uint(
            "[depositFor] Allowance after second depositFor",
            DUST.allowance(address(transferStrategy), address(dustLock))
        );
        assertEq(DUST.allowance(address(transferStrategy), address(dustLock)), 0);

        IDustLock.LockedBalance memory lockedBalance = dustLock.locked(tokenId);
        emit log_named_uint("[depositFor] Final locked amount", uint256(lockedBalance.amount));
        assertEq(lockedBalance.amount, 3e18);
    }
}
