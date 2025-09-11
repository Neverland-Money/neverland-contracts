// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

/**
 * @title IUserVaultFactory
 * @author Neverland
 * @notice Interface for the UserVaultFactory contract.
 *         Allows creation and retrieval of user-specific vaults.
 */
interface IUserVaultFactory {
    /// @notice Emitted when a concurrent vault creation for the same user is in progress
    error CreationInProgress();

    /*//////////////////////////////////////////////////////////////
                                VIEWS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the vault address for a given user. Creates a new vault if none exists
     * @dev If the vault does not exist, a new BeaconProxy is deployed and initialized for the user
     * @param user The address of the user whose vault is being queried or created
     * @return vault The address of the user's vault
     */
    function getUserVault(address user) external view returns (address vault);

    /*//////////////////////////////////////////////////////////////
                               ACTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the vault address for a given user if it exists
     * @dev If the vault does not exist, returns address(0)
     * @param user The address of the user whose vault is being queried or created
     * @return vault The address of the user's vault
     */
    function getOrCreateUserVault(address user) external returns (address vault);
}
