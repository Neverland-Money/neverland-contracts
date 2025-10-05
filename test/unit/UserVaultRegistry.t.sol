// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "../BaseTestLocal.sol";
import {UserVaultRegistry} from "../../src/self-repaying-loans/UserVaultRegistry.sol";

contract UserVaultRegistryTest is BaseTestLocal {
    UserVaultRegistry registry;

    function setUp() public override {
        _testSetup();
        registry = UserVaultRegistry(address(userVaultRegistry));
    }

    function testRenounceOwnershipReverts() public {
        // Arrange
        address currentOwner = registry.owner();
        assertEq(currentOwner, address(this), "Owner should be the test contract");

        // Act & Assert
        vm.expectRevert();
        registry.renounceOwnership();

        // Verify owner hasn't changed
        assertEq(registry.owner(), address(this), "Owner should still be test contract after failed renounce");
    }

    function testRenounceOwnershipRevertsForNonOwner() public {
        // Arrange
        address currentOwner = registry.owner();
        assertEq(currentOwner, address(this), "Owner should be the test contract");

        // Act & Assert - non-owner trying to call renounceOwnership should revert
        vm.prank(user);
        vm.expectRevert();
        registry.renounceOwnership();

        // Verify owner hasn't changed
        assertEq(registry.owner(), address(this), "Owner should still be test contract");
    }
}
