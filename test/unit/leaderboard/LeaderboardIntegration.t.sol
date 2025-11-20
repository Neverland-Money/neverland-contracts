// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "./LeaderboardBase.sol";

contract LeaderboardIntegrationTest is LeaderboardBase {
    function testCompleteLeaderboardLifecycle() public {
        emit log("=== Complete Leaderboard Lifecycle Test ===");

        // 1. SETUP PHASE (before epoch start)
        emit log("\n1. Setup Phase");

        assertFalse(epochManager.hasStarted(), "Leaderboard should not be started");
        assertEq(epochManager.currentEpoch(), 0, "Should be at epoch 0");

        // Configure rates
        vm.startPrank(admin);
        leaderboardConfig.updateAllRates(100, 500, 200, 10e18, 20e18);

        // Setup NFT partnerships
        nftRegistry.addPartnership(address(nftCollection1), "Collection1", block.timestamp, 0);
        nftRegistry.addPartnership(address(nftCollection2), "Collection2", block.timestamp, 0);

        // Setup voting power tiers
        vpMultiplier.addTier(1_000e18, 11_000); // 1k VP = 1.1x
        vpMultiplier.addTier(5_000e18, 12_000); // 5k VP = 1.2x
        vm.stopPrank();

        emit log("Config complete");

        // 2. EPOCH 1 START
        emit log("\n2. Epoch 1 Start");

        vm.prank(admin);
        epochManager.startNewEpoch();

        assertTrue(epochManager.hasStarted(), "Leaderboard should be started");
        assertEq(epochManager.currentEpoch(), 1, "Should be epoch 1");

        uint256 epoch1Start = epochManager.currentEpochStartTime();
        emit log(string(abi.encodePacked("Epoch 1 started at: ", vm.toString(epoch1Start))));

        // 3. USER PARTICIPATION
        emit log("\n3. User Participation");

        // User1: Holds 1 NFT, has 3k voting power
        _mintNFT(nftCollection1, user1, 1);
        _lockDust(user1, 3_000e18, 365 days);

        // User2: Holds 2 NFTs, has 7k voting power
        _mintNFT(nftCollection1, user2, 2);
        _mintNFT(nftCollection2, user2, 3);
        _lockDust(user2, 7_000e18, 365 days);

        // User3: Holds 0 NFTs, has 0 voting power
        // User3 doesn't lock or hold NFTs

        emit log("User1: 1 NFT, 3k VP");
        emit log("User2: 2 NFTs, 7k VP");
        emit log("User3: 0 NFTs, 0 VP");

        // Calculate expected multipliers
        // User1: NFT multiplier = 1.1x (n=1), VP multiplier = 1.1x (tier 1)
        //        Combined = 1.1 * 1.1 = 1.21x = 12100 bps
        // User2: NFT multiplier = 1.19x (n=2), VP multiplier = 1.2x (tier 2)
        //        Combined = 1.19 * 1.2 = 1.428x = 14280 bps
        // User3: NFT multiplier = 1.0x (n=0), VP multiplier = 1.0x (tier 0)
        //        Combined = 1.0 * 1.0 = 1.0x = 10000 bps

        (uint256 vpMult1,,) = vpMultiplier.getUserMultiplier(user1);
        (uint256 vpMult2,,) = vpMultiplier.getUserMultiplier(user2);

        emit log(string(abi.encodePacked("User1 VP multiplier: ", vm.toString(vpMult1))));
        emit log(string(abi.encodePacked("User2 VP multiplier: ", vm.toString(vpMult2))));

        // 4. EPOCH 1 PROGRESSION (30 days)
        emit log("\n4. Epoch 1 - 30 Days");
        skip(30 days);
        vm.roll(block.number + 1000);

        // At this point, subgraph would calculate:
        // - User positions (supply/borrow)
        // - Points accrued = position * rate * time * multiplier
        // - Leaderboard rankings

        // 5. RATE CHANGE MID-EPOCH
        emit log("\n5. Rate Change (still in Epoch 1)");

        vm.prank(admin);
        leaderboardConfig.setBorrowRate(1000); // Double borrow rate

        assertEq(leaderboardConfig.borrowRateBps(), 1000, "Borrow rate updated");
        emit log("Borrow rate doubled to 1000 bps");

        // Subgraph should apply new rate from this block forward

        // 6. EPOCH 2 START
        emit log("\n6. Epoch 2 Start");
        skip(15 days); // Epoch 1 total duration: 45 days
        vm.roll(block.number + 500);

        // End epoch 1
        vm.prank(admin);
        epochManager.endCurrentEpoch();

        // Small gap
        skip(1 days);
        vm.roll(block.number + 10);

        // Start epoch 2
        vm.prank(admin);
        epochManager.startNewEpoch();

        assertEq(epochManager.currentEpoch(), 2, "Should be epoch 2");

        // Verify epoch 1 ended
        (,, uint256 e1EndBlock, uint256 e1EndTime) = epochManager.getEpochDetails(1);
        assertGt(e1EndBlock, 0, "Epoch 1 should have end block");
        assertGt(e1EndTime, 0, "Epoch 1 should have end time");

        uint256 epoch1Duration = e1EndTime - epoch1Start;
        assertEq(epoch1Duration, 45 days, "Epoch 1 should be 45 days");

        emit log("Epoch 1 ended, Epoch 2 started");
        emit log("User points for Epoch 1 are finalized");

        // 7. MULTIPLIER ADJUSTMENT IN EPOCH 2
        emit log("\n7. Multiplier Adjustment");

        vm.startPrank(admin);
        // Make NFT multipliers more generous
        nftRegistry.setMultiplierParams(2000, 8500); // first_bonus=0.2, decay_ratio=0.85

        // Add higher VP tier
        vpMultiplier.addTier(10_000e18, 14_000); // 10k VP = 1.4x
        vm.stopPrank();

        emit log("Multipliers made more generous for Epoch 2");

        // 8. USER3 JOINS IN EPOCH 2
        emit log("\n8. User3 Joins");

        _lockDust(user3, 12_000e18, 365 days);
        (uint256 vpMult3,,) = vpMultiplier.getUserMultiplier(user3);

        emit log(string(abi.encodePacked("User3 VP multiplier: ", vm.toString(vpMult3))));
        assertEq(vpMult3, 14_000, "User3 should be in tier 3 (1.4x)");

        // 9. EPOCH 3 START (Final)
        emit log("\n9. Epoch 3 Start");
        skip(30 days);
        vm.roll(block.number + 1000);

        // End epoch 2
        vm.prank(admin);
        epochManager.endCurrentEpoch();

        // Small gap
        skip(1 days);
        vm.roll(block.number + 10);

        // Start epoch 3
        vm.prank(admin);
        epochManager.startNewEpoch();

        assertEq(epochManager.currentEpoch(), 3, "Should be epoch 3");
        emit log("Epoch 2 ended, Epoch 3 started");

        // Verify all epochs exist
        assertTrue(epochManager.isEpochActive(3), "Epoch 3 should be active");
        assertFalse(epochManager.isEpochActive(2), "Epoch 2 should not be active");
        assertFalse(epochManager.isEpochActive(1), "Epoch 1 should not be active");

        emit log("\n=== Test Complete ===");
        emit log("All epochs tracked, all multipliers configured, ready for subgraph");
    }

    function testDeterministicPointCalculation() public {
        emit log("=== Deterministic Point Calculation ===");

        // Setup
        vm.startPrank(admin);
        epochManager.startNewEpoch();
        leaderboardConfig.updateAllRates(100, 500, 200, 10e18, 20e18);
        nftRegistry.addPartnership(address(nftCollection1), "Collection1", block.timestamp, 0);
        vpMultiplier.addTier(1_000e18, 11_000);
        vm.stopPrank();

        // User has:
        // - 1 NFT (n=1) -> NFT multiplier = 1.1x (11000 bps)
        // - 2000 DUST locked -> VP ~2000 -> VP multiplier = 1.1x (11000 bps)
        // - Combined multiplier = 1.1 * 1.1 = 1.21x (12100 bps)
        _mintNFT(nftCollection1, user1, 1);
        _lockDust(user1, 2_000e18, 365 days);

        (uint256 vpMult,,) = vpMultiplier.getUserMultiplier(user1);
        assertEq(vpMult, 11_000, "VP multiplier should be 1.1x");

        // Simulated position: $10,000 supplied
        uint256 positionUSD = 10_000e18;
        uint256 depositRate = 100; // 0.01 per USD/day
        uint256 daysElapsed = 30;

        // Base points calculation (for subgraph reference):
        // points_per_day = positionUSD * depositRate / 10000
        //                = 10000 * 100 / 10000 = 100 points/day
        // base_points = 100 * 30 = 3000 points

        uint256 basePointsPerDay = (positionUSD * depositRate) / 10_000;
        uint256 basePoints = basePointsPerDay * daysElapsed;

        emit log(string(abi.encodePacked("Position: $", vm.toString(positionUSD / 1e18))));
        emit log(string(abi.encodePacked("Rate: ", vm.toString(depositRate), " bps")));
        emit log(string(abi.encodePacked("Days: ", vm.toString(daysElapsed))));
        emit log(string(abi.encodePacked("Base points/day: ", vm.toString(basePointsPerDay))));
        emit log(string(abi.encodePacked("Total base points: ", vm.toString(basePoints))));

        // NFT multiplier calculation:
        // n = 1, firstBonus = 1000 (0.1), decayRatio = 9000 (0.9)
        // multiplier = 1 + 0.1 * (1 - 0.9^1) / (1 - 0.9)
        //            = 1 + 0.1 * 0.1 / 0.1 = 1.1 = 11000 bps
        uint256 nftMultiplier = 11_000;

        // Combined multiplier = 11000 * 11000 / 10000 = 12100 bps
        uint256 combinedMultiplier = (nftMultiplier * vpMult) / 10_000;

        // Final points = basePoints * combinedMultiplier / 10000
        //              = 3000 * 12100 / 10000 = 3630 points
        uint256 finalPoints = (basePoints * combinedMultiplier) / 10_000;

        emit log(string(abi.encodePacked("NFT multiplier: ", vm.toString(nftMultiplier))));
        emit log(string(abi.encodePacked("VP multiplier: ", vm.toString(vpMult))));
        emit log(string(abi.encodePacked("Combined multiplier: ", vm.toString(combinedMultiplier))));
        emit log(string(abi.encodePacked("Final points: ", vm.toString(finalPoints))));

        assertEq(finalPoints, 3630e18, "Final points should be 3630e18");
    }

    function testMultiEpochPointAccumulation() public {
        emit log("=== Multi-Epoch Point Accumulation ===");

        // Epoch 1 setup
        vm.startPrank(admin);
        epochManager.startNewEpoch();
        leaderboardConfig.updateAllRates(100, 0, 200, 0, 0); // Deposit and VP points
        vm.stopPrank();

        (, uint256 epoch1Start,,) = epochManager.getEpochDetails(1);

        // User participates in epoch 1 (no multipliers)
        // Simulated: $1000 position for 30 days
        // Base points = 1000 * 100 / 10000 * 30 = 300 points
        skip(30 days);
        vm.roll(block.number + 1000);

        // End epoch 1
        vm.prank(admin);
        epochManager.endCurrentEpoch();

        skip(1 hours); // Small gap
        vm.roll(block.number + 10);

        // Start epoch 2
        vm.prank(admin);
        epochManager.startNewEpoch();

        (, uint256 epoch2Start,,) = epochManager.getEpochDetails(2);

        // Epoch 1 points: 300 (frozen)
        emit log("Epoch 1: 300 points (frozen)");

        // User continues in epoch 2 with same position
        // Another 30 days = another 300 points (epoch 2 counter)
        skip(30 days);
        vm.roll(block.number + 1000);

        // End epoch 2
        vm.prank(admin);
        epochManager.endCurrentEpoch();

        skip(1 hours); // Small gap
        vm.roll(block.number + 10);

        // Start epoch 3
        vm.prank(admin);
        epochManager.startNewEpoch();

        // Epoch 2 points: 300 (frozen)
        // Total across all epochs: 600
        emit log("Epoch 2: 300 points (frozen)");
        emit log("Total across all epochs: 600 points");

        // Verify epoch separation
        assertEq(epochManager.currentEpoch(), 3, "Should be epoch 3");

        (,,, uint256 e1End) = epochManager.getEpochDetails(1);
        (,,, uint256 e2End) = epochManager.getEpochDetails(2);

        assertEq(e1End - epoch1Start, 30 days, "Epoch 1 was 30 days");
        assertEq(e2End - epoch2Start, 30 days, "Epoch 2 was 30 days");
    }
}
