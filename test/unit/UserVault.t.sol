// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "../BaseTestLocal.sol";
import {HarnessFactory} from "../harness/HarnessFactory.sol";
import {UserVaultHarness} from "../harness/UserVaultHarness.sol";
import {IUserVault} from "../../src/interfaces/IUserVault.sol";

contract RevenueRewardsTest is BaseTestLocal {
    HarnessFactory harnessFactory;

    function _setUp() internal override {
        harnessFactory = new HarnessFactory();
    }

    function testVerifySlippage() public {
        // arrange
        (UserVaultHarness _userVault,,,) =
            harnessFactory.createUserVaultHarness(user, revenueReward, poolAddressesProviderRegistry, automation);

        // act/assert

        // slippage is 100
        _userVault.exposed_verifySlippage(100, 1e8, 90, 11e7, 100);
        // slippage is 100
        vm.expectRevert(IUserVault.SlippageExceeded.selector);
        _userVault.exposed_verifySlippage(100, 1e8, 90, 11e7, 99);
        // slippage is 100
        _userVault.exposed_verifySlippage(90, 1e8, 100, 11e7, 100);
    }
}
