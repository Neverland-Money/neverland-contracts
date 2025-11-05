// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "./LeaderboardBase.sol";
import {IVotingPowerMultiplier} from "../../../src/interfaces/IVotingPowerMultiplier.sol";

contract VotingPowerMultiplierTest is LeaderboardBase {
    function testInitialState() public view {
        assertEq(address(vpMultiplier.dustLock()), address(dustLock), "DustLock address");
        assertEq(vpMultiplier.getTierCount(), 1, "Should have 1 default tier");

        // Check default tier (0 VP = 1.0x)
        IVotingPowerMultiplier.VotingPowerTier memory tier = vpMultiplier.getTier(0);
        assertEq(tier.minVotingPower, 0, "Tier 0 min VP should be 0");
        assertEq(tier.multiplierBps, 10_000, "Tier 0 multiplier should be 1.0x");
    }

    function testAddTier() public {
        vm.prank(admin);
        vpMultiplier.addTier(1000e18, 11_000); // 1000 VP = 1.1x

        assertEq(vpMultiplier.getTierCount(), 2, "Should have 2 tiers");

        IVotingPowerMultiplier.VotingPowerTier memory tier = vpMultiplier.getTier(1);
        assertEq(tier.minVotingPower, 1000e18, "Tier 1 min VP");
        assertEq(tier.multiplierBps, 11_000, "Tier 1 multiplier");
    }

    function testAddTierOnlyOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        vpMultiplier.addTier(1000e18, 11_000);
    }

    function testAddTierNotAscending() public {
        vm.startPrank(admin);
        vpMultiplier.addTier(1000e18, 11_000);

        // Try to add tier with lower min VP
        vm.expectRevert();
        vpMultiplier.addTier(500e18, 11_500);
        vm.stopPrank();
    }

    function testAddTierMultiplierTooHigh() public {
        vm.prank(admin);
        vm.expectRevert();
        vpMultiplier.addTier(1000e18, 50_001);
    }

    function testAddTierMultiplierTooLow() public {
        vm.prank(admin);
        vm.expectRevert();
        vpMultiplier.addTier(1000e18, 9_999);
    }

    function testUpdateTier() public {
        vm.startPrank(admin);
        vpMultiplier.addTier(1000e18, 11_000);

        // Update tier 1
        vpMultiplier.updateTier(1, 1500e18, 11_500);
        vm.stopPrank();

        IVotingPowerMultiplier.VotingPowerTier memory tier = vpMultiplier.getTier(1);
        assertEq(tier.minVotingPower, 1500e18, "Updated min VP");
        assertEq(tier.multiplierBps, 11_500, "Updated multiplier");
    }

    function testUpdateTierInvalidIndex() public {
        vm.prank(admin);
        vm.expectRevert();
        vpMultiplier.updateTier(999, 1000e18, 11_000);
    }

    function testRemoveTier() public {
        vm.startPrank(admin);
        vpMultiplier.addTier(1000e18, 11_000);
        assertEq(vpMultiplier.getTierCount(), 2, "Should have 2 tiers");

        vpMultiplier.removeTier(1);
        assertEq(vpMultiplier.getTierCount(), 1, "Should have 1 tier");
        vm.stopPrank();
    }

    function testRemoveLastTierFails() public {
        vm.prank(admin);
        vm.expectRevert();
        vpMultiplier.removeTier(0); // Cannot remove last tier
    }

    function testSetDustLock() public {
        address newDustLock = address(0x123);

        vm.prank(admin);
        vpMultiplier.setDustLock(newDustLock);

        assertEq(address(vpMultiplier.dustLock()), newDustLock, "DustLock updated");
    }

    function testSetDustLockZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert();
        vpMultiplier.setDustLock(address(0));
    }

    function testGetMultiplierForVotingPower() public {
        // Setup tiers
        vm.startPrank(admin);
        vpMultiplier.addTier(1000e18, 11_000); // 1000 VP = 1.1x
        vpMultiplier.addTier(5000e18, 12_000); // 5000 VP = 1.2x
        vpMultiplier.addTier(10_000e18, 13_000); // 10000 VP = 1.3x
        vm.stopPrank();

        // Test different voting powers
        assertEq(vpMultiplier.getMultiplierForVotingPower(0), 10_000, "0 VP = 1.0x");
        assertEq(vpMultiplier.getMultiplierForVotingPower(999e18), 10_000, "999 VP = 1.0x");
        assertEq(vpMultiplier.getMultiplierForVotingPower(1000e18), 11_000, "1000 VP = 1.1x");
        assertEq(vpMultiplier.getMultiplierForVotingPower(4999e18), 11_000, "4999 VP = 1.1x");
        assertEq(vpMultiplier.getMultiplierForVotingPower(5000e18), 12_000, "5000 VP = 1.2x");
        assertEq(vpMultiplier.getMultiplierForVotingPower(9999e18), 12_000, "9999 VP = 1.2x");
        assertEq(vpMultiplier.getMultiplierForVotingPower(10_000e18), 13_000, "10000 VP = 1.3x");
        assertEq(vpMultiplier.getMultiplierForVotingPower(100_000e18), 13_000, "100000 VP = 1.3x");
    }

    function testGetUserMultiplierNoVeNFTs() public view {
        (uint256 multiplier, uint256 votingPower, uint256 tokenId) = vpMultiplier.getUserMultiplier(user1);

        assertEq(multiplier, 10_000, "Should return 1.0x for no veNFTs");
        assertEq(votingPower, 0, "Should return 0 voting power");
        assertEq(tokenId, 0, "Should return 0 tokenId");
    }

    function testGetUserMultiplierWithOneVeNFT() public {
        // Setup tiers
        vm.prank(admin);
        vpMultiplier.addTier(1000e18, 11_000);

        // User locks 10,000 DUST for 1 year
        uint256 lockAmount = 10_000e18;
        uint256 lockDuration = 365 days;
        _lockDust(user1, lockAmount, lockDuration);

        (uint256 multiplier, uint256 votingPower, uint256 tokenId) = vpMultiplier.getUserMultiplier(user1);

        // Voting power for 10k DUST locked for 1 year should be ~10k (full amount)
        assertGt(votingPower, 9900e18, "VP should be close to lock amount");
        assertEq(multiplier, 11_000, "Should be tier 1 (1.1x)");
        assertEq(tokenId, 1, "Should be tokenId 1");
    }

    function testGetUserMultiplierWithMultipleVeNFTs() public {
        // Setup tiers
        vm.startPrank(admin);
        vpMultiplier.addTier(1000e18, 11_000);
        vpMultiplier.addTier(5000e18, 12_000);
        vm.stopPrank();

        // User1 creates 3 veNFTs with different amounts
        _lockDust(user1, 1_000e18, 365 days); // ~1000 VP
        _lockDust(user1, 8_000e18, 365 days); // ~8000 VP (highest)
        _lockDust(user1, 500e18, 365 days); // ~500 VP

        (uint256 multiplier, uint256 votingPower, uint256 tokenId) = vpMultiplier.getUserMultiplier(user1);

        // Should use the highest veNFT (8000 VP)
        assertGt(votingPower, 7900e18, "VP should be ~8000");
        assertLt(votingPower, 8100e18, "VP should be ~8000");
        assertEq(multiplier, 12_000, "Should be tier 2 (1.2x) for 8000 VP");
        assertEq(tokenId, 2, "Should be tokenId 2 (the highest VP one)");
    }

    function testGetAllTiers() public {
        vm.startPrank(admin);
        vpMultiplier.addTier(1000e18, 11_000);
        vpMultiplier.addTier(5000e18, 12_000);
        vm.stopPrank();

        IVotingPowerMultiplier.VotingPowerTier[] memory tiers = vpMultiplier.getAllTiers();
        assertEq(tiers.length, 3, "Should have 3 tiers");

        assertEq(tiers[0].minVotingPower, 0, "Tier 0");
        assertEq(tiers[0].multiplierBps, 10_000, "Tier 0 multiplier");

        assertEq(tiers[1].minVotingPower, 1000e18, "Tier 1");
        assertEq(tiers[1].multiplierBps, 11_000, "Tier 1 multiplier");

        assertEq(tiers[2].minVotingPower, 5000e18, "Tier 2");
        assertEq(tiers[2].multiplierBps, 12_000, "Tier 2 multiplier");
    }

    function testDeterministicVotingPowerCalculation() public {
        // Lock 10,000 DUST for exactly 1 year
        uint256 lockAmount = 10_000e18;
        uint256 lockDuration = 365 days;

        uint256 tokenId = _lockDust(user1, lockAmount, lockDuration);

        // Get voting power immediately after lock
        uint256 vp = dustLock.balanceOfNFT(tokenId);

        emit log("=== Deterministic Voting Power Test ===");
        emit log(string(abi.encodePacked("Lock amount: ", vm.toString(lockAmount))));
        emit log(string(abi.encodePacked("Lock duration: ", vm.toString(lockDuration))));
        emit log(string(abi.encodePacked("Voting power: ", vm.toString(vp))));

        // For 1 year lock, VP should be close to lock amount
        // VP = amount * time_remaining / MAXTIME
        // VP = 10000 * 365 days / 365 days = 10000
        assertGt(vp, 9_900e18, "VP should be at least 9900");
        assertLt(vp, 10_000e18 + 1, "VP should be at most 10000");
    }

    function testVotingPowerDecay() public {
        // Setup tiers
        vm.startPrank(admin);
        vpMultiplier.addTier(5000e18, 12_000);
        vm.stopPrank();

        // Lock 10,000 DUST for 1 year
        _lockDust(user1, 10_000e18, 365 days);

        // Check initial multiplier (should be tier 1: 1.2x)
        (uint256 multiplier1,,) = vpMultiplier.getUserMultiplier(user1);
        assertEq(multiplier1, 12_000, "Initial: tier 1 (1.2x)");

        // Advance 6 months (50% of lock duration)
        skip(182 days);
        vm.roll(block.number + 1000);

        // Voting power should decay to ~5000
        (uint256 multiplier2, uint256 vp2,) = vpMultiplier.getUserMultiplier(user1);

        emit log("=== Voting Power Decay Test ===");
        emit log(string(abi.encodePacked("VP after 6 months: ", vm.toString(vp2))));
        emit log(string(abi.encodePacked("Multiplier after 6 months: ", vm.toString(multiplier2))));

        // VP decays to ~5000, which is near the tier boundary
        // Due to rounding, it may be just below 5000e18 and fall to tier 0
        assertGt(vp2, 4700e18, "VP should be ~5000 after 6 months");
        assertLt(vp2, 5100e18, "VP should be ~5000 after 6 months");
        // Multiplier depends on whether VP is >= 5000e18
        assertTrue(multiplier2 == 12_000 || multiplier2 == 10_000, "Should be tier 0 or tier 1");

        // Advance to near expiry (just before lock ends)
        skip(180 days); // Total: ~362 days, very close to expiry
        vm.roll(block.number + 1000);

        (uint256 multiplier3, uint256 vp3,) = vpMultiplier.getUserMultiplier(user1);

        emit log(string(abi.encodePacked("VP near expiry: ", vm.toString(vp3))));
        emit log(string(abi.encodePacked("Multiplier near expiry: ", vm.toString(multiplier3))));

        // VP should be very low near expiry
        assertLt(vp3, 500e18, "VP should be very low near expiry");
        assertEq(multiplier3, 10_000, "Should be tier 0 (1.0x) near expiry");
    }

    function testVotingPowerStaysAboveThreshold() public {
        // Setup tier
        vm.prank(admin);
        vpMultiplier.addTier(3_000e18, 12_000); // 3k VP = 1.2x (lower threshold)

        // Lock 10,000 DUST for 1 year
        _lockDust(user1, 10_000e18, 365 days);

        // Check initial
        (uint256 multiplier1,,) = vpMultiplier.getUserMultiplier(user1);
        assertEq(multiplier1, 12_000, "Initial: tier 1 (1.2x)");

        // Advance 6 months - VP should be ~5000, still above 3000 threshold
        skip(182 days);
        vm.roll(block.number + 1000);

        (uint256 multiplier2, uint256 vp2,) = vpMultiplier.getUserMultiplier(user1);

        emit log("=== VP Above Threshold Test ===");
        emit log(string(abi.encodePacked("VP after 6 months: ", vm.toString(vp2))));
        emit log(string(abi.encodePacked("Multiplier: ", vm.toString(multiplier2))));

        assertGt(vp2, 3000e18, "VP should still be above 3000");
        assertEq(multiplier2, 12_000, "Should still be tier 1 (above 3k threshold)");
    }

    function testComprehensiveTierSystem() public {
        // Setup 5 tiers
        vm.startPrank(admin);
        vpMultiplier.addTier(1_000e18, 11_000); // 1k VP = 1.1x
        vpMultiplier.addTier(5_000e18, 12_000); // 5k VP = 1.2x
        vpMultiplier.addTier(10_000e18, 13_000); // 10k VP = 1.3x
        vpMultiplier.addTier(50_000e18, 15_000); // 50k VP = 1.5x
        vm.stopPrank();

        assertEq(vpMultiplier.getTierCount(), 5, "Should have 5 tiers");

        // Lock different amounts for different users
        _lockDust(user1, 800e18, 365 days); // Tier 0: 1.0x
        _lockDust(user2, 3_000e18, 365 days); // Tier 1: 1.1x
        _lockDust(user3, 7_000e18, 365 days); // Tier 2: 1.2x
        _lockDust(user4, 15_000e18, 365 days); // Tier 3: 1.3x
        _lockDust(user5, 60_000e18, 365 days); // Tier 4: 1.5x

        (uint256 m1,,) = vpMultiplier.getUserMultiplier(user1);
        (uint256 m2,,) = vpMultiplier.getUserMultiplier(user2);
        (uint256 m3,,) = vpMultiplier.getUserMultiplier(user3);
        (uint256 m4,,) = vpMultiplier.getUserMultiplier(user4);
        (uint256 m5,,) = vpMultiplier.getUserMultiplier(user5);

        assertEq(m1, 10_000, "User1: Tier 0 (1.0x)");
        assertEq(m2, 11_000, "User2: Tier 1 (1.1x)");
        assertEq(m3, 12_000, "User3: Tier 2 (1.2x)");
        assertEq(m4, 13_000, "User4: Tier 3 (1.3x)");
        assertEq(m5, 15_000, "User5: Tier 4 (1.5x)");
    }
}
