// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {BaseTest} from "./BaseTest.sol";

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

import {IAaveOracle} from "@aave/core-v3/contracts/interfaces/IAaveOracle.sol";

import {IDustLock} from "../src/interfaces/IDustLock.sol";
import {IUserVaultRegistry} from "../src/interfaces/IUserVaultRegistry.sol";
import {IUserVaultFactory} from "../src/interfaces/IUserVaultFactory.sol";
import {RevenueReward} from "../src/rewards/RevenueReward.sol";
import {Dust} from "../src/tokens/Dust.sol";
import {DustLock} from "../src/tokens/DustLock.sol";
import {MockERC20} from "./_utils/MockERC20.sol";
import {UserVaultFactory} from "../src/self-repaying-loans/UserVaultFactory.sol";
import {UserVault} from "../src/self-repaying-loans/UserVault.sol";
import {UserVaultRegistry} from "../src/self-repaying-loans/UserVaultRegistry.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

abstract contract BaseTestLocal is BaseTest {
    Dust internal DUST;
    IDustLock internal dustLock;
    RevenueReward internal revenueReward;
    MockERC20 internal mockUSDC;
    MockERC20 internal mockERC20;
    IUserVaultFactory internal userVaultFactory;
    IUserVaultRegistry internal userVaultRegistry;

    function _testSetup() internal virtual override {
        // seed set up with initial time
        skip(1 weeks);

        // deploy DUST
        Dust dustImpl = new Dust();
        ProxyAdmin proxyAdmin = new ProxyAdmin();
        TransparentUpgradeableProxy dustProxy =
            new TransparentUpgradeableProxy(address(dustImpl), address(proxyAdmin), "");
        DUST = Dust(address(dustProxy));

        // deploy ERC20
        mockUSDC = new MockERC20("USDC", "USDC", 6);
        mockERC20 = new MockERC20("mERC20", "mERC20", 18);

        // deploy DustLock
        string memory baseUrl = "https://neverland.money/nfts/";
        dustLock = new DustLock(FORWARDER, address(DUST), baseUrl);

        // deploy UserVault
        IAaveOracle aaveOracle = IAaveOracle(NON_ZERO_ADDRESS);

        userVaultRegistry = new UserVaultRegistry();
        userVaultRegistry.setExecutor(automation);

        UserVault userVault = new UserVault();
        UpgradeableBeacon userVaultBeacon = new UpgradeableBeacon(address(userVault));
        UserVaultFactory _userVaultFactory = new UserVaultFactory();
        userVaultFactory = IUserVaultFactory(address(_userVaultFactory));

        // deploy RevenueReward
        revenueReward = new RevenueReward(FORWARDER, dustLock, admin, userVaultFactory);

        // initializers
        DUST.initialize(admin);
        _userVaultFactory.initialize(address(userVaultBeacon), userVaultRegistry, aaveOracle, revenueReward);

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
        vm.label(address(userVaultRegistry), "UserVaultRegistry");
        vm.label(address(userVaultFactory), "UserVaultFactory");
        vm.label(address(revenueReward), "RevenueReward");
    }
}
