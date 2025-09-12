// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import {IPoolAddressesProviderRegistry} from "@aave/core-v3/contracts/interfaces/IPoolAddressesProviderRegistry.sol";

import {IUserVaultFactory} from "../interfaces/IUserVaultFactory.sol";
import {IUserVaultRegistry} from "../interfaces/IUserVaultRegistry.sol";
import {IRevenueReward} from "../interfaces/IRevenueReward.sol";
import {CommonChecksLibrary} from "../libraries/CommonChecksLibrary.sol";

import {UserVault} from "./UserVault.sol";

/**
 * @title UserVaultFactory
 * @author Neverland
 * @notice Factory contract for creating UserVault instances
 */
contract UserVaultFactory is IUserVaultFactory, Initializable, ReentrancyGuard {
    /*//////////////////////////////////////////////////////////////
                          STORAGE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Address of the UserVault beacon
    address private userVaultBeacon;
    /// @notice UserVaultRegistry contract
    IUserVaultRegistry public userVaultRegistry;
    /// @notice AAVE PoolAddressesProviderRegistry contract
    IPoolAddressesProviderRegistry public poolAddressesProviderRegistry;
    /// @notice RevenueReward contract
    IRevenueReward public revenueReward;

    /// @notice Mapping of user to their UserVault
    mapping(address => address) private userVaults;

    /*//////////////////////////////////////////////////////////////
                              INITIALIZER
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the contract
     * @param _userVaultBeacon Address of the UserVault beacon
     * @param _userVaultRegistry UserVaultRegistry contract
     * @param _poolAddressesProviderRegistry AAVE PoolAddressesProviderRegistry contract
     * @param _revenueReward RevenueReward contract
     */
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

    /*//////////////////////////////////////////////////////////////
                                 VIEWS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IUserVaultFactory
    function getUserVault(address user) external view override returns (address) {
        return userVaults[user];
    }

    /*//////////////////////////////////////////////////////////////
                                ACTIONS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IUserVaultFactory
    function getOrCreateUserVault(address user) external override nonReentrant returns (address) {
        CommonChecksLibrary.revertIfZeroAddress(user);

        address existingUserVault = userVaults[user];
        if (existingUserVault != address(0)) return existingUserVault;

        address deployedUserVaultAddress = _createUserVault(user);
        userVaults[user] = deployedUserVaultAddress;

        emit UserVaultCreated(user, deployedUserVaultAddress);

        return deployedUserVaultAddress;
    }

    /*//////////////////////////////////////////////////////////////
                               INTERNAL
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Creates a new UserVault
     * @param user User address
     * @return Address of the deployed UserVault
     */
    function _createUserVault(address user) internal returns (address) {
        BeaconProxy userVaultBeaconProxy = new BeaconProxy(userVaultBeacon, "");
        UserVault deployedUserVault = UserVault(address(userVaultBeaconProxy));
        deployedUserVault.initialize(user, revenueReward, userVaultRegistry, poolAddressesProviderRegistry);

        return address(deployedUserVault);
    }
}
