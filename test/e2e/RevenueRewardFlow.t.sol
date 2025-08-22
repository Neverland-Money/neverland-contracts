// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "../BaseTest.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IDustLock} from "../../src/interfaces/IDustLock.sol";
import {RevenueReward} from "../../src/rewards/RevenueReward.sol";

/**
 * @title RevenueRewardFlow
 * @notice Tests for reward distribution based on voting power precision
 * @dev Tests that rewards are distributed proportionally to voting power
 */
contract RevenueRewardFlow is BaseTest {
    // RevenueReward instances for precision testing
    RevenueReward internal testRevenueReward;
    RevenueReward internal testRevenueReward2;
    RevenueReward internal testRevenueReward3;

    function _claimAndLog(uint256 tokenId, address owner, address[] memory rewards, string memory label) internal {
        uint256 dustPre = DUST.balanceOf(owner);
        uint256 usdcPre = mockUSDC.balanceOf(owner);
        vm.startPrank(owner);
        testRevenueReward.getReward(tokenId, rewards);
        vm.stopPrank();
        uint256 dustReceived = DUST.balanceOf(owner) - dustPre;
        uint256 usdcReceived = mockUSDC.balanceOf(owner) - usdcPre;
        logWithTs(string(abi.encodePacked(label, " DUST expected/actual")));
        emit log_named_uint("expected", 0);
        emit log_named_uint("actual", dustReceived);
        logWithTs(string(abi.encodePacked(label, " USDC expected/actual")));
        emit log_named_uint("expected", 0);
        emit log_named_uint("actual", usdcReceived);
    }

    function _createRewardWithAmount(RevenueReward _revenueReward, address _token, uint256 _amount) internal {
        // Mint tokens directly to user (rewardDistributor) to avoid transfer issues
        deal(_token, user, IERC20(_token).balanceOf(user) + _amount);

        // user (address(this)) is the rewardDistributor, so we can call directly
        IERC20(_token).approve(address(_revenueReward), _amount);
        _revenueReward.notifyRewardAmount(address(_token), _amount);
    }

    function _setUp() internal override {
        // Call parent setup first
        super._setUp();

        // Initialize RevenueReward instances for precision testing
        // Use user (address(this)) as rewardDistributor instead of admin (proxy admin)
        testRevenueReward = new RevenueReward(address(0xF2), address(dustLock), user);
        testRevenueReward2 = new RevenueReward(address(0xF3), address(dustLock), user);
        testRevenueReward3 = new RevenueReward(address(0xF4), address(dustLock), user);

        skip(1 hours);

        // Ensure all users have enough DUST tokens for creating locks
        deal(address(DUST), user1, TOKEN_100K);
        deal(address(DUST), user2, TOKEN_10K);
        deal(address(DUST), user3, TOKEN_1K);
        deal(address(DUST), user4, TOKEN_10K);

        // Create locks for all users with different durations to test voting power differences
        vm.startPrank(user1);
        DUST.approve(address(dustLock), TOKEN_100K);
        dustLock.createLock(TOKEN_100K, MAXTIME); // tokenId 1 - 100,000 DUST for MAXTIME
        vm.stopPrank();

        vm.startPrank(user2);
        DUST.approve(address(dustLock), TOKEN_10K);
        uint256 tokenId2 = dustLock.createLock(TOKEN_10K, MAXTIME); // tokenId 2 - 10,000 DUST for PERMANENT
        dustLock.lockPermanent(tokenId2);
        vm.stopPrank();

        vm.startPrank(user3);
        DUST.approve(address(dustLock), TOKEN_1K);
        dustLock.createLock(TOKEN_1K, MAXTIME); // tokenId 3 - 1,000 DUST for MAXTIME
        vm.stopPrank();

        vm.startPrank(user4);
        DUST.approve(address(dustLock), TOKEN_10K);
        dustLock.createLock(TOKEN_10K, MAXTIME / 4); // tokenId 4 - 10,000 DUST for 1/4 MAXTIME
        vm.stopPrank();

        skip(1);
    }

    function testRewardDistributionProportionalToVotingPowerAtEpochStart() public {
        // Test reward distribution based on voting power precision
        address[] memory rewards = new address[](2);
        rewards[0] = address(DUST);
        rewards[1] = address(mockUSDC);

        // Aggregate trackers (sum of user distributions)
        uint256 dustSum;
        uint256 usdcSum;
        // Setup: Create rewards for different lock holders (limit local lifetimes)
        {
            // Test contract has max lock time (higher voting power)
            // user4 has quarter of max lock time (lower voting power)
            uint256 dustReward = TOKEN_10K; // 10,000 DUST (18 decimals)
            uint256 usdcReward = USDC_10K; // 10,000 USDC (6 decimals)
            _createRewardWithAmount(testRevenueReward, address(DUST), dustReward);
            _createRewardWithAmount(testRevenueReward, address(mockUSDC), usdcReward);
        }

        // Skip to next epoch boundary to make rewards claimable deterministically
        skipToNextEpoch(1);

        // --- Voting power documentation and assertions (at epoch start) ---
        // We validate the exact ve balances used for pro‑rata distribution.
        // For standard locks: ve(ts) = amount * (end - ts) / MAXTIME (linear decay)
        // For permanent locks: ve(ts) = amount (no decay, end == 0)
        // Given BaseTest sets ts%WEEK == 1, createLock rounding makes effective
        // durations = chosen - 1s. We assert balances at the epoch start after the skip.
        {
            uint256 epochStart = _getEpochStart(block.timestamp);
            uint256 totalExpectedVeAtEpoch;

            // tokenId 1: 100,000 DUST, MAXTIME (linear decay)
            {
                IDustLock.LockedBalance memory l1 = dustLock.locked(1);
                uint256 expectedVe1 = (uint256(l1.amount) * (l1.end - epochStart)) / MAXTIME;
                uint256 actualVe1 = dustLock.balanceOfNFTAt(1, epochStart);
                logWithTs("tokenId 1 ve expected/actual at epochStart");
                emit log_named_uint("expected", expectedVe1);
                emit log_named_uint("actual", actualVe1);
                assertTrue(!l1.isPermanent, "tokenId 1 should be non-permanent");
                assertEq(actualVe1, expectedVe1, "tokenId 1 ve mismatch at epochStart");
                totalExpectedVeAtEpoch += expectedVe1;
            }

            // tokenId 2: 10,000 DUST, PERMANENT (no decay)
            {
                IDustLock.LockedBalance memory l2 = dustLock.locked(2);
                uint256 expectedVe2 = uint256(l2.amount);
                uint256 actualVe2 = dustLock.balanceOfNFTAt(2, epochStart);
                logWithTs("tokenId 2 ve expected/actual at epochStart (permanent)");
                emit log_named_uint("expected", expectedVe2);
                emit log_named_uint("actual", actualVe2);
                assertTrue(l2.isPermanent, "tokenId 2 should be permanent");
                assertEq(l2.end, 0, "tokenId 2 permanent lock must have end == 0");
                assertEq(actualVe2, expectedVe2, "tokenId 2 ve mismatch at epochStart");
                // Also assert current == amount (permanent locks do not decay)
                assertEq(dustLock.balanceOfNFT(2), expectedVe2, "tokenId 2 current ve mismatch (permanent)");
                totalExpectedVeAtEpoch += expectedVe2;
            }

            // tokenId 3: 1,000 DUST, MAXTIME (linear decay)
            {
                IDustLock.LockedBalance memory l3 = dustLock.locked(3);
                uint256 expectedVe3 = (uint256(l3.amount) * (l3.end - epochStart)) / MAXTIME;
                uint256 actualVe3 = dustLock.balanceOfNFTAt(3, epochStart);
                logWithTs("tokenId 3 ve expected/actual at epochStart");
                emit log_named_uint("expected", expectedVe3);
                emit log_named_uint("actual", actualVe3);
                assertTrue(!l3.isPermanent, "tokenId 3 should be non-permanent");
                assertEq(actualVe3, expectedVe3, "tokenId 3 ve mismatch at epochStart");
                totalExpectedVeAtEpoch += expectedVe3;
            }

            // tokenId 4: 10,000 DUST, MAXTIME/4 (linear decay - lock created with MAXTIME/4)
            {
                IDustLock.LockedBalance memory l4 = dustLock.locked(4);
                uint256 expectedVe4 = (uint256(l4.amount) * (l4.end - epochStart)) / MAXTIME;
                uint256 actualVe4 = dustLock.balanceOfNFTAt(4, epochStart);
                logWithTs("tokenId 4 ve expected/actual at epochStart");
                emit log_named_uint("expected", expectedVe4);
                emit log_named_uint("actual", actualVe4);
                assertTrue(!l4.isPermanent, "tokenId 4 should be non-permanent");
                assertEq(actualVe4, expectedVe4, "tokenId 4 ve mismatch at epochStart");
                totalExpectedVeAtEpoch += expectedVe4;
            }

            // Aggregate sanity: sum of per-token ve equals totalSupply at epoch start (within a few wei)
            {
                uint256 totalSupplyAtEpoch = dustLock.totalSupplyAt(epochStart);
                logWithTs("Aggregate ve expected/actual at epochStart");
                emit log_named_uint("expected_total_ve", totalExpectedVeAtEpoch);
                emit log_named_uint("actual_total_ve", totalSupplyAtEpoch);
                // Minor 1-3 wei drift can occur due to WAD rounding in global slope/bias math.
                assertEqApprThreeWei(totalSupplyAtEpoch, totalExpectedVeAtEpoch);
            }
        }

        /*
         General deterministic setup and formula used for all expected values in this test:
         - Initial timestamp has ts%WEEK == 1 (from BaseTest), so createLock rounding makes
           effective durations = chosen - 1s.
         - Locks created:
           tokenId1 = 100,000 DUST, MAXTIME
           tokenId2 = 10,000 DUST, PERMANENT
           tokenId3 = 1,000 DUST, MAXTIME
           tokenId4 = 10,000 DUST, MAXTIME/4
         - We call skipToNextEpoch(1) so rewards are claimable at the next epoch; shares use
           ve balances at that epoch start.

         Pro‑rata formula (applies to DUST 18dec and USDC 6dec):
         - Let r_i = veBalance(tokenId_i, epochStart) / totalVe(epochStart).
         - share(tokenId_i, token) = floor(totalReward_token * r_i).
         - Totals in this test:
              totalReward_DUST  = 10,000 DUST  = 10,000e18 wei = 1e22 wei
              totalReward_USDC  = 10,000 USDC  = 10,000e6 units = 1e10 units
         - Calculations per user (using expected ve at epoch start):
             Denominator (totalExpectedVeAtEpoch) = 111_087_671_232_876_712_328_765
             r1 = expectedVe1 / total = 97_808_219_178_082_191_780_821 / 111_087_671_232_876_712_328_765 = 0.8804597134189952400917
             r2 = expectedVe2 / total = 10_000_000_000_000_000_000_000 / 111_087_671_232_876_712_328_765 = 0.0900189903075443312698
             r3 = expectedVe3 / total =    978_082_191_780_821_917_808 / 111_087_671_232_876_712_328_765 = 0.0088045971341899524009
             r4 = expectedVe4 / total =  2_301_369_863_013_698_630_136 / 111_087_671_232_876_712_328_765 = 0.0207166991392704762374
         - Deterministic r_i ratios (sum exactly 1.0 given the setup):
             r1 = 0.8804597134189952400917
             r2 = 0.0900189903075443312698
             r3 = 0.0088045971341899524009
             r4 = 0.0207166991392704762374
         - Therefore:
             expectedDustFor_i = floor(1e22 * r_i)
             expectedUsdcFor_i = floor(1e10 * r_i)
         - Rounding occurs once at the large total (not per 1‑unit); any remainder stays in the contract.
        */

        // tokenId 1 validation in its own scope to free locals early
        {
            /*
             tokenId 1 expected for 10,000 unit reward total:
             - Lock: 100,000 DUST, MAXTIME.
             - DUST: 8,804,597,134,189,952,400,917 wei (≈ 8,804.597134189952400917 DUST)
             - USDC: 8,804,597,134 units (≈ 8,804.597134 USDC)
             Calculation:
               r1 = 0.8804597134189952400917
               totalReward_DUST = 1e22 wei  => floor(1e22 * r1) = 8_804_597_134_189_952_400_917
               totalReward_USDC = 1e10 unit => floor(1e10 * r1) = 8_804_597_134
             - Derived via the general pro‑rata formula at the epoch start; rounding once at 10,000‑unit scale.
             */
            uint256 expectedDustFor1 = 8_804_597_134_189_952_400_917;
            uint256 expectedUsdcFor1 = 8_804_597_134;

            // Check that rewards can be claimed by lock holders
            uint256 dustPre = DUST.balanceOf(user1);
            uint256 usdcPre = mockUSDC.balanceOf(user1);

            vm.startPrank(user1);
            testRevenueReward.getReward(1, rewards);
            vm.stopPrank();

            uint256 dustPost = DUST.balanceOf(user1);
            uint256 usdcPost = mockUSDC.balanceOf(user1);

            // Verify exact reward amounts for tokenId 1
            uint256 dustReceived1 = dustPost - dustPre;
            uint256 usdcReceived1 = usdcPost - usdcPre;
            logWithTs("tokenId 1 DUST expected/actual");
            emit log_named_uint("expected", expectedDustFor1);
            emit log_named_uint("actual", dustReceived1);
            logWithTs("tokenId 1 USDC expected/actual");
            emit log_named_uint("expected", expectedUsdcFor1);
            emit log_named_uint("actual", usdcReceived1);
            assertEq(dustReceived1, expectedDustFor1, "tokenId 1 DUST amount incorrect");
            assertEq(usdcReceived1, expectedUsdcFor1, "tokenId 1 USDC amount incorrect");
            // aggregate sums
            dustSum += dustReceived1;
            usdcSum += usdcReceived1;
        }

        // tokenId 2 (user2) validation in its own scope to free locals early
        {
            /*
             tokenId 2 expected for 10,000 unit reward total:
             - Lock: 10,000 DUST, PERMANENT -> full MAXTIME-equivalent voting power at epoch start.
             - DUST: 900,189,903,075,443,312,698 wei (≈ 900.189903075443312698 DUST)
             - USDC: 900,189,903 units (≈ 900.189903 USDC)
             Calculation:
               r2 = 0.0900189903075443312698
               totalReward_DUST = 1e22 wei  => floor(1e22 * r2) = 900_189_903_075_443_312_698
               totalReward_USDC = 1e10 unit => floor(1e10 * r2) = 900_189_903
             - Same pro‑rata formula and rounding once at 10,000‑unit scale.
             */
            uint256 expectedDustFor2 = 900_189_903_075_443_312_698;
            uint256 expectedUsdcFor2 = 900_189_903;

            uint256 dustPre = DUST.balanceOf(user2);
            uint256 usdcPre = mockUSDC.balanceOf(user2);

            vm.startPrank(user2);
            testRevenueReward.getReward(2, rewards);
            vm.stopPrank();

            uint256 dustPost = DUST.balanceOf(user2);
            uint256 usdcPost = mockUSDC.balanceOf(user2);

            // Verify exact reward amounts for tokenId 2
            uint256 dustReceived2 = dustPost - dustPre;
            uint256 usdcReceived2 = usdcPost - usdcPre;
            logWithTs("tokenId 2 DUST expected/actual");
            emit log_named_uint("expected", expectedDustFor2);
            emit log_named_uint("actual", dustReceived2);
            logWithTs("tokenId 2 USDC expected/actual");
            emit log_named_uint("expected", expectedUsdcFor2);
            emit log_named_uint("actual", usdcReceived2);
            assertEq(dustReceived2, expectedDustFor2, "tokenId 2 DUST amount incorrect");
            assertEq(usdcReceived2, expectedUsdcFor2, "tokenId 2 USDC amount incorrect");
            // aggregate sums
            dustSum += dustReceived2;
            usdcSum += usdcReceived2;
        }

        // tokenId 3 (user3) validation in its own scope
        {
            /*
             tokenId 3 expected for 10,000 unit reward total:
             - Lock: 1,000 DUST, MAXTIME.
             - DUST: 88,045,971,341,899,524,009 wei (≈ 88.045971341899524009 DUST)
             - USDC: 88,045,971 units (≈ 88.045971 USDC)
             Calculation:
               r3 = 0.0088045971341899524009
               totalReward_DUST = 1e22 wei  => floor(1e22 * r3) = 88_045_971_341_899_524_009
               totalReward_USDC = 1e10 unit => floor(1e10 * r3) = 88_045_971
             - Same pro‑rata formula and rounding once at 10,000‑unit scale.
             */
            uint256 expectedDustFor3 = 88_045_971_341_899_524_009;
            uint256 expectedUsdcFor3 = 88_045_971;

            uint256 dustPre = DUST.balanceOf(user3);
            uint256 usdcPre = mockUSDC.balanceOf(user3);

            vm.startPrank(user3);
            testRevenueReward.getReward(3, rewards);
            vm.stopPrank();

            uint256 dustPost = DUST.balanceOf(user3);
            uint256 usdcPost = mockUSDC.balanceOf(user3);

            // Verify exact reward amounts for tokenId 3
            uint256 dustReceived3 = dustPost - dustPre;
            uint256 usdcReceived3 = usdcPost - usdcPre;
            logWithTs("tokenId 3 DUST expected/actual");
            emit log_named_uint("expected", expectedDustFor3);
            emit log_named_uint("actual", dustReceived3);
            logWithTs("tokenId 3 USDC expected/actual");
            emit log_named_uint("expected", expectedUsdcFor3);
            emit log_named_uint("actual", usdcReceived3);
            assertEq(dustReceived3, expectedDustFor3, "tokenId 3 DUST amount incorrect");
            assertEq(usdcReceived3, expectedUsdcFor3, "tokenId 3 USDC amount incorrect");
            // aggregate sums
            dustSum += dustReceived3;
            usdcSum += usdcReceived3;
        }

        // tokenId 4 (user4) validation in its own scope
        {
            /*
             tokenId 4 expected for 10,000 unit reward total:
             - Lock: 10,000 DUST for MAXTIME/4 => lower ve share at epoch start.
             - DUST: 207,166,991,392,704,762,374 wei (≈ 207.166991392704762374 DUST)
             - USDC: 207,166,991 units (≈ 207.166991 USDC)
             Calculation:
               r4 = 0.0207166991392704762374
               totalReward_DUST = 1e22 wei  => floor(1e22 * r4) = 207_166_991_392_704_762_374
               totalReward_USDC = 1e10 unit => floor(1e10 * r4) = 207_166_991
             - Same pro‑rata formula and rounding once at 10,000‑unit scale.
             */
            uint256 expectedDustFor4 = 207_166_991_392_704_762_374;
            uint256 expectedUsdcFor4 = 207_166_991;

            uint256 dustPre = DUST.balanceOf(user4);
            uint256 usdcPre = mockUSDC.balanceOf(user4);

            vm.startPrank(user4);
            testRevenueReward.getReward(4, rewards);
            vm.stopPrank();

            uint256 dustPost = DUST.balanceOf(user4);
            uint256 usdcPost = mockUSDC.balanceOf(user4);

            // Verify exact reward amounts for tokenId 4
            uint256 dustReceived4 = dustPost - dustPre;
            uint256 usdcReceived4 = usdcPost - usdcPre;
            logWithTs("tokenId 4 DUST expected/actual");
            emit log_named_uint("expected", expectedDustFor4);
            emit log_named_uint("actual", dustReceived4);
            logWithTs("tokenId 4 USDC expected/actual");
            emit log_named_uint("expected", expectedUsdcFor4);
            emit log_named_uint("actual", usdcReceived4);
            assertEq(dustReceived4, expectedDustFor4, "tokenId 4 DUST amount incorrect");
            assertEq(usdcReceived4, expectedUsdcFor4, "tokenId 4 USDC amount incorrect");
            // aggregate sums
            dustSum += dustReceived4;
            usdcSum += usdcReceived4;
        }

        // Aggregate distribution sanity checks: distributed + remainder == total notified
        {
            uint256 remainingDust = DUST.balanceOf(address(testRevenueReward));
            uint256 remainingUsdc = mockUSDC.balanceOf(address(testRevenueReward));

            logWithTs("Aggregate DUST distributed + remainder == total");
            emit log_named_uint("distributed_sum", dustSum);
            emit log_named_uint("remainder", remainingDust);
            emit log_named_uint("total_notified", TOKEN_10K);
            assertEq(dustSum + remainingDust, TOKEN_10K, "aggregate DUST distribution mismatch");

            logWithTs("Aggregate USDC distributed + remainder == total");
            emit log_named_uint("distributed_sum", usdcSum);
            emit log_named_uint("remainder", remainingUsdc);
            emit log_named_uint("total_notified", USDC_10K);
            assertEq(usdcSum + remainingUsdc, USDC_10K, "aggregate USDC distribution mismatch");
        }

        // Final per-user balances must match their exact expected rewards
        // Initial DUST/USDC balances for users are zero after locking, so final balances == rewards received
        {
            // user1
            {
                uint256 dustBal = DUST.balanceOf(user1);
                uint256 usdcBal = mockUSDC.balanceOf(user1);
                uint256 expectedDust = 8_804_597_134_189_952_400_917;
                uint256 expectedUsdc = 8_804_597_134;
                logWithTs("user1 final DUST expected/actual");
                emit log_named_uint("expected", expectedDust);
                emit log_named_uint("actual", dustBal);
                logWithTs("user1 final USDC expected/actual");
                emit log_named_uint("expected", expectedUsdc);
                emit log_named_uint("actual", usdcBal);
                assertEq(dustBal, expectedDust, "user1 final DUST balance mismatch");
                assertEq(usdcBal, expectedUsdc, "user1 final USDC balance mismatch");
            }
            // user2
            {
                uint256 dustBal = DUST.balanceOf(user2);
                uint256 usdcBal = mockUSDC.balanceOf(user2);
                uint256 expectedDust = 900_189_903_075_443_312_698;
                uint256 expectedUsdc = 900_189_903;
                logWithTs("user2 final DUST expected/actual");
                emit log_named_uint("expected", expectedDust);
                emit log_named_uint("actual", dustBal);
                logWithTs("user2 final USDC expected/actual");
                emit log_named_uint("expected", expectedUsdc);
                emit log_named_uint("actual", usdcBal);
                assertEq(dustBal, expectedDust, "user2 final DUST balance mismatch");
                assertEq(usdcBal, expectedUsdc, "user2 final USDC balance mismatch");
            }
            // user3
            {
                uint256 dustBal = DUST.balanceOf(user3);
                uint256 usdcBal = mockUSDC.balanceOf(user3);
                uint256 expectedDust = 88_045_971_341_899_524_009;
                uint256 expectedUsdc = 88_045_971;
                logWithTs("user3 final DUST expected/actual");
                emit log_named_uint("expected", expectedDust);
                emit log_named_uint("actual", dustBal);
                logWithTs("user3 final USDC expected/actual");
                emit log_named_uint("expected", expectedUsdc);
                emit log_named_uint("actual", usdcBal);
                assertEq(dustBal, expectedDust, "user3 final DUST balance mismatch");
                assertEq(usdcBal, expectedUsdc, "user3 final USDC balance mismatch");
            }
            // user4
            {
                uint256 dustBal = DUST.balanceOf(user4);
                uint256 usdcBal = mockUSDC.balanceOf(user4);
                uint256 expectedDust = 207_166_991_392_704_762_374;
                uint256 expectedUsdc = 207_166_991;
                logWithTs("user4 final DUST expected/actual");
                emit log_named_uint("expected", expectedDust);
                emit log_named_uint("actual", dustBal);
                logWithTs("user4 final USDC expected/actual");
                emit log_named_uint("expected", expectedUsdc);
                emit log_named_uint("actual", usdcBal);
                assertEq(dustBal, expectedDust, "user4 final DUST balance mismatch");
                assertEq(usdcBal, expectedUsdc, "user4 final USDC balance mismatch");
            }
        }
    }

    function testBasicRewardDistribution() public {
        address[] memory rewards = new address[](1);
        rewards[0] = address(DUST);

        // Create some rewards
        _createRewardWithAmount(testRevenueReward, address(DUST), TOKEN_1);

        // Skip to next epoch boundary to make rewards claimable deterministically
        skipToNextEpoch(1);

        // Check initial balance
        uint256 balanceBefore = DUST.balanceOf(user1);

        // Claim rewards
        vm.startPrank(user1);
        testRevenueReward.getReward(1, rewards);
        vm.stopPrank();

        // Verify rewards were received
        uint256 balanceAfter = DUST.balanceOf(user1);
        uint256 received = balanceAfter - balanceBefore;
        /*
         Calculations for expected tokenId 1 share (1 DUST reward):
         - Reward: 1 DUST (18 decimals).
         - share = floor(1e18 * veBalance(tokenId1, epochStart) / totalVe(epochStart)).
         - With the deterministic setup and epoch alignment (ts%WEEK == 1), this equals
           880,459,713,418,995,240 wei (≈ 0.880459713418995240 DUST).
         - Matches the per‑1‑unit constants used above.
         */
        uint256 expected = 880_459_713_418_995_240; // tokenId1 share for 1e18
        logWithTs("tokenId 1 DUST expected/actual");
        emit log_named_uint("expected", expected);
        emit log_named_uint("actual", received);
        assertEq(received, expected, "tokenId 1 DUST amount incorrect");
    }

    function testVotingPowerBasedRewardPrecision() public {
        // Deterministic precision test with large reward to ensure ratios hold exactly
        address[] memory rewards = new address[](1);
        rewards[0] = address(DUST);

        uint256 rewardAmount = TOKEN_1 * 1000; // 1,000 DUST
        _createRewardWithAmount(testRevenueReward, address(DUST), rewardAmount);

        // Skip time to make rewards claimable
        skipToNextEpoch(1);

        // Claim rewards and measure distribution
        uint256 balance1Before = DUST.balanceOf(user1);
        vm.startPrank(user1);
        testRevenueReward.getReward(1, rewards);
        vm.stopPrank();
        uint256 balance1After = DUST.balanceOf(user1);
        uint256 reward1 = balance1After - balance1Before;

        uint256 balance4Before = DUST.balanceOf(user4);
        vm.startPrank(user4);
        testRevenueReward.getReward(4, rewards);
        vm.stopPrank();
        uint256 balance4After = DUST.balanceOf(user4);
        uint256 reward4 = balance4After - balance4Before;

        /*
         Expected exact amounts for 1,000 DUST (deterministic rounding):
         - Use the same pro‑rata ratio at epoch start, but apply it to 1000e18 once:
             expected = floor(1000e18 * veBalance(tokenId) / totalVe).
         - Not exactly 1000x of the 1‑DUST constants because rounding occurs once at the larger scale
           (e.g., tokenId1 adds +91 wei; tokenId4 adds +237 wei compared to 1000x).
         - tokenId1: 880,459,713,418,995,240,091 wei.
         - tokenId4: 20,716,699,139,270,476,237 wei.
         */
        uint256 expected1 = 880_459_713_418_995_240_091; // tokenId1 (1000x)
        uint256 expected4 = 20_716_699_139_270_476_237; // tokenId4 (1000x)

        logWithTs("tokenId 1 DUST expected/actual (1000x)");
        emit log_named_uint("expected", expected1);
        emit log_named_uint("actual", reward1);
        logWithTs("tokenId 4 DUST expected/actual (1000x)");
        emit log_named_uint("expected", expected4);
        emit log_named_uint("actual", reward4);

        assertEq(reward1, expected1, "tokenId 1 DUST amount incorrect (1000x)");
        assertEq(reward4, expected4, "tokenId 4 DUST amount incorrect (1000x)");
    }
}
