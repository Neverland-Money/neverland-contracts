// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {BaseTest} from "./BaseTest.sol";

abstract contract BaseTestFork is BaseTest {
    function _testSetup() internal override {}
}
