// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.30;

/**
 * @title IDustTransferStrategy
 * @author Original implementation by Aave
 * @author Extended by Neverland
 * @notice Extended Aave's `ITransferStrategyBase` interface to add lockTime
 *         and tokenId parameters to the `performTransfer()` function.
 *         Added emergency withdrawal functionality.
 */
interface IDustTransferStrategy {
    /// @notice Error thrown when the caller is not the incentives controller
    error CallerNotIncentivesController();

    /// @notice Error thrown when the caller is not the rewards admin
    error OnlyRewardsAdmin();

    /**
     * @notice Emitted when an emergency withdrawal is performed
     * @param caller The rewards admin that performed the withdrawal
     * @param token The token address withdrawn from this strategy
     * @param to The recipient of the withdrawn tokens
     * @param amount The amount of tokens withdrawn
     */
    event EmergencyWithdrawal(address indexed caller, address indexed token, address indexed to, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                                 VIEWS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the address of the Incentives Controller
     * @return The Incentives Controller address
     */
    function getIncentivesController() external view returns (address);

    /**
     * @notice Returns the address of the Rewards admin
     * @return The rewards admin address
     */
    function getRewardsAdmin() external view returns (address);

    /*//////////////////////////////////////////////////////////////
                         TRANSFER STRATEGY
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Perform custom transfer logic via delegate call from source contract to a TransferStrategy implementation
     * @dev If `tokenId` is specified it's owner has to be `to`
     *      DUST_VAULT pre-approves infinite amount of `reward` to this contract
     * @param to Account to transfer rewards to
     * @param reward Address of the reward token
     * @param amount Amount of the reward token to transfer
     * @param lockTime Lock duration, or 0 for early exit
     * @param tokenId Token ID to merge the emissions with, or 0 for no merge
     * @return Returns true if transfer logic succeeds
     */
    function performTransfer(address to, address reward, uint256 amount, uint256 lockTime, uint256 tokenId)
        external
        returns (bool);

    /*//////////////////////////////////////////////////////////////
                                 ADMIN
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Perform an emergency token withdrawal (admin only)
     * @dev Only callable by the rewards admin to recover tokens from this strategy contract
     * @param token Address of the token to withdraw funds from this contract
     * @param to Address of the recipient of the withdrawal
     * @param amount Amount of the withdrawal
     */
    function emergencyWithdrawal(address token, address to, uint256 amount) external;
}
