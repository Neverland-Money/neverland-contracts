// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

import {IPoolAddressesProviderRegistry} from "@aave/core-v3/contracts/interfaces/IPoolAddressesProviderRegistry.sol";

import {IUserVaultFactory} from "../interfaces/IUserVaultFactory.sol";
import {IUserVaultRegistry} from "../interfaces/IUserVaultRegistry.sol";
import {IRevenueReward} from "../interfaces/IRevenueReward.sol";
import {CommonChecksLibrary} from "../libraries/CommonChecksLibrary.sol";
import {UserVault} from "./UserVault.sol";

contract UserVaultFactory is IUserVaultFactory, Initializable {
    address private userVaultBeacon;
    IUserVaultRegistry userVaultRegistry;
    IPoolAddressesProviderRegistry poolAddressesProviderRegistry;
    IRevenueReward revenueReward;

    // user => UserVault
    mapping(address => address) private userVaults;

    function initialize(
        address _userVaultBeacon,
        IUserVaultRegistry _userVaultRegistry,
        IPoolAddressesProviderRegistry _poolAddressesProviderRegistry,
        IRevenueReward _revenueReward
    ) external initializer {
        CommonChecksLibrary.revertIfZeroAddress(_userVaultBeacon);
        CommonChecksLibrary.revertIfZeroAddress(address(_userVaultRegistry));
        CommonChecksLibrary.revertIfZeroAddress(address(_poolAddressesProviderRegistry));
        CommonChecksLibrary.revertIfZeroAddress(address(_revenueReward));

        userVaultBeacon = _userVaultBeacon;
        userVaultRegistry = _userVaultRegistry;
        poolAddressesProviderRegistry = _poolAddressesProviderRegistry;
        revenueReward = _revenueReward;
    }

    function getUserVault(address user) external view returns (address) {
        return userVaults[user];
    }

    function getOrCreateUserVault(address user) external returns (address) {
        CommonChecksLibrary.revertIfZeroAddress(user);

        address existingUserVault = userVaults[user];
        if (existingUserVault != address(0)) return existingUserVault;

        address deployedUserVaultAddress = _createUserVault(user);
        userVaults[user] = deployedUserVaultAddress;

        return deployedUserVaultAddress;
    }

    function _createUserVault(address user) internal returns (address) {
        BeaconProxy userVaultBeaconProxy = new BeaconProxy(userVaultBeacon, "");
        UserVault deployedUserVault = UserVault(address(userVaultBeaconProxy));
        deployedUserVault.initialize(user, revenueReward, userVaultRegistry, poolAddressesProviderRegistry);

        return address(deployedUserVault);
    }
}
