// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "../BaseTest.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {RevenueReward} from "../../src/rewards/RevenueReward.sol";

/// @dev Contains helpful functions for voting power precision and decay testing
abstract contract ExtendedBaseTest is BaseTest {
    // Precision used in calculating rewards
    // 1e12 relative precision implies acceptable error of 1e-6 * expected value
    // e.g. if we expect 1e18, precision of 1e12 means we will accept values of
    // 1e18 +- (1e6 * 1e12 / 1e18)
    uint256 public immutable PRECISION = 1e12;

    // RevenueReward instances for precision testing
    RevenueReward internal testRevenueReward;
    RevenueReward internal testRevenueReward2;
    RevenueReward internal testRevenueReward3;

    function _setUp() internal virtual override {
        super._setUp();

        // Initialize RevenueReward instances for precision testing
        // Use user (address(this)) as rewardDistributor instead of admin (proxy admin)
        testRevenueReward = new RevenueReward(address(0xF2), address(dustLock), user);
        testRevenueReward2 = new RevenueReward(address(0xF3), address(dustLock), user);
        testRevenueReward3 = new RevenueReward(address(0xF4), address(dustLock), user);
    }

    function _createRewardWithAmount(RevenueReward _revenueReward, address _token, uint256 _amount) internal {
        // Mint tokens directly to user (rewardDistributor) to avoid transfer issues
        deal(_token, user, IERC20(_token).balanceOf(user) + _amount);

        // user (address(this)) is the rewardDistributor, so we can call directly
        IERC20(_token).approve(address(_revenueReward), _amount);
        _revenueReward.notifyRewardAmount(address(_token), _amount);
    }
}
