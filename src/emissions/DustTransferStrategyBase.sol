// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.30;

import {GPv2SafeERC20} from "@aave/core-v3/contracts/dependencies/gnosis/contracts/GPv2SafeERC20.sol";
import {IERC20} from "@aave/core-v3/contracts/dependencies/openzeppelin/contracts/IERC20.sol";

import {IDustTransferStrategy} from "../interfaces/IDustTransferStrategy.sol";

import {CommonChecksLibrary} from "../libraries/CommonChecksLibrary.sol";

/**
 * @title DustTransferStrategyBase
 * @author Original implementation by Aave
 * @author Extended by Neverland
 * @notice Modified Aave's TransferStrategyBase contract to pass lockTime and
 *         tokenId to the `IDustTransferStrategy`.
 */
abstract contract DustTransferStrategyBase is IDustTransferStrategy {
    using GPv2SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                          STORAGE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @dev The incentives controller contract address
    address internal immutable INCENTIVES_CONTROLLER;

    /// @dev The rewards admin address for administrative functions
    address internal immutable REWARDS_ADMIN;

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Constructs the base transfer strategy
     * @param incentivesController The incentives controller authorized to call performTransfer
     * @param rewardsAdmin The rewards admin authorized for emergency actions
     */
    constructor(address incentivesController, address rewardsAdmin) {
        CommonChecksLibrary.revertIfZeroAddress(incentivesController);
        CommonChecksLibrary.revertIfZeroAddress(rewardsAdmin);

        INCENTIVES_CONTROLLER = incentivesController;
        REWARDS_ADMIN = rewardsAdmin;
    }

    /*//////////////////////////////////////////////////////////////
                           ACCESS CONTROL
    //////////////////////////////////////////////////////////////*/

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

    /*//////////////////////////////////////////////////////////////
                                VIEWS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IDustTransferStrategy
    function getIncentivesController() external view override returns (address) {
        return INCENTIVES_CONTROLLER;
    }

    /// @inheritdoc IDustTransferStrategy
    function getRewardsAdmin() external view override returns (address) {
        return REWARDS_ADMIN;
    }

    /*//////////////////////////////////////////////////////////////
                         TRANSFER STRATEGY
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IDustTransferStrategy
    function performTransfer(address to, address reward, uint256 amount, uint256 lockTime, uint256 tokenId)
        external
        virtual
        returns (bool);

    /*//////////////////////////////////////////////////////////////
                               ADMIN
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IDustTransferStrategy
    function emergencyWithdrawal(address token, address to, uint256 amount) external onlyRewardsAdmin {
        IERC20(token).safeTransfer(to, amount);

        emit EmergencyWithdrawal(msg.sender, token, to, amount);
    }
}
