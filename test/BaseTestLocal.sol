// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {BaseTest} from "./BaseTest.sol";

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

import {IPoolAddressesProviderRegistry} from "@aave/core-v3/contracts/interfaces/IPoolAddressesProviderRegistry.sol";
import {IPoolAddressesProvider} from "@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol";
import {IPool} from "@aave/core-v3/contracts/interfaces/IPool.sol";
import {IAaveOracle} from "@aave/core-v3/contracts/interfaces/IAaveOracle.sol";
import {IACLManager} from "@aave/core-v3/contracts/interfaces/IACLManager.sol";
import {PoolAddressesProviderRegistry} from
    "@aave/core-v3/contracts/protocol/configuration/PoolAddressesProviderRegistry.sol";
import {PoolAddressesProvider} from "@aave/core-v3/contracts/protocol/configuration/PoolAddressesProvider.sol";
import {Pool} from "@aave/core-v3/contracts/protocol/pool/Pool.sol";
import {ACLManager} from "@aave/core-v3/contracts/protocol/configuration/ACLManager.sol";
import {AaveOracle} from "@aave/core-v3/contracts/misc/AaveOracle.sol";

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
    // AAVE
    IPoolAddressesProviderRegistry public poolAddressesProviderRegistry;
    IPoolAddressesProvider public poolAddressesProvider;

    address public AAVE_ADMIN = user;
    uint256 public PROVIDER_ID = 1;
    string public MARKET_ID = "TestMarket";
    address public BASE_CURRENCY = address(0x1); // eg Mock USDC
    uint256 public BASE_CURRENCY_UNIT = 1e8;

    // DUST
    Dust internal DUST;
    IDustLock internal dustLock;
    RevenueReward internal revenueReward;
    MockERC20 internal mockUSDC;
    MockERC20 internal mockERC20;
    IUserVaultFactory internal userVaultFactory;
    IUserVaultRegistry internal userVaultRegistry;

    function _testSetup() internal virtual override {
        _testSetUpAave();
        _testSetUpDust();
    }

    function _testSetUpAave() internal {
        // Deploy the registry with owner
        poolAddressesProviderRegistry = new PoolAddressesProviderRegistry(AAVE_ADMIN);

        // Deploy addresses provider with marketId and owner
        poolAddressesProvider = new PoolAddressesProvider(MARKET_ID, AAVE_ADMIN);

        // IMPORTANT: Set ACL Admin BEFORE deploying ACL Manager
        poolAddressesProvider.setACLAdmin(AAVE_ADMIN);

        // Now deploy ACL Manager (it will call getACLAdmin() during construction)
        IACLManager aclManager = new ACLManager(poolAddressesProvider);
        poolAddressesProvider.setACLManager(address(aclManager));

        // Deploy Pool implementation
        IPool poolImpl = new Pool(poolAddressesProvider);
        poolAddressesProvider.setPoolImpl(address(poolImpl));

        // Set up oracle with minimal configuration
        address[] memory assets = new address[](0);
        address[] memory sources = new address[](0);
        address fallbackOracle = address(0);

        IAaveOracle oracle =
            new AaveOracle(poolAddressesProvider, assets, sources, fallbackOracle, BASE_CURRENCY, BASE_CURRENCY_UNIT);
        poolAddressesProvider.setPriceOracle(address(oracle));

        // Register the addresses provider
        poolAddressesProviderRegistry.registerAddressesProvider(address(poolAddressesProvider), PROVIDER_ID);

        // add address labels
        vm.label(address(poolAddressesProviderRegistry), "PoolAddressesProviderRegistry");
    }

    function _testSetUpDust() internal {
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

        userVaultRegistry = new UserVaultRegistry();
        userVaultRegistry.setExecutor(automation);

        UserVault userVault = new UserVault();
        UpgradeableBeacon userVaultBeacon = new UpgradeableBeacon(address(userVault));
        UserVaultFactory _userVaultFactory = new UserVaultFactory();
        userVaultFactory = IUserVaultFactory(address(_userVaultFactory));

        // deploy RevenueReward
        revenueReward = new RevenueReward(FORWARDER, dustLock, admin, userVaultFactory);

        // initializers
        DUST.initialize(admin, 0);
        _userVaultFactory.initialize(
            address(userVaultBeacon), userVaultRegistry, poolAddressesProviderRegistry, revenueReward
        );

        dustLock.setRevenueReward(revenueReward);

        // add address labels
        vm.label(address(DUST), "DUST");
        vm.label(address(dustLock), "DustLock");
        vm.label(address(userVaultRegistry), "UserVaultRegistry");
        vm.label(address(userVaultFactory), "UserVaultFactory");
        vm.label(address(revenueReward), "RevenueReward");
    }
}
