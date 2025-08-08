// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import {IDustTransferStrategy} from "../interfaces/IDustTransferStrategy.sol";
import {GPv2SafeERC20} from "@aave/core-v3/contracts/dependencies/gnosis/contracts/GPv2SafeERC20.sol";
import {IERC20} from "@aave/core-v3/contracts/dependencies/openzeppelin/contracts/IERC20.sol";

/**
 * @title DustTransferStrategyBase
 * @notice Modified Aave's TransferStrategyBase contract to pass lockTime and
 *         tokenId to the `IDustTransferStrategy`.
 * @author Aave
 * @author Neverland
 */
abstract contract DustTransferStrategyBase is IDustTransferStrategy {
    using GPv2SafeERC20 for IERC20;

    address internal immutable INCENTIVES_CONTROLLER;
    address internal immutable REWARDS_ADMIN;

    constructor(address incentivesController, address rewardsAdmin) {
        INCENTIVES_CONTROLLER = incentivesController;
        REWARDS_ADMIN = rewardsAdmin;
    }

    /// @dev Modifier for incentives controller only functions
    modifier onlyIncentivesController() {
        if (INCENTIVES_CONTROLLER != msg.sender) revert CallerNotIncentivesController();
        _;
    }

    /// @dev Modifier for reward admin only functions
    modifier onlyRewardsAdmin() {
        if (msg.sender != REWARDS_ADMIN) revert OnlyRewardsAdmin();
        _;
    }

    /// @inheritdoc IDustTransferStrategy
    function getIncentivesController() external view override returns (address) {
        return INCENTIVES_CONTROLLER;
    }

    /// @inheritdoc IDustTransferStrategy
    function getRewardsAdmin() external view override returns (address) {
        return REWARDS_ADMIN;
    }

    /// @inheritdoc IDustTransferStrategy
    function performTransfer(address to, address reward, uint256 amount, uint256 lockTime, uint256 tokenId)
        external
        virtual
        returns (bool);

    /// @inheritdoc IDustTransferStrategy
    function emergencyWithdrawal(address token, address to, uint256 amount) external onlyRewardsAdmin {
        IERC20(token).safeTransfer(to, amount);

        emit EmergencyWithdrawal(msg.sender, token, to, amount);
    }
}
