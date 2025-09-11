// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {IPoolDataProvider} from "@aave/core-v3/contracts/interfaces/IPoolDataProvider.sol";
import {IUiPoolDataProviderV3} from "@aave-v3-periphery/contracts/misc/interfaces/IUiPoolDataProviderV3.sol";

abstract contract ImportUpgradeableBeacon is UpgradeableBeacon {}

abstract contract ImportProxyAdmin is ProxyAdmin {}

abstract contract ImportPoolDataProvider is IPoolDataProvider {}

abstract contract ImportUiPoolDataProviderV3 is IUiPoolDataProviderV3 {}
