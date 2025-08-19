// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {Script} from "forge-std/Script.sol";
import {Test} from "forge-std/Test.sol";

import {IDustLock} from "../src/interfaces/IDustLock.sol";
import {RevenueReward} from "../src/rewards/RevenueReward.sol";
import {Dust} from "../src/tokens/Dust.sol";
import {DustLock} from "../src/tokens/DustLock.sol";
import {MockERC20} from "./utils/MockERC20.sol";

abstract contract BaseTest is Script, Test {
    Dust internal DUST;
    DustLock internal dustLock;
    RevenueReward internal revenueReward;
    MockERC20 internal mockUSDC;
    MockERC20 internal mockERC20;

    uint256 constant USDC_1_UNIT = 1; // 1/100th of a cent
    uint256 constant USDC_1_CENT = 10000; // 0.01 USDC
    uint256 constant USDC_1 = 1e6;
    uint256 constant USDC_1K = 1e9; // 1e3 = 10K tokens with 6 decimals
    uint256 constant USDC_10K = 1e10; // 1e4 = 10K tokens with 6 decimals
    uint256 constant USDC_100K = 1e11; // 1e5 = 100K tokens with 6 decimals

    uint256 constant TOKEN_1_WEI = 1;
    uint256 constant TOKEN_1_MWEI = 1e6;
    uint256 constant TOKEN_1_GWEI = 1e9;
    uint256 constant TOKEN_1 = 1e18;
    uint256 constant TOKEN_1K = 1e21; // 1e3 = 1K tokens with 18 decimals
    uint256 constant TOKEN_10K = 1e22; // 1e4 = 10K tokens with 18 decimals
    uint256 constant TOKEN_100K = 1e23; // 1e5 = 100K tokens with 18 decimals
    uint256 constant TOKEN_1M = 1e24; // 1e6 = 1M tokens with 18 decimals
    uint256 constant TOKEN_10M = 1e25; // 1e7 = 10M tokens with 18 decimals
    uint256 constant TOKEN_50M = 5e25; // 5e7 = 50M tokens with 18 decimals
    uint256 constant TOKEN_100M = 1e26; // 1e8 = 100M tokens with 18 decimals

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

    uint256 constant MIN_LOCK_AMOUNT = 1e18;

    uint256 constant PRECISION_TOLERANCE = 1; // 1 wei tolerance for rounding

    function setUp() public virtual {
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
        TransparentUpgradeableProxy dustProxy = new TransparentUpgradeableProxy(address(dustImpl), address(admin), "");
        DUST = Dust(address(dustProxy));
        DUST.initialize(admin);

        // deploy USDC
        mockUSDC = new MockERC20("USDC", "USDC", 6);
        mockERC20 = new MockERC20("mERC20", "mERC20", 18);

        // deploy DustLock
        string memory baseUrl = "https://neverland.money/nfts/";
        dustLock = new DustLock(address(0xF0), address(DUST), baseUrl);

        // deploy RevenueReward
        revenueReward = new RevenueReward(address(0xF1), address(dustLock), admin);

        // set RevenueReward to DustLock
        dustLock.setRevenueReward(revenueReward);

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

    function logWithTs(string memory label) internal {
        emit log(string(abi.encodePacked("TS - ", vm.toString(block.timestamp), " - ", label)));
    }

    /// @dev Forwards time to next week
    ///      note epoch requires at least one second to have passed into the new epoch
    function skipToNextEpoch(uint256 offset) internal {
        uint256 ts = block.timestamp;
        uint256 nextEpoch = ts - (ts % (1 weeks)) + (1 weeks);
        vm.warp(nextEpoch + offset);
        vm.roll(block.number + 1);
    }

    function skipToAndLog(uint256 to, string memory label) internal {
        vm.warp(to);
        emit log(string(abi.encodePacked("Wrap to ", vm.toString(to), " TS - ", label)));
    }

    function skipAndRoll(uint256 timeOffset) internal {
        skip(timeOffset);
        vm.roll(block.number + 1);
    }

    function skipNumberOfEpochs(uint256 epochs) internal {
        for (uint256 i = 0; i < epochs; i++) {
            skipToNextEpoch(0);
        }
    }

    function goToEpoch(uint256 epochNumber) internal {
        uint256 currentEpoch = block.timestamp / 1 weeks;
        if (epochNumber <= currentEpoch) revert("goToEpoch less or equal than current");
        skipNumberOfEpochs(epochNumber - currentEpoch);
    }

    /// @dev Get start of epoch based on timestamp
    function _getEpochStart(uint256 _timestamp) internal pure returns (uint256) {
        return _timestamp - (_timestamp % (7 days));
    }

    /// @dev Converts int128s to uint256, values always positive
    function convert(int128 _amount) internal pure returns (uint256) {
        return uint256(uint128(_amount));
    }

    // assertion helpers

    function assertArrayContainsUint(uint256[] memory array, uint256 value) internal pure {
        bool found = false;
        for (uint256 i = 0; i < array.length; i++) {
            if (array[i] == value) {
                found = true;
                break;
            }
        }
        assertTrue(found, "Array does not contain expected value");
    }

    function assertArrayContainsAddr(address[] memory array, address value) internal pure {
        bool found = false;
        for (uint256 i = 0; i < array.length; i++) {
            if (array[i] == value) {
                found = true;
                break;
            }
        }
        assertTrue(found, "Array does not contain expected value");
    }

    function assertEqApprThreeWei(uint256 actualAmount, uint256 expectedAmount) internal pure {
        assertApproxEqAbs(actualAmount, expectedAmount, 3);
    }
}
