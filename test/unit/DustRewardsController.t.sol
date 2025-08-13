// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IDustRewardsController} from "../../src/interfaces/IDustRewardsController.sol";

import {DustRewardsController} from "../../src/emissions/DustRewardsController.sol";
import "../BaseTestLocal.sol";

contract DustRewardsControllerTest is BaseTestLocal {
    DustRewardsController public rewardsController;
    address internal emissionsManager;

    /* ========== SETUP ========== */

    function _setUp() internal override {
        // Set IncentivesController mock and DustVault with DUST tokens
        emissionsManager = address(0xc1);
        vm.label(emissionsManager, "emissionsManager");

        // Deploy DustLockTransferStrategy
        rewardsController = new DustRewardsController(emissionsManager);
    }

    /* ========== TEST SET CLAIMER ========== */

    function testSetClaimerWithUserCalling() public {
        vm.prank(user);
        address claimer = rewardsController.getClaimer(user);
        assertEq(claimer, address(0), "Initial claimer should be zero address");
        emit log("[rewardsController] Setting claimer by user");
        rewardsController.setClaimer(
            user, // user
            address(0x123) // caller
        );
        address newClaimer = rewardsController.getClaimer(user);
        emit log_named_address("[rewardsController] New claimer", newClaimer);
        assertEq(newClaimer, address(0x123));
    }

    function testSetClaimerWithEmissionsManagerCalling() public {
        vm.prank(emissionsManager);
        address claimer = rewardsController.getClaimer(user);
        assertEq(claimer, address(0), "Initial claimer should be zero address");
        emit log("[rewardsController] Setting claimer by emissionsManager");
        rewardsController.setClaimer(
            user, // user
            address(0x123) // caller
        );
        address newClaimer = rewardsController.getClaimer(user);
        emit log_named_address("[rewardsController] New claimer", newClaimer);
        assertEq(newClaimer, address(0x123));
    }

    function testSetClaimerWithUser2CallingForOtherUser() public {
        address claimer = rewardsController.getClaimer(user);
        assertEq(claimer, address(0), "Initial claimer should be zero address");
        vm.prank(user2);
        emit log("[rewardsController] Expect revert: setClaimer by non-owner/non-emissionsManager");
        vm.expectRevert(IDustRewardsController.OnlyEmissionManagerOrSelf.selector);
        rewardsController.setClaimer(
            user, // user
            address(0x123) // caller
        );
        address newClaimer = rewardsController.getClaimer(user);
        assertEq(newClaimer, address(0), "Initial claimer should not be changed zero address");
    }

    function testSetClaimerWithUserCallingForOtherUserAfterSetClaimer() public {
        vm.prank(emissionsManager);
        address claimer = rewardsController.getClaimer(user);
        assertEq(claimer, address(0), "Initial claimer should be zero address");
        emit log("[rewardsController] Pre-setting claimer by emissionsManager");
        rewardsController.setClaimer(
            user, // user
            address(0x123) // caller
        );
        address newClaimer = rewardsController.getClaimer(user);
        emit log_named_address("[rewardsController] New claimer", newClaimer);
        assertEq(newClaimer, address(0x123));
        vm.prank(user2);
        emit log("[rewardsController] Expect revert: setClaimer by non-owner for other user");
        vm.expectRevert(IDustRewardsController.OnlyEmissionManagerOrSelf.selector);
        rewardsController.setClaimer(
            user, // user
            address(0x123) // caller
        );
        address newClaimer2 = rewardsController.getClaimer(user);
        assertEq(newClaimer2, address(0x123), "Initial claimer should not be changed 0x123");
    }
}
