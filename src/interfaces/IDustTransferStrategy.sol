// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

/**
 * @title IDustTransferStrategy
 * @author Aave
 * @author Neverland
 * @notice Modified Aave's `ITransferStrategyBase` contract to add lockTime
 *         and tokenId to the `performTransfer()` function.
 */
interface IDustTransferStrategy {
    /// Errors

    /// @notice Error thrown when the caller is not the incentives controller
    error CallerNotIncentivesController();

    /// @notice Error thrown when the caller is not the rewards admin
    error OnlyRewardsAdmin();

    /// Events

    /// @notice Emitted when an emergency withdrawal is performed
    event EmergencyWithdrawal(address indexed caller, address indexed token, address indexed to, uint256 amount);

    /// Functions

    /**
     * @dev Perform custom transfer logic via delegate call from source contract to a TransferStrategy implementation
     * @dev If `tokenId` is specified it's owner has to be `to`
     * @param to Account to transfer rewards
     * @param reward Address of the reward token
     * @param amount Amount to transfer to the "to" address parameter
     * @param lockTime Lock duration, or 0 for early exit
     * @param tokenId Token ID to merge the emissions with, or 0 for no merge
     * @return Returns true bool if transfer logic succeeds
     */
    function performTransfer(address to, address reward, uint256 amount, uint256 lockTime, uint256 tokenId)
        external
        returns (bool);

    /// @return Returns the address of the Incentives Controller
    function getIncentivesController() external view returns (address);

    /// @return Returns the address of the Rewards admin
    function getRewardsAdmin() external view returns (address);

    /**
     * @dev Perform an emergency token withdrawal only callable by the Rewards admin
     * @param token Address of the token to withdraw funds from this contract
     * @param to Address of the recipient of the withdrawal
     * @param amount Amount of the withdrawal
     */
    function emergencyWithdrawal(address token, address to, uint256 amount) external;
}
