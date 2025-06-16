// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {BaseTest} from "./BaseTest.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

contract DustLockTest is BaseTest {

  function testSupportInterfaces() public view {
    assertTrue(dustLock.supportsInterface(type(IERC721).interfaceId));
  }

}