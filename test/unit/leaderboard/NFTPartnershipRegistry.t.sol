// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "./LeaderboardBase.sol";
import {INFTPartnershipRegistry} from "../../../src/interfaces/INFTPartnershipRegistry.sol";

contract NFTPartnershipRegistryTest is LeaderboardBase {
    function testInitialState() public view {
        assertEq(nftRegistry.firstBonus(), FIRST_BONUS, "Initial first bonus");
        assertEq(nftRegistry.decayRatio(), DECAY_RATIO, "Initial decay ratio");
        assertEq(nftRegistry.getPartnershipCount(), 0, "Should have no partnerships");
    }

    function testAddPartnership() public {
        uint256 startTime = block.timestamp;
        uint256 endTime = startTime + 30 days;

        vm.prank(admin);
        nftRegistry.addPartnership(address(nftCollection1), "Collection1", startTime, endTime);

        assertEq(nftRegistry.getPartnershipCount(), 1, "Should have 1 partnership");

        INFTPartnershipRegistry.Partnership memory p = nftRegistry.getPartnership(address(nftCollection1));
        assertEq(p.collection, address(nftCollection1), "Collection address");
        assertEq(p.name, "Collection1", "Collection name");
        assertTrue(p.active, "Should be active");
        assertEq(p.startTimestamp, startTime, "Start timestamp");
        assertEq(p.endTimestamp, endTime, "End timestamp");
    }

    function testAddPartnershipWithNoEndDate() public {
        uint256 startTime = block.timestamp;

        vm.prank(admin);
        nftRegistry.addPartnership(address(nftCollection1), "Collection1", startTime, 0);

        INFTPartnershipRegistry.Partnership memory p = nftRegistry.getPartnership(address(nftCollection1));
        assertEq(p.endTimestamp, 0, "Should have no end date");
    }

    function testAddPartnershipOnlyOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        nftRegistry.addPartnership(address(nftCollection1), "Collection1", block.timestamp, 0);
    }

    function testAddPartnershipAlreadyExists() public {
        vm.startPrank(admin);
        nftRegistry.addPartnership(address(nftCollection1), "Collection1", block.timestamp, 0);

        vm.expectRevert();
        nftRegistry.addPartnership(address(nftCollection1), "Collection1 Again", block.timestamp, 0);
        vm.stopPrank();
    }

    function testAddPartnershipInvalidTimestamp() public {
        uint256 startTime = block.timestamp;
        uint256 invalidEndTime = startTime - 1; // End before start

        vm.prank(admin);
        vm.expectRevert();
        nftRegistry.addPartnership(address(nftCollection1), "Collection1", startTime, invalidEndTime);
    }

    function testAddPartnershipZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert();
        nftRegistry.addPartnership(address(0), "Collection1", block.timestamp, 0);
    }

    function testUpdatePartnership() public {
        // Add partnership
        vm.startPrank(admin);
        nftRegistry.addPartnership(address(nftCollection1), "Collection1", block.timestamp, 0);

        // Update to inactive
        nftRegistry.updatePartnership(address(nftCollection1), false);
        vm.stopPrank();

        INFTPartnershipRegistry.Partnership memory p = nftRegistry.getPartnership(address(nftCollection1));
        assertFalse(p.active, "Should be inactive");
    }

    function testUpdatePartnershipNotFound() public {
        vm.prank(admin);
        vm.expectRevert();
        nftRegistry.updatePartnership(address(nftCollection1), false);
    }

    function testRemovePartnership() public {
        // Add partnership
        vm.startPrank(admin);
        nftRegistry.addPartnership(address(nftCollection1), "Collection1", block.timestamp, 0);
        assertEq(nftRegistry.getPartnershipCount(), 1, "Should have 1 partnership");

        // Remove partnership
        nftRegistry.removePartnership(address(nftCollection1));
        vm.stopPrank();

        assertEq(nftRegistry.getPartnershipCount(), 0, "Should have 0 partnerships");

        // Trying to get removed partnership should revert
        vm.expectRevert();
        nftRegistry.getPartnership(address(nftCollection1));
    }

    function testRemovePartnershipNotFound() public {
        vm.prank(admin);
        vm.expectRevert();
        nftRegistry.removePartnership(address(nftCollection1));
    }

    function testGetActivePartnerships() public {
        vm.startPrank(admin);

        // Add 3 partnerships
        nftRegistry.addPartnership(address(nftCollection1), "Collection1", block.timestamp, 0);
        nftRegistry.addPartnership(address(nftCollection2), "Collection2", block.timestamp, 0);
        nftRegistry.addPartnership(address(nftCollection3), "Collection3", block.timestamp, 0);

        // Deactivate one
        nftRegistry.updatePartnership(address(nftCollection2), false);

        vm.stopPrank();

        address[] memory active = nftRegistry.getActivePartnerships();
        assertEq(active.length, 2, "Should have 2 active partnerships");

        // Check that collection2 is not in the list
        bool foundCollection2 = false;
        for (uint256 i = 0; i < active.length; i++) {
            if (active[i] == address(nftCollection2)) {
                foundCollection2 = true;
            }
        }
        assertFalse(foundCollection2, "Collection2 should not be in active list");
    }

    function testSetMultiplierParams() public {
        uint256 newFirstBonus = 2000; // 0.2
        uint256 newDecayRatio = 8500; // 0.85

        vm.prank(admin);
        nftRegistry.setMultiplierParams(newFirstBonus, newDecayRatio);

        assertEq(nftRegistry.firstBonus(), newFirstBonus, "First bonus updated");
        assertEq(nftRegistry.decayRatio(), newDecayRatio, "Decay ratio updated");
    }

    function testSetMultiplierParamsInvalidFirstBonus() public {
        vm.prank(admin);
        vm.expectRevert();
        nftRegistry.setMultiplierParams(10_001, 9000); // Too high
    }

    function testSetMultiplierParamsInvalidDecayRatio() public {
        vm.prank(admin);
        vm.expectRevert();
        nftRegistry.setMultiplierParams(1000, 10_000); // Too high (would cause division by zero)
    }

    function testDeterministicMultiplierCalculation() public {
        // Set specific parameters
        vm.prank(admin);
        nftRegistry.setMultiplierParams(1000, 9000); // first_bonus=0.1, decay_ratio=0.9

        // Formula: 1 + first_bonus × (1 - decay_ratio^n) / (1 - decay_ratio)
        // n=0: 1.0x (baseline)
        // n=1: 1 + 0.1 × (1 - 0.9) / (1 - 0.9) = 1 + 0.1 × 0.1/0.1 = 1 + 0.1 = 1.1x = 11000 bps
        // n=2: 1 + 0.1 × (1 - 0.81) / 0.1 = 1 + 0.1 × 1.9 = 1.19x = 11900 bps
        // n=3: 1 + 0.1 × (1 - 0.729) / 0.1 = 1 + 0.1 × 2.71 = 1.271x = 12710 bps

        // These calculations should be verified in the subgraph tests
        emit log("Multiplier params set for deterministic calculations");
        emit log(string(abi.encodePacked("First bonus: ", vm.toString(nftRegistry.firstBonus()))));
        emit log(string(abi.encodePacked("Decay ratio: ", vm.toString(nftRegistry.decayRatio()))));
    }

    function testMultiplePartnershipsWithDifferentStates() public {
        vm.startPrank(admin);

        // Active permanent partnership
        nftRegistry.addPartnership(address(nftCollection1), "Collection1", block.timestamp, 0);

        // Active temporary partnership
        nftRegistry.addPartnership(address(nftCollection2), "Collection2", block.timestamp, block.timestamp + 30 days);

        // Inactive partnership
        nftRegistry.addPartnership(address(nftCollection3), "Collection3", block.timestamp, 0);
        nftRegistry.updatePartnership(address(nftCollection3), false);

        vm.stopPrank();

        assertEq(nftRegistry.getPartnershipCount(), 3, "Should have 3 total partnerships");

        address[] memory active = nftRegistry.getActivePartnerships();
        assertEq(active.length, 2, "Should have 2 active partnerships");

        // Verify individual partnerships
        INFTPartnershipRegistry.Partnership memory p1 = nftRegistry.getPartnership(address(nftCollection1));
        assertTrue(p1.active, "Collection1 should be active");
        assertEq(p1.endTimestamp, 0, "Collection1 has no end date");

        INFTPartnershipRegistry.Partnership memory p2 = nftRegistry.getPartnership(address(nftCollection2));
        assertTrue(p2.active, "Collection2 should be active");
        assertGt(p2.endTimestamp, 0, "Collection2 has end date");

        INFTPartnershipRegistry.Partnership memory p3 = nftRegistry.getPartnership(address(nftCollection3));
        assertFalse(p3.active, "Collection3 should be inactive");
    }

    function testPartnershipLifecycle() public {
        uint256 startTime = block.timestamp;
        uint256 endTime = startTime + 30 days;

        vm.startPrank(admin);

        // 1. Add partnership
        nftRegistry.addPartnership(address(nftCollection1), "Collection1", startTime, endTime);
        assertEq(nftRegistry.getPartnershipCount(), 1, "Should have 1 partnership");

        // 2. Update to inactive
        nftRegistry.updatePartnership(address(nftCollection1), false);
        INFTPartnershipRegistry.Partnership memory p = nftRegistry.getPartnership(address(nftCollection1));
        assertFalse(p.active, "Should be inactive");

        // 3. Reactivate
        nftRegistry.updatePartnership(address(nftCollection1), true);
        p = nftRegistry.getPartnership(address(nftCollection1));
        assertTrue(p.active, "Should be active again");

        // 4. Remove
        nftRegistry.removePartnership(address(nftCollection1));
        assertEq(nftRegistry.getPartnershipCount(), 0, "Should have 0 partnerships");

        vm.stopPrank();
    }
}
