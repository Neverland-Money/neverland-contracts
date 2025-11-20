// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "../../BaseTestLocal.sol";
import {EpochManager} from "../../../src/leaderboard/EpochManager.sol";
import {LeaderboardConfig} from "../../../src/leaderboard/LeaderboardConfig.sol";
import {NFTPartnershipRegistry} from "../../../src/leaderboard/NFTPartnershipRegistry.sol";
import {VotingPowerMultiplier} from "../../../src/leaderboard/VotingPowerMultiplier.sol";
import {MockERC721} from "../../_utils/MockERC721.sol";

abstract contract LeaderboardBase is BaseTestLocal {
    EpochManager internal epochManager;
    LeaderboardConfig internal leaderboardConfig;
    NFTPartnershipRegistry internal nftRegistry;
    VotingPowerMultiplier internal vpMultiplier;

    MockERC721 internal nftCollection1;
    MockERC721 internal nftCollection2;
    MockERC721 internal nftCollection3;

    // Test constants
    uint256 constant DEPOSIT_RATE = 100; // 0.01 per USD/day
    uint256 constant BORROW_RATE = 500; // 0.05 per USD/day
    uint256 constant VP_RATE = 200; // 0.02 per veDUST/day
    uint256 constant SUPPLY_BONUS = 10e18; // 10 points/day
    uint256 constant BORROW_BONUS = 20e18; // 20 points/day
    uint256 constant COOLDOWN = 3600; // 1 hour
    uint256 constant MIN_DAILY_BONUS_USD = 100e18; // $100

    uint256 constant FIRST_BONUS = 1000; // 0.1 (10%)
    uint256 constant DECAY_RATIO = 9000; // 0.9 (90%)

    function _testSetup() internal virtual override {
        super._testSetup();
        _testSetupLeaderboard();
    }

    function _testSetupLeaderboard() internal {
        // Deploy EpochManager
        epochManager = new EpochManager(admin);

        // Deploy LeaderboardConfig
        leaderboardConfig = new LeaderboardConfig(
            admin, DEPOSIT_RATE, BORROW_RATE, VP_RATE, SUPPLY_BONUS, BORROW_BONUS, 0, 0, COOLDOWN, MIN_DAILY_BONUS_USD
        );

        // Deploy NFTPartnershipRegistry
        nftRegistry = new NFTPartnershipRegistry(admin, FIRST_BONUS, DECAY_RATIO);

        // Deploy VotingPowerMultiplier
        vpMultiplier = new VotingPowerMultiplier(admin, address(dustLock));

        // Deploy mock NFT collections
        nftCollection1 = new MockERC721("Collection1", "C1");
        nftCollection2 = new MockERC721("Collection2", "C2");
        nftCollection3 = new MockERC721("Collection3", "C3");

        // Labels
        vm.label(address(epochManager), "EpochManager");
        vm.label(address(leaderboardConfig), "LeaderboardConfig");
        vm.label(address(nftRegistry), "NFTPartnershipRegistry");
        vm.label(address(vpMultiplier), "VotingPowerMultiplier");
        vm.label(address(nftCollection1), "NFTCollection1");
        vm.label(address(nftCollection2), "NFTCollection2");
        vm.label(address(nftCollection3), "NFTCollection3");
    }

    // Helper to mint NFTs to users
    function _mintNFT(MockERC721 collection, address to, uint256 tokenId) internal {
        collection.mint(to, tokenId);
    }

    // Helper to lock DUST and get voting power
    function _lockDust(address user, uint256 amount, uint256 duration) internal returns (uint256 tokenId) {
        deal(address(DUST), user, amount);

        vm.startPrank(user);
        DUST.approve(address(dustLock), amount);
        tokenId = dustLock.createLock(amount, duration);
        vm.stopPrank();
    }
}
