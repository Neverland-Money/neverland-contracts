// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {DustLock} from "../src/tokens/DustLock.sol";
import {Dust} from "../src/tokens/Dust.sol";
import {IDustLock} from "../src/interfaces/IDustLock.sol";
import {Script} from "forge-std/Script.sol";
import {Test} from "forge-std/Test.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {MockERC20} from "./utils/MockERC20.sol";
import {RevenueReward} from "../src/rewards/RevenueReward.sol";

abstract contract BaseTest is Script, Test {
    Dust internal DUST;
    DustLock internal dustLock;
    RevenueReward internal revenueReward;
    MockERC20 internal mockUSDC;

    uint256 constant USDC_1 = 1e6;
    uint256 constant USDC_10K = 1e10; // 1e4 = 10K tokens with 6 decimals
    uint256 constant USDC_100K = 1e11; // 1e5 = 100K tokens with 6 decimals

    uint256 constant TOKEN_1 = 1e18;
    uint256 constant TOKEN_10K = 1e22; // 1e4 = 10K tokens with 18 decimals
    uint256 constant TOKEN_100K = 1e23; // 1e5 = 100K tokens with 18 decimals
    uint256 constant TOKEN_1M = 1e24; // 1e6 = 1M tokens with 18 decimals
    uint256 constant TOKEN_10M = 1e25; // 1e7 = 10M tokens with 18 decimals
    uint256 constant TOKEN_100M = 1e26; // 1e8 = 100M tokens with 18 decimals
    uint256 constant TOKEN_10B = 1e28; // 1e10 = 10B tokens with 18 decimals

    address internal ZERO_ADDRESS = address(0);
    address internal admin = address(0xad1);
    address internal user = address(this);
    address internal user1 = address(0x1);
    address internal user2 = address(0x2);
    address internal user3 = address(0x3);
    address internal user4 = address(0x4);
    address internal user5 = address(0x5);

    uint256 constant MINTIME = 4 weeks;
    uint256 constant MAXTIME = 1 * 365 * 86400;
    uint256 constant WEEK = 1 weeks;

    function setUp() public {
        _testSetup();
        _setUp();
    }

    /// @dev Implement this if you want a custom configured deployment
    function _setUp() internal virtual {}

    function _testSetup() internal {
        // seed set up with initial time
        skip(1 weeks);

        // deploy DUST
        Dust dustImpl = new Dust();
        TransparentUpgradeableProxy dustProxy =
                    new TransparentUpgradeableProxy(address(dustImpl), address(admin), "");
        DUST = Dust(address(dustProxy));
        DUST.initialize(admin);

        // deploy USDC
        mockUSDC = new MockERC20("USDC", "USDC", 6);

        // deploy DustLock
        string memory baseUrl = "https://neverland.money/nfts/";
        dustLock = new DustLock(ZERO_ADDRESS, address(DUST), baseUrl);

        // deploy RevenueReward
        revenueReward = new RevenueReward(ZERO_ADDRESS, address(dustLock), admin);

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

    /* ========== HELPER FUNCTIONS ========== */

    function mintErc20Tokens(address _token, address[] memory _accounts, uint256[] memory _amounts) internal {
        for (uint256 i = 0; i < _amounts.length; i++) {
            mintErc20Token(address(_token), _accounts[i], _amounts[i]);
        }
    }

    function mintErc20Token(address _token, address _account, uint256 _amount) internal {
        deal(address(_token), _account, _amount, true);
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
