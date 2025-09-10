// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

import {IAaveOracle} from "@aave/core-v3/contracts/interfaces/IAaveOracle.sol";

import {IUserVaultRegistry} from "../../src/interfaces/IUserVaultRegistry.sol";
import {IRevenueReward} from "../../src/interfaces/IRevenueReward.sol";
import {UserVaultRegistry} from "../../src/self-repaying-loans/UserVaultRegistry.sol";
import {UserVaultHarness} from "./UserVaultHarness.sol";

contract HarnessFactory {
    function createUserVaultHarness(
        address user,
        IRevenueReward revenueReward,
        address aaveOracleAddress,
        address executor
    ) public returns (UserVaultHarness, IRevenueReward, IUserVaultRegistry, IAaveOracle) {
        IAaveOracle _aaveOracle = IAaveOracle(aaveOracleAddress);

        IUserVaultRegistry _userVaultRegistry = new UserVaultRegistry();
        _userVaultRegistry.setExecutor(executor);

        // Create temporaries in a scoped block to free stack slots
        UserVaultHarness _userVault;
        {
            UserVaultHarness _userVaultIml = new UserVaultHarness();
            UpgradeableBeacon _userVaultBeacon = new UpgradeableBeacon(address(_userVaultIml));
            BeaconProxy _userVaultBeaconProxy = new BeaconProxy(address(_userVaultBeacon), "");
            _userVault = UserVaultHarness(address(_userVaultBeaconProxy));
        }
        _userVault.initialize(_userVaultRegistry, _aaveOracle, revenueReward, user);

        return (_userVault, revenueReward, _userVaultRegistry, _aaveOracle);
    }
}
