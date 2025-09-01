// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {BaseTest} from "./BaseTest.sol";
import {IDustLock} from "../src/interfaces/IDustLock.sol";
import {IUserVaultRegistry} from "../src/interfaces/IUserVaultRegistry.sol";
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
    IUserVaultRegistry internal userVaultRegistry;

    address internal automation = address(0xad2);
    address internal admin = address(0xad1);
    address internal user = address(this);
    address internal user1 = address(0x1);
    address internal user2 = address(0x2);
    address internal user3 = address(0x3);
    address internal user4 = address(0x4);
    address internal user5 = address(0x5);

    function _testSetup() internal virtual override {
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
        userVaultRegistry = new UserVaultRegistry();
        userVaultRegistry.setExecutor(automation);

        UserVault userVault = new UserVault(userVaultRegistry, aaveOracle);
        UpgradeableBeacon userVaultBeacon = new UpgradeableBeacon(address(userVault));
        userVaultFactory = new UserVaultFactory(address(userVaultBeacon));

        // deploy RevenueReward
        revenueReward = new RevenueReward(FORWARDER, dustLock, admin, userVaultFactory);

        // set RevenueReward to DustLock
        dustLock.setRevenueReward(revenueReward);

        // add log labels
        vm.label(automation, "automation");
        vm.label(admin, "admin");
        vm.label(address(this), "user");
        vm.label(user1, "user1");
        vm.label(user2, "user2");
        vm.label(user3, "user3");
        vm.label(user4, "user4");

        vm.label(address(DUST), "DUST");
        vm.label(address(dustLock), "DustLock");
        vm.label(address(aaveOracle), "AAVE Oracle");
        vm.label(address(userVaultRegistry), "UserVaultRegistry");
        vm.label(address(userVaultFactory), "UserVaultFactory");
        vm.label(address(revenueReward), "RevenueReward");
    }
}
