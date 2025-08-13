// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "../BaseTestFork.sol";
import {IPoolAddressesProviderRegistry} from "@aave/core-v3/contracts/interfaces/IPoolAddressesProviderRegistry.sol";
import "forge-std/console.sol";

contract UserVaultTest is BaseTestFork {
    address poolDataProviderAddress = 0x2F7ae2EebE5Dd10BfB13f3fB2956C7b7FFD60A5F;

    function testRepayDebt() public {
        // arrange
        IPoolAddressesProviderRegistry papr = IPoolAddressesProviderRegistry(poolDataProviderAddress);
        address[] memory addresses = papr.getAddressesProvidersList();

        address pool1 = addresses[0];

        emit log_named_address("pool address", pool1);
    }
}
