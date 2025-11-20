// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "./LeaderboardBase.sol";
import {LeaderboardKeeper} from "../../../src/leaderboard/LeaderboardKeeper.sol";
import {ILeaderboardKeeper} from "../../../src/interfaces/ILeaderboardKeeper.sol";

contract LeaderboardKeeperTest is LeaderboardBase {
    LeaderboardKeeper public keeper;

    address public keeperBot = makeAddr("keeperBot");

    function setUp() public override {
        super.setUp();

        // Deploy LeaderboardKeeper
        keeper = new LeaderboardKeeper(admin, keeperBot, 3600, makeAddr("random1"), makeAddr("random2")); // 1 hour interval
    }

    /*//////////////////////////////////////////////////////////////
                           INITIALIZATION TESTS
      //////////////////////////////////////////////////////////////*/

    function testInitialConfiguration() public view {
        assertEq(keeper.keeper(), keeperBot, "Initial keeper address");
        assertEq(keeper.minSettlementInterval(), 3600, "Initial interval");
        assertEq(keeper.owner(), admin, "Initial owner");
        assertEq(keeper.MAX_CORRECTION_BATCH(), 100, "Max correction batch");
        assertEq(keeper.MAX_SETTLEMENT_BATCH(), 200, "Max settlement batch");
    }

    function testConstructorZeroAddressOwner() public {
        vm.expectRevert();
        new LeaderboardKeeper(ZERO_ADDRESS, keeperBot, 3600, ZERO_ADDRESS, ZERO_ADDRESS);
    }

    function testConstructorZeroAddressKeeper() public {
        vm.expectRevert();
        new LeaderboardKeeper(admin, ZERO_ADDRESS, 3600, ZERO_ADDRESS, ZERO_ADDRESS);
    }

    /*//////////////////////////////////////////////////////////////
                      BATCH VERIFY AND SETTLE TESTS
      //////////////////////////////////////////////////////////////*/

    function testBatchVerifyAndSettle() public {
        address[] memory users = new address[](2);
        users[0] = user1;
        users[1] = user2;

        ILeaderboardKeeper.UserState[] memory states = new ILeaderboardKeeper.UserState[](2);
        states[0] =
            ILeaderboardKeeper.UserState({votingPower: 1000e18, nftCollectionCount: 3, timestamp: block.timestamp});
        states[1] =
            ILeaderboardKeeper.UserState({votingPower: 2000e18, nftCollectionCount: 5, timestamp: block.timestamp});

        vm.prank(keeperBot);
        keeper.batchVerifyAndSettle(users, states);

        assertEq(keeper.lastSettlement(user1), block.timestamp, "User1 settlement time");
        assertEq(keeper.lastSettlement(user2), block.timestamp, "User2 settlement time");
    }

    function testBatchVerifyAndSettleEmitsEvents() public {
        address[] memory users = new address[](1);
        users[0] = user1;

        ILeaderboardKeeper.UserState[] memory states = new ILeaderboardKeeper.UserState[](1);
        states[0] =
            ILeaderboardKeeper.UserState({votingPower: 1000e18, nftCollectionCount: 3, timestamp: block.timestamp});

        vm.expectEmit(true, true, true, true);
        emit ILeaderboardKeeper.StateVerified(user1, 1000e18, 3, block.timestamp, "Keeper verification");

        vm.expectEmit(true, true, true, true);
        emit ILeaderboardKeeper.UserSettled(user1, block.timestamp, true);

        vm.expectEmit(true, true, true, true);
        emit ILeaderboardKeeper.BatchSettlementComplete(1, 1, block.timestamp);

        vm.prank(keeperBot);
        keeper.batchVerifyAndSettle(users, states);
    }

    function testBatchVerifyAndSettleArrayLengthMismatch() public {
        address[] memory users = new address[](2);
        users[0] = user1;
        users[1] = user2;

        ILeaderboardKeeper.UserState[] memory states = new ILeaderboardKeeper.UserState[](1);
        states[0] =
            ILeaderboardKeeper.UserState({votingPower: 1000e18, nftCollectionCount: 3, timestamp: block.timestamp});

        vm.prank(keeperBot);
        vm.expectRevert(abi.encodeWithSelector(ILeaderboardKeeper.ArrayLengthMismatch.selector, 2, 1));
        keeper.batchVerifyAndSettle(users, states);
    }

    function testBatchVerifyAndSettleBatchTooLarge() public {
        address[] memory users = new address[](101);
        ILeaderboardKeeper.UserState[] memory states = new ILeaderboardKeeper.UserState[](101);

        vm.prank(keeperBot);
        vm.expectRevert(abi.encodeWithSelector(ILeaderboardKeeper.BatchTooLarge.selector, 101, 100));
        keeper.batchVerifyAndSettle(users, states);
    }

    function testBatchVerifyAndSettleOnlyKeeper() public {
        address[] memory users = new address[](1);
        users[0] = user1;

        ILeaderboardKeeper.UserState[] memory states = new ILeaderboardKeeper.UserState[](1);
        states[0] =
            ILeaderboardKeeper.UserState({votingPower: 1000e18, nftCollectionCount: 3, timestamp: block.timestamp});

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(ILeaderboardKeeper.NotKeeper.selector, user1));
        keeper.batchVerifyAndSettle(users, states);
    }

    function testBatchVerifyAndSettleOwnerCanCall() public {
        address[] memory users = new address[](1);
        users[0] = user1;

        ILeaderboardKeeper.UserState[] memory states = new ILeaderboardKeeper.UserState[](1);
        states[0] =
            ILeaderboardKeeper.UserState({votingPower: 1000e18, nftCollectionCount: 3, timestamp: block.timestamp});

        vm.prank(admin);
        keeper.batchVerifyAndSettle(users, states);

        assertEq(keeper.lastSettlement(user1), block.timestamp, "User1 settlement time");
    }

    /*//////////////////////////////////////////////////////////////
                      BATCH SETTLE ACCURATE TESTS
      //////////////////////////////////////////////////////////////*/

    function testBatchSettleAccurate() public {
        address[] memory users = new address[](2);
        users[0] = user1;
        users[1] = user2;

        vm.prank(keeperBot);
        keeper.batchSettleAccurate(users);

        assertEq(keeper.lastSettlement(user1), block.timestamp, "User1 settlement time");
        assertEq(keeper.lastSettlement(user2), block.timestamp, "User2 settlement time");
    }

    function testBatchSettleAccurateSkipsRecentlySettled() public {
        address[] memory users = new address[](1);
        users[0] = user1;

        // First settlement
        vm.prank(keeperBot);
        keeper.batchSettleAccurate(users);

        uint256 firstSettlement = keeper.lastSettlement(user1);
        assertEq(firstSettlement, block.timestamp, "First settlement");

        // Try to settle again immediately (should skip)
        vm.prank(keeperBot);
        keeper.batchSettleAccurate(users);

        // Last settlement should be unchanged
        assertEq(keeper.lastSettlement(user1), firstSettlement, "Settlement unchanged");
    }

    function testBatchSettleAccurateAfterInterval() public {
        address[] memory users = new address[](1);
        users[0] = user1;

        // First settlement
        vm.prank(keeperBot);
        keeper.batchSettleAccurate(users);

        // Wait for interval to pass
        vm.warp(block.timestamp + 3601);

        // Second settlement should succeed
        vm.prank(keeperBot);
        keeper.batchSettleAccurate(users);

        assertEq(keeper.lastSettlement(user1), block.timestamp, "Settlement updated");
    }

    function testBatchSettleAccurateBatchTooLarge() public {
        address[] memory users = new address[](201);

        vm.prank(keeperBot);
        vm.expectRevert(abi.encodeWithSelector(ILeaderboardKeeper.BatchTooLarge.selector, 201, 200));
        keeper.batchSettleAccurate(users);
    }

    function testBatchSettleAccurateEmitsEvents() public {
        address[] memory users = new address[](1);
        users[0] = user1;

        vm.expectEmit(true, true, true, true);
        emit ILeaderboardKeeper.UserSettled(user1, block.timestamp, false);

        vm.expectEmit(true, true, true, true);
        emit ILeaderboardKeeper.BatchSettlementComplete(1, 0, block.timestamp);

        vm.prank(keeperBot);
        keeper.batchSettleAccurate(users);
    }

    /*//////////////////////////////////////////////////////////////
                         EMERGENCY SETTLE TESTS
      //////////////////////////////////////////////////////////////*/

    function testEmergencySettle() public {
        vm.prank(admin);
        keeper.emergencySettle(user1);

        assertEq(keeper.lastSettlement(user1), block.timestamp, "Settlement time");
    }

    function testEmergencySettleZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert();
        keeper.emergencySettle(address(0));
    }

    function testEmergencySettleOnlyOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        keeper.emergencySettle(user2);
    }

    function testEmergencySettleEmitsEvent() public {
        vm.expectEmit(true, true, true, true);
        emit ILeaderboardKeeper.UserSettled(user1, block.timestamp, false);

        vm.prank(admin);
        keeper.emergencySettle(user1);
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN TESTS
      //////////////////////////////////////////////////////////////*/

    function testSetKeeper() public {
        address newKeeper = makeAddr("newKeeper");

        vm.prank(admin);
        keeper.setKeeper(newKeeper);

        assertEq(keeper.keeper(), newKeeper, "Keeper updated");
    }

    function testSetKeeperEmitsEvent() public {
        address newKeeper = makeAddr("newKeeper");

        vm.expectEmit(true, true, true, true);
        emit ILeaderboardKeeper.KeeperUpdated(keeperBot, newKeeper);

        vm.prank(admin);
        keeper.setKeeper(newKeeper);
    }

    function testSetKeeperZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert();
        keeper.setKeeper(address(0));
    }

    function testSetKeeperOnlyOwner() public {
        address newKeeper = makeAddr("newKeeper");

        vm.prank(user1);
        vm.expectRevert();
        keeper.setKeeper(newKeeper);
    }

    function testSetMinSettlementInterval() public {
        uint256 newInterval = 7200; // 2 hours

        vm.prank(admin);
        keeper.setMinSettlementInterval(newInterval);

        assertEq(keeper.minSettlementInterval(), newInterval, "Interval updated");
    }

    function testSetMinSettlementIntervalEmitsEvent() public {
        uint256 newInterval = 7200;

        vm.expectEmit(true, true, true, true);
        emit ILeaderboardKeeper.MinSettlementIntervalUpdated(3600, newInterval);

        vm.prank(admin);
        keeper.setMinSettlementInterval(newInterval);
    }

    function testSetMinSettlementIntervalOnlyOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        keeper.setMinSettlementInterval(7200);
    }
}
