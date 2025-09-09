// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

abstract contract ImportUpgradeableBeacon is UpgradeableBeacon {}

abstract contract ImportProxyAdmin is ProxyAdmin {}
