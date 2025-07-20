// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import "./BaseTest.sol";
import {UserVault} from "../src/self-repaying-loans/UserVault.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

contract UserVaultFactoryTest is BaseTest {
    function testUserVaultCreation() public {
        address userVault = userVaultFactory.getUserVault(user);
        address userVault2 = userVaultFactory.getUserVault(user2);
        address userVault3 = userVaultFactory.getUserVault(user);

        assertTrue(userVault.code.length > 0);
        assertTrue(userVault2.code.length > 0);
        assertTrue(userVault == userVault3);
        assertTrue(userVault != userVault2);
    }
}
