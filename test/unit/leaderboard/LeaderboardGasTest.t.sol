// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {LeaderboardConfig} from "../../../src/leaderboard/LeaderboardConfig.sol";

contract LeaderboardGasTest is Test {
    LeaderboardConfig public leaderboard;
    address public owner = address(this);

    function setUp() public {
        leaderboard = new LeaderboardConfig(
            owner,
            100, // depositRateBps
            500, // borrowRateBps
            200, // vpRateBps
            10e18, // supplyDailyBonus
            20e18, // borrowDailyBonus
            0, // repayDailyBonus
            0, // withdrawDailyBonus
            3600, // cooldownSeconds
            0 // minDailyBonusUsd
        );
    }

    function testGasBatchAwardPoints() public {
        uint256[] memory sizes = new uint256[](6);
        sizes[0] = 10;
        sizes[1] = 50;
        sizes[2] = 100;
        sizes[3] = 500;
        sizes[4] = 1000;
        sizes[5] = 5000;

        for (uint256 s = 0; s < sizes.length; s++) {
            uint256 batchSize = sizes[s];
            address[] memory users = new address[](batchSize);
            uint256[] memory points = new uint256[](batchSize);

            for (uint256 i = 0; i < batchSize; i++) {
                users[i] = address(uint160(i + 1));
                points[i] = 100e18;
            }

            uint256 gasBefore = gasleft();
            leaderboard.batchAwardPoints(users, points, "Gas test batch");
            uint256 gasUsed = gasBefore - gasleft();

            uint256 gasPerUser = batchSize > 0 ? gasUsed / batchSize : 0;

            console.log("Batch size:", batchSize);
            console.log("  Total gas:", gasUsed);
            console.log("  Gas per user:", gasPerUser);
            console.log("  Estimated max users @ 30M gas:", 30_000_000 / gasPerUser);
            console.log("");
        }
    }
}
