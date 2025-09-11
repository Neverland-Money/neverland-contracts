// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {GPv2SafeERC20} from "@aave/core-v3/contracts/dependencies/gnosis/contracts/GPv2SafeERC20.sol";
import {IERC20} from "@aave/core-v3/contracts/dependencies/openzeppelin/contracts/IERC20.sol";
import {SafeERC20} from "@aave/core-v3/contracts/dependencies/openzeppelin/contracts/SafeERC20.sol";

import {IDustLock} from "../interfaces/IDustLock.sol";
import {IDustLockTransferStrategy, IDustTransferStrategy} from "../interfaces/IDustLockTransferStrategy.sol";

import {CommonChecksLibrary} from "../libraries/CommonChecksLibrary.sol";

import {DustTransferStrategyBase} from "./DustTransferStrategyBase.sol";

/**
 * @title DustLockTransferStrategy
 * @author Neverland
 * @notice Transfer strategy for DUST rewards, that sends user veDUST lock
 *         created from DUST rewards, or allows for early withdrawal.
 *         Adding DUST to an existing veDUST lock is also supported.
 */
contract DustLockTransferStrategy is DustTransferStrategyBase, IDustLockTransferStrategy {
    using GPv2SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                             CONSTANTS
    //////////////////////////////////////////////////////////////*/

    uint256 internal constant BASIS_POINTS = 10_000;

    /*//////////////////////////////////////////////////////////////
                          STORAGE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IDustLockTransferStrategy
    IDustLock public immutable DUST_LOCK;

    /// @inheritdoc IDustLockTransferStrategy
    address public immutable DUST_VAULT;

    /// @inheritdoc IDustLockTransferStrategy
    address public immutable DUST;

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Constructs the DUST lock transfer strategy
     * @param incentivesController The incentives controller authorized to call performTransfer
     * @param rewardsAdmin The rewards admin allowed to emergency withdraw tokens
     * @param dustVault The vault address that holds DUST balances
     * @param dustLock The DustLock contract address
     */
    constructor(address incentivesController, address rewardsAdmin, address dustVault, address dustLock)
        DustTransferStrategyBase(incentivesController, rewardsAdmin)
    {
        CommonChecksLibrary.revertIfZeroAddress(incentivesController);
        CommonChecksLibrary.revertIfZeroAddress(rewardsAdmin);
        CommonChecksLibrary.revertIfZeroAddress(dustVault);
        CommonChecksLibrary.revertIfZeroAddress(dustLock);

        DUST_VAULT = dustVault;
        DUST_LOCK = IDustLock(dustLock);
        DUST = DUST_LOCK.token();
    }

    /*//////////////////////////////////////////////////////////////
                         TRANSFER STRATEGY
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc DustTransferStrategyBase
    function performTransfer(address to, address reward, uint256 amount, uint256 lockTime, uint256 tokenId)
        external
        override(DustTransferStrategyBase, IDustTransferStrategy)
        onlyIncentivesController
        returns (bool)
    {
        // Gracefully handle zero amount transfers
        if (amount == 0) return true;
        CommonChecksLibrary.revertIfInvalidToAddress(to);
        if (reward != DUST) revert InvalidRewardAddress();

        IERC20 rewardToken = IERC20(reward);
        rewardToken.safeTransferFrom(DUST_VAULT, address(this), amount);

        // tokenId > 0                      -> add DUST to existing veDUST;
        // tokenId == 0 && lockTime > 0     -> create new veDUST lock;
        // tokenId == 0 && lockTime == 0    -> direct DUST transfer with earlyWithdrawPenalty;
        if (tokenId > 0) {
            // Add DUST to existing veDUST
            address owner = DUST_LOCK.ownerOf(tokenId);
            if (owner != to) revert NotTokenOwner();
            SafeERC20.safeIncreaseAllowance(rewardToken, address(DUST_LOCK), amount);
            DUST_LOCK.depositFor(tokenId, amount);
            SafeERC20.safeApprove(rewardToken, address(DUST_LOCK), 0);
        } else if (lockTime > 0) {
            // Create new veDUST lock
            SafeERC20.safeIncreaseAllowance(rewardToken, address(DUST_LOCK), amount);
            DUST_LOCK.createLockFor(amount, lockTime, to);
            SafeERC20.safeApprove(rewardToken, address(DUST_LOCK), 0);
        } else {
            // Direct transfer with earlyWithdrawPenalty; overflow impossible within uint256 range
            uint256 treasuryValue = (amount * DUST_LOCK.earlyWithdrawPenalty()) / BASIS_POINTS;
            address treasury = DUST_LOCK.earlyWithdrawTreasury();
            CommonChecksLibrary.revertIfZeroAddress(treasury);

            rewardToken.safeTransfer(to, amount - treasuryValue);
            rewardToken.safeTransfer(treasury, treasuryValue);
        }
        return true;
    }
}
