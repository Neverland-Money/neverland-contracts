// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {DustLockTransferStrategy, IDustLockTransferStrategy, IDustLock} from "../src/emissions/DustLockTransferStrategy.sol";
import "./BaseTest.sol";
import {console2} from "forge-std/console2.sol";

contract DustLockTransferStrategyTest is BaseTest {

    DustLockTransferStrategy public transferStrategy;
    address internal dustVault;
    address internal incentivesController;

    /* ========== SETUP ========== */

    function _setUp() public override {
        // Set IncentivesController mock and DustVault with DUST tokens
        incentivesController = address(0xc1);
        dustVault = address(0xd5);
        vm.label(incentivesController, "incentivesController");
        vm.label(dustVault, "dustVault");

        address[] memory usersTmp = new address[](1);
        usersTmp[0] = dustVault;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = TOKEN_10M;

        mintErc20Token18Dec(address(DUST), usersTmp, amounts);

        // Deploy DustLockTransferStrategy
        transferStrategy = new DustLockTransferStrategy(
            incentivesController,   // incentivesController
            admin,                  // rewardsAdmin
            dustVault,              // dustVault
            address(dustLock)       // dustLock
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
        vm.expectRevert("CALLER_NOT_INCENTIVES_CONTROLLER");
        transferStrategy.performTransfer(
            address(0),         // to
            address(DUST),      // reward
            TOKEN_1,            // amount
            0,                  // lockTime
            0                   // tokenId
        );
    }

    function testPerformTransferWithAddressZero() public {
        vm.prank(incentivesController);
        vm.expectRevert(IDustLockTransferStrategy.AddressZero.selector);
        transferStrategy.performTransfer(
            address(0),         // to
            address(DUST),      // reward
            TOKEN_1,            // amount
            0,                  // lockTime
            0                   // tokenId
        );
    }

    function testPerformTransferWithAmountZero() public {
        uint balanceBefore = DUST.balanceOf(dustVault);

        vm.prank(incentivesController);
        transferStrategy.performTransfer(
            user,         // to
            address(DUST),      // reward
            0,            // amount
            0,                  // lockTime
            0                   // tokenId
        );

        assertEq(DUST.balanceOf(dustVault), balanceBefore);
    }

    function testPerformTransferWithDifferentDustAddress() public {
        vm.prank(incentivesController);
        vm.expectRevert(IDustLockTransferStrategy.InvalidRewardAddress.selector);
        transferStrategy.performTransfer(
            user,               // to
            address(0),         // reward
            TOKEN_1,            // amount
            0,                  // lockTime
            0                   // tokenId
        );

        vm.prank(incentivesController);
        vm.expectRevert(IDustLockTransferStrategy.InvalidRewardAddress.selector);
        transferStrategy.performTransfer(
            user,               // to
            user2,         // reward
            TOKEN_1,            // amount
            0,                  // lockTime
            0                   // tokenId
        );
    }

    function testPerformTransferWithEarlyWithdrawal() public {
        uint256 userDustBefore = DUST.balanceOf(user);
        uint256 vaultDustBefore = DUST.balanceOf(dustVault);
        uint256 adminDustBefore = DUST.balanceOf(admin);

        vm.prank(incentivesController);
        transferStrategy.performTransfer(
            user2,              // to
            address(DUST),      // reward
            TOKEN_1,            // amount
            0,                  // lockTime
            0                   // tokenId
        );

        assertEq(DUST.balanceOf(user2), userDustBefore + (TOKEN_1 / 2));
        assertEq(DUST.balanceOf(dustVault), vaultDustBefore - TOKEN_1);
        assertEq(DUST.balanceOf(user), adminDustBefore + (TOKEN_1 / 2));
    }

    function testPerformTransferWithLessThanMinLockTime() public {
        vm.prank(incentivesController);
        vm.expectRevert(IDustLock.LockDurationTooSort.selector);
        transferStrategy.performTransfer(
            user2,              // to
            address(DUST),      // reward
            TOKEN_1,            // amount
            MINTIME - 1,        // lockTime
            0                   // tokenId
        );
    }

    function testPerformTransferWithMinLockTime() public {
        uint256 vaultDustBefore = DUST.balanceOf(dustVault);

        vm.prank(incentivesController);
        transferStrategy.performTransfer(
            user2,              // to
            address(DUST),      // reward
            TOKEN_1,            // amount
            MINTIME + WEEK,     // lockTime
            0                   // tokenId
        );

        assertEq(DUST.balanceOf(dustVault), vaultDustBefore - TOKEN_1);
        assertEq(dustLock.ownerOf(dustLock.tokenId()), user2);
        IDustLock.LockedBalance memory lockedBalance = dustLock.locked(dustLock.tokenId());
        assertEq(lockedBalance.amount, 1e18);
        // We subtract 1 because of the previous transaction that moved the block.timestamp
        assertEq(lockedBalance.end, block.timestamp - 1 + MINTIME + WEEK);
        assertEq(lockedBalance.isPermanent, false);
    }

    function testPerformTransferWithMaxLockTime() public {
        uint256 vaultDustBefore = DUST.balanceOf(dustVault);

        vm.prank(incentivesController);
        transferStrategy.performTransfer(
            user2,              // to
            address(DUST),      // reward
            TOKEN_1,            // amount
            MAXTIME,            // lockTime
            0                   // tokenId
        );

        assertEq(DUST.balanceOf(dustVault), vaultDustBefore - TOKEN_1);
        assertEq(dustLock.ownerOf(dustLock.tokenId()), user2);
        IDustLock.LockedBalance memory lockedBalance = dustLock.locked(dustLock.tokenId());
        assertEq(lockedBalance.amount, 1e18);
        assertApproxEqAbs(lockedBalance.end, block.timestamp + MAXTIME, WEEK);
        assertEq(lockedBalance.isPermanent, false);
    }

    function testPerformTransferWithMergingTokenId() public {
        uint256 vaultDustBefore = DUST.balanceOf(dustVault);

        vm.prank(incentivesController);
        transferStrategy.performTransfer(
            user2,              // to
            address(DUST),      // reward
            TOKEN_1,            // amount
            MAXTIME,            // lockTime
            0                   // tokenId
        );

        uint256 createLockTokenId = dustLock.tokenId();
        assertEq(dustLock.ownerOf(createLockTokenId), user2);
        IDustLock.LockedBalance memory lockedBalanceFirst = dustLock.locked(createLockTokenId);
        assertEq(lockedBalanceFirst.amount, 1e18);
        assertApproxEqAbs(lockedBalanceFirst.end, block.timestamp + MAXTIME, WEEK);
        assertEq(lockedBalanceFirst.isPermanent, false);

        vm.prank(incentivesController);
        transferStrategy.performTransfer(
            user2,              // to
            address(DUST),      // reward
            TOKEN_1,            // amount
            0,                  // lockTime
            createLockTokenId  // tokenId
        );

        assertEq(DUST.balanceOf(dustVault), vaultDustBefore - (2 * TOKEN_1));
        IDustLock.LockedBalance memory lockedBalanceSecond = dustLock.locked(createLockTokenId);
        assertEq(lockedBalanceSecond.amount, 2e18);
        assertEq(lockedBalanceFirst.end, lockedBalanceSecond.end);
        assertEq(lockedBalanceSecond.isPermanent, false);
    }

    function testPerformTransferWithMergingNonExistingTokenId() public {
        vm.prank(incentivesController);
        transferStrategy.performTransfer(
            user2,              // to
            address(DUST),      // reward
            TOKEN_1,            // amount
            MAXTIME,            // lockTime
            0                   // tokenId
        );

        uint256 createLockTokenId = dustLock.tokenId();
        vm.prank(incentivesController);
        vm.expectRevert(IDustLockTransferStrategy.InvalidTokenId.selector);
        transferStrategy.performTransfer(
            user2,              // to
            address(DUST),      // reward
            TOKEN_1,            // amount
            0,                  // lockTime
            createLockTokenId + 1  // tokenId
        );
    }
}