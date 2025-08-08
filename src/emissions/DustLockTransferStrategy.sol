// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {DustTransferStrategyBase} from "./DustTransferStrategyBase.sol";
import {GPv2SafeERC20} from "@aave/core-v3/contracts/dependencies/gnosis/contracts/GPv2SafeERC20.sol";
import {IERC20} from "@aave/core-v3/contracts/dependencies/openzeppelin/contracts/IERC20.sol";
import {IDustLock} from "../interfaces/IDustLock.sol";
import {IDustLockTransferStrategy, IDustTransferStrategy} from "../interfaces/IDustLockTransferStrategy.sol";
import {AddressZero, InvalidTokenId} from "../_shared/CommonErrors.sol";

/**
 * @title DustLockTransferStrategy
 * @notice Transfer strategy for DUST rewards, that sends user veDUST lock
 *         created from DUST rewards, or allows for early withdrawal.
 *         Adding DUST to an existing veDUST lock is also supported.
 * @author Neverland
 */
contract DustLockTransferStrategy is DustTransferStrategyBase, IDustLockTransferStrategy {
    using GPv2SafeERC20 for IERC20;

    /**
     * @notice The DustLock contract that manages veNFTs
     * @dev Used for creating new locks, adding to existing locks, and checking ownership
     */
    IDustLock public immutable DUST_LOCK;

    /**
     * @notice The vault address where DUST rewards are stored before distribution
     * @dev Rewards are transferred from this vault when they are claimed
     */
    address public immutable DUST_VAULT;

    /**
     * @notice The DUST token address
     * @dev Retrieved from the DUST_LOCK contract during construction
     */
    address public immutable DUST;

    constructor(address incentivesController, address rewardsAdmin, address dustVault, address dustLock)
        DustTransferStrategyBase(incentivesController, rewardsAdmin)
    {
        DUST_VAULT = dustVault;
        DUST_LOCK = IDustLock(dustLock);
        DUST = DUST_LOCK.token();
    }

    /// @inheritdoc DustTransferStrategyBase
    function performTransfer(address to, address reward, uint256 amount, uint256 lockTime, uint256 tokenId)
        external
        override(DustTransferStrategyBase, IDustTransferStrategy)
        onlyIncentivesController
        returns (bool)
    {
        // Gracefully handle zero amount transfers
        if (amount == 0) return true;
        if (to == address(0)) revert AddressZero();
        if (reward != DUST) revert InvalidRewardAddress();
        IERC20(reward).safeTransferFrom(DUST_VAULT, address(this), amount);
        // If tokenId is greater than 0, it means we are merging emissions with an existing lock
        // If tokenId is 0, it means we are creating a new lock or performing an early withdrawal
        if (tokenId > 0) {
            // Add DUST to an existing lock
            if (DUST_LOCK.ownerOf(tokenId) == address(0)) revert InvalidTokenId();
            if (DUST_LOCK.ownerOf(tokenId) != to) revert NotTokenOwner();
            IERC20(reward).approve(address(DUST_LOCK), amount);
            DUST_LOCK.depositFor(tokenId, amount);
        } else if (lockTime > 0) {
            // Create a new lock
            IERC20(reward).approve(address(DUST_LOCK), amount);
            DUST_LOCK.createLockFor(amount, lockTime, to);
        } else {
            // Early withdrawal w/ penalty
            uint256 treasuryValue = (amount * DUST_LOCK.earlyWithdrawPenalty()) / 10_000;
            IERC20(reward).safeTransfer(to, amount - treasuryValue);
            IERC20(reward).safeTransfer(DUST_LOCK.earlyWithdrawTreasury(), treasuryValue);
        }
        return true;
    }

    /**
     * @notice Returns the address of the vault holding DUST rewards
     * @dev This vault must approve this contract to transfer DUST tokens
     * @return The address of the DUST_VAULT
     */
    function getDustVault() external view returns (address) {
        return DUST_VAULT;
    }
}
