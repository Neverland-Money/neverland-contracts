// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "../_shared/CommonErrors.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {UserVault} from "./UserVault.sol";

contract UserVaultFactory {
    address private userVaultBeacon;
    // user address => user vault address
    mapping(address => address) private userVaults;

    error UserVaultExists();

    constructor(address _userVaultBeacon) {
        if (_userVaultBeacon == address(0)) revert AddressZero();
        userVaultBeacon = _userVaultBeacon;
    }

    function getUserVault(address user) public returns (address) {
        if (user == address(0)) revert AddressZero();

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
