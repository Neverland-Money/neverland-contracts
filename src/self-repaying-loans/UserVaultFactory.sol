// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {CommonChecksLibrary} from "../libraries/CommonChecksLibrary.sol";
import {IUserVaultFactory} from "../interfaces/IUserVaultFactory.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {UserVault} from "./UserVault.sol";

contract UserVaultFactory is IUserVaultFactory {
    address private userVaultBeacon;
    // user address => user vault address
    mapping(address => address) private userVaults;

    error UserVaultExists();

    constructor(address _userVaultBeacon) {
        CommonChecksLibrary.revertIfZeroAddress(_userVaultBeacon);
        userVaultBeacon = _userVaultBeacon;
    }

    function getUserVault(address user) public returns (address) {
        CommonChecksLibrary.revertIfZeroAddress(user);

        address existingUserVault = userVaults[user];
        if (existingUserVault != address(0)) return existingUserVault;

        BeaconProxy userVaultBeaconProxy = new BeaconProxy(userVaultBeacon, "");
        UserVault deployedUserVault = UserVault(address(userVaultBeaconProxy));
        deployedUserVault.initialize(user);

        address deployedUserVaultAddress = address(deployedUserVault);
        userVaults[user] = deployedUserVaultAddress;

        return deployedUserVaultAddress;
    }
}
