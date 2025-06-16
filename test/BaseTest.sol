// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Dust} from "../src/tokens/Dust.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {Script} from "forge-std/Script.sol";
import {Test} from "forge-std/Test.sol";
import {DustLock} from "../src/tokens/DustLock.sol";
import {IDustLock} from "../src/interfaces/IDustLock.sol";
import "forge-std/console2.sol";

abstract contract BaseTest is Script, Test {
    Dust public DUST;
    DustLock public dustLock;

    uint256 constant TOKEN_1 = 1e18;
    uint256 constant TOKEN_10K = 1e22; // 1e4 = 10K tokens with 18 decimals
    uint256 constant TOKEN_100K = 1e23; // 1e5 = 100K tokens with 18 decimals
    uint256 constant TOKEN_1M = 1e24; // 1e6 = 1M tokens with 18 decimals
    uint256 constant TOKEN_10M = 1e25; // 1e7 = 10M tokens with 18 decimals
    uint256 constant TOKEN_100M = 1e26; // 1e8 = 100M tokens with 18 decimals
    uint256 constant TOKEN_10B = 1e28; // 1e10 = 10B tokens with 18 decimals

    address internal admin = address(0xad1);
    address internal user = address(this);
    address internal user1 = address(0x1);
    address internal user2 = address(0x2);
    address internal user3 = address(0x3);
    address internal user4 = address(0x4);
    address internal user5 = address(0x5);
    address[] users;

    uint256 constant MAXTIME = 4 * 365 * 86400;
    uint256 constant WEEK = 1 weeks;

    function setUp() public {
        _testSetup();
    }

    function _testSetup() public {
        // seed set up with initial time
        skip(1 weeks);

        // mint DUST to users
        uint256[] memory amounts = new uint256[](5);
        amounts[0] = TOKEN_10M;
        amounts[1] = TOKEN_10M;
        amounts[2] = TOKEN_10M;
        amounts[3] = TOKEN_10M;
        amounts[4] = TOKEN_10M;

        users = new address[](6);
        users[0] = payable(address(this));
        users[1] = address(admin);
        users[2] = address(user1);
        users[3] = address(user2);
        users[4] = address(user3);
        users[5] = address(user4);

        // deploy DUST
        Dust dustImpl = new Dust();
        TransparentUpgradeableProxy dustProxy =
                    new TransparentUpgradeableProxy(address(dustImpl), address(admin), "");
        DUST = Dust(address(dustProxy));
        DUST.initialize(admin);


        // mint
        mintErc20Token18Dec(address(DUST), users, amounts);

        // deploy DustLock
        dustLock = new DustLock(admin, address(DUST));

        // add log labels
        vm.label(address(admin), "admin");
        vm.label(address(user1), "user1");
        vm.label(address(user2), "user2");
        vm.label(address(user3), "user3");
        vm.label(address(user4), "user4");

        vm.label(address(DUST), "DUST");
        vm.label(address(dustLock), "DustLock");
    }

    /* ========== HELPER FUNCTIONS ========== */

    function mintErc20Token18Dec(address _token, address[] memory _accounts, uint256[] memory _amounts) internal {
        for (uint256 i = 0; i < _amounts.length; i++) {
            deal(address(_token), _accounts[i], _amounts[i], true);
        }
    }

    function mintETH(address[] memory _accounts, uint256[] memory _amounts) internal {
        for (uint256 i = 0; i < _accounts.length; i++) {
            vm.deal(_accounts[i], _amounts[i]);
        }
    }

    /// @dev Forwards time to next week
    ///      note epoch requires at least one second to have passed into the new epoch
    function skipToNextEpoch(uint256 offset) internal {
        uint256 ts = block.timestamp;
        uint256 nextEpoch = ts - (ts % (1 weeks)) + (1 weeks);
        vm.warp(nextEpoch + offset);
        vm.roll(block.number + 1);
    }

    function skipAndRoll(uint256 timeOffset) internal {
        skip(timeOffset);
        vm.roll(block.number + 1);
    }

    /// @dev Get start of epoch based on timestamp
    function _getEpochStart(uint256 _timestamp) internal pure returns (uint256) {
        return _timestamp - (_timestamp % (7 days));
    }

    /// @dev Converts int128s to uint256, values always positive
    function convert(int128 _amount) internal pure returns (uint256) {
        return uint256(uint128(_amount));
    }
}
