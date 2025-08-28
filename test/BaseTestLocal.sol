// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {BaseTest} from "./BaseTest.sol";
import {IDustLock} from "../src/interfaces/IDustLock.sol";
import {RevenueReward} from "../src/rewards/RevenueReward.sol";
import {Dust} from "../src/tokens/Dust.sol";
import {DustLock} from "../src/tokens/DustLock.sol";
import {MockERC20} from "./_utils/MockERC20.sol";
import {IUserVaultFactory} from "../src/interfaces/IUserVaultFactory.sol";
import {UserVaultFactory} from "../src/self-repaying-loans/UserVaultFactory.sol";
import {UserVault} from "../src/self-repaying-loans/UserVault.sol";
import {UserVaultRegistry} from "../src/self-repaying-loans/UserVaultRegistry.sol";
import {IAaveOracle} from "@aave/core-v3/contracts/interfaces/IAaveOracle.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

abstract contract BaseTestLocal is BaseTest {
    Dust internal DUST;
    IDustLock internal dustLock;
    RevenueReward internal revenueReward;
    MockERC20 internal mockUSDC;
    MockERC20 internal mockERC20;
    IUserVaultFactory internal userVaultFactory;

    address internal admin = address(0xad1);
    address internal user = address(this);
    address internal user1 = address(0x1);
    address internal user2 = address(0x2);
    address internal user3 = address(0x3);
    address internal user4 = address(0x4);
    address internal user5 = address(0x5);

    function _testSetup() internal override {
        // seed set up with initial time
        skip(1 weeks);

        // deploy DUST
        Dust dustImpl = new Dust();
        TransparentUpgradeableProxy dustProxy = new TransparentUpgradeableProxy(address(dustImpl), address(admin), "");
        DUST = Dust(address(dustProxy));
        DUST.initialize(admin);

        // deploy USDC
        mockUSDC = new MockERC20("USDC", "USDC", 6);
        mockERC20 = new MockERC20("mERC20", "mERC20", 18);

        // deploy DustLock
        string memory baseUrl = "https://neverland.money/nfts/";
        dustLock = new DustLock(FORWARDER, address(DUST), baseUrl);

        // AAVE
        IAaveOracle aaveOracle = IAaveOracle(ZERO_ADDRESS);

        // user vault
        UserVaultRegistry userVaultRegistry = new UserVaultRegistry();

        UserVault userVault = new UserVault(userVaultRegistry, aaveOracle);
        UpgradeableBeacon userVaultBeacon = new UpgradeableBeacon(address(userVault));
        userVaultFactory = new UserVaultFactory(address(userVaultBeacon));

        // deploy RevenueReward
        emit log("here1");
        revenueReward = new RevenueReward(FORWARDER, dustLock, admin, userVaultFactory);
        emit log("here2");

        // set RevenueReward to DustLock
        dustLock.setRevenueReward(revenueReward);

        // add log labels
        vm.label(address(admin), "admin");
        vm.label(address(this), "user");
        vm.label(address(user1), "user1");
        vm.label(address(user2), "user2");
        vm.label(address(user3), "user3");
        vm.label(address(user4), "user4");

        vm.label(address(DUST), "DUST");
        vm.label(address(dustLock), "DustLock");
    }
}
