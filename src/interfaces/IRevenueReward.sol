// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {IDustLock} from "../interfaces/IDustLock.sol";
import {IUserVaultFactory} from "./IUserVaultFactory.sol";

/**
 * @title IRevenueReward Interface
 * @notice Interface for the RevenueReward contract that manages token rewards distribution
 * @dev Handles reward epochs, claiming rewards, and self-repaying loan functionality
 */
interface IRevenueReward {
    /**
     * @notice Emitted when rewards are claimed by a user
     * @param user Address that claimed the rewards
     * @param token Address of the reward token being claimed
     * @param amount Amount of rewards claimed
     */
    event ClaimRewards(address indexed user, address indexed token, uint256 amount);

    /**
     * @notice Emitted when new rewards are notified to the contract
     * @param from Address that notified the rewards (typically the reward distributor)
     * @param token Address of the reward token being added
     * @param epoch Reward epoch number for the notification
     * @param amount Amount of rewards added
     */
    event NotifyReward(address indexed from, address indexed token, uint256 epoch, uint256 amount);

    /**
     * @notice Emitted when tokens are recovered from the contract
     * @param token Address of the token being recovered
     * @param amount Amount of tokens recovered
     */
    event RecoverTokens(address indexed token, uint256 amount);

    /**
     * @notice Emitted when self-repaying loan status is updated for a token
     * @param token ID of the veNFT whose reward redirection is being configured
     * @param rewardReceiver Address that will receive the rewards (or zero address if disabled)
     * @param isEnabled Whether self-repaying loan is being enabled (true) or disabled (false)
     */
    event SelfRepayingLoanUpdate(uint256 indexed token, address rewardReceiver, bool isEnabled);

    /// @notice Error thrown when attempting to notify or claim with a zero amount
    error ZeroAmount();

    /// @notice Error thrown when a non-distributor address attempts to notify rewards
    error NotRewardDistributor();

    /// @notice Error thrown when a non-owner address attempts a restricted operation
    error NotOwner();

    /// @notice Error thrown when a non-DustLock address attempts a restricted operation
    error NotDustLock();

    /**
     * @notice The address of the DustLock contract that manages veNFTs
     * @return The IDustLock interface of the connected DustLock contract
     */
    function dustLock() external view returns (IDustLock);

    /**
     * @notice The address of the UserVaultFactory contract that manages user vaults
     * @return The IUserVaultFactory interface of the connected UserVaultFactory contract
     */
    function userVaultFactory() external view returns (IUserVaultFactory);

    /**
     * @notice The duration of a reward epoch in seconds
     * @dev This defines the time window for each reward distribution cycle
     * @return Duration in seconds for each reward epoch
     */
    function DURATION() external view returns (uint256);

    /**
     * @notice Returns the timestamp of the last reward claim for a specific token and veNFT
     * @dev Used to calculate the amount of rewards earned since the last claim
     * @param token The address of the reward token
     * @param tokenId The ID of the veNFT
     * @return The timestamp (in seconds) when rewards were last claimed
     */
    function lastEarnTime(address token, uint256 tokenId) external view returns (uint256);

    /**
     * @notice Returns the address authorized to add rewards to the contract
     * @dev This address is the only one that can call notifyRewardAmount
     *      Typically set to a protocol treasury or governance-controlled address
     * @return The current reward distributor address
     */
    function rewardDistributor() external view returns (address);

    /**
     * @notice Checks if a token is registered as a valid reward token
     * @dev Only registered reward tokens can be distributed through the contract
     *      Tokens are registered automatically the first time they're used in notifyRewardAmount
     * @param token The address of the token to check
     * @return True if the token is registered as a reward token, false otherwise
     */
    function isRewardToken(address token) external view returns (bool);

    /**
     * @notice Returns the reward token at a specific index in the list of registered reward tokens
     * @dev Used to enumerate all reward tokens available in the contract
     *      Valid indices range from 0 to the number of registered reward tokens minus 1
     * @param index The index in the reward tokens array
     * @return The address of the reward token at the specified index
     */
    function rewardTokens(uint256 index) external view returns (address);

    /**
     * @notice Returns the accumulated sum of all reward distributions for a specific token
     * @dev Used for internal reward accounting and distribution calculations
     *      This value increases each time new rewards are notified
     * @param token The address of the reward token
     * @return The total amount of rewards ever distributed for this token
     */
    function totalRewardsPerToken(address token) external view returns (uint256);

    /**
     * @notice Returns the amount of rewards allocated for a specific token in a given epoch
     * @dev Rewards are distributed per epoch, with each epoch lasting for DURATION seconds
     *      Used to calculate the reward rate for a particular token during a specific epoch
     * @param token The address of the reward token
     * @param epoch The epoch number to query
     * @return The amount of rewards allocated for the specified token in the given epoch
     */
    function tokenRewardsPerEpoch(address token, uint256 epoch) external view returns (uint256);

    /**
     * @notice Returns the configured reward recipient address for a specific veNFT
     * @dev When self-repaying loan functionality is enabled, rewards are sent to this address
     *      Returns address(0) if no special recipient is configured (rewards go to veNFT owner)
     * @param tokenId The ID of the veNFT to query
     * @return The address that receives rewards for this veNFT, or address(0) if it's the owner
     */
    function tokenRewardReceiver(uint256 tokenId) external view returns (address);

    /**
     * @notice Claims accumulated rewards for a specific veNFT across multiple reward tokens
     * @dev Calculates earned rewards for each specified token and transfers them to the appropriate recipient
     *      If a reward receiver is configured via enableSelfRepayLoan, rewards go to that address
     *      Otherwise, rewards are sent to the veNFT owner
     *      Updates lastEarnTime for each claimed token to track future reward accruals
     * @param tokenId The ID of the veNFT to claim rewards for
     * @param tokens Array of reward token addresses to claim (must be registered reward tokens)
     */
    function getReward(uint256 tokenId, address[] memory tokens) external;

    /**
     * @notice Enables the self-repaying loan feature for a specific veNFT
     * @dev Configures a custom reward receiver address (typically a loan contract)
     *      This allows veNFT owners to use their rewards to automatically repay loans
     *      The getReward function must still be called to trigger the reward claim
     *      Can only be called by the veNFT owner
     * @param tokenId The ID of the veNFT to configure
     */
    function enableSelfRepayLoan(uint256 tokenId) external;

    /**
     * @notice Disables the self-repaying loan feature for a specific veNFT
     * @dev Removes the custom reward receiver configuration, returning to default behavior
     *      After disabling, all future rewards will go directly to the veNFT owner
     *      Can only be called by the veNFT owner
     * @param tokenId The ID of the veNFT to restore default reward routing for
     */
    function disableSelfRepayLoan(uint256 tokenId) external;

    /**
     * @notice Notifies the contract that a specific token has been transferred.
     * @dev Intended to update internal state or trigger logic after a veNFT transfer event.
     *      Can only be called by authorized contracts, typically after a transfer operation.
     * @param _tokenId The ID of the token (veNFT) that has been transferred.
     * @param _from The owner of token transferred.
     */
    function _notifyTokenTransferred(uint256 _tokenId, address _from) external;

    /**
     * @notice Notifies the contract that a specific token has been burned.
     * @dev Intended to update internal state or trigger logic after a veNFT burn event.
     *      Can only be called by authorized contracts, typically after a burn operation.
     * @param _tokenId The ID of the token (veNFT) that has been burned.
     * @param _from The owner of token burned.
     */
    function _notifyTokenBurned(uint256 _tokenId, address _from) external;

    /**
     * @notice Returns a list of user addresses with at least one active self-repaying loan within a given range.
     * @dev Iterates over the internal set of users who have enabled self-repaying loans,
     *      returning addresses from index `from` up to, but not including, index `to`.
     *      If the specified range exceeds the number of users, the function adjusts accordingly.
     * @param from The starting index (inclusive) in the user set.
     * @param to The ending index (exclusive) in the user set.
     * @return users An array of user addresses in the specified range who have self-repaying loans enabled.
     */
    function getUsersWithSelfRepayingLoan(uint256 from, uint256 to) external view returns (address[] memory);

    /**
     * @notice Returns the list of token IDs for which the given user has enabled a self-repaying loan.
     * @dev Checks the user's internal set of token IDs with self-repaying loans and returns them as an array.
     * @param user The address of the user to query.
     * @return tokenIds An array of token IDs currently associated with self-repaying loans for the user.
     */
    function getUserTokensWithSelfRepayingLoan(address user) external view returns (uint256[] memory tokenIds);

    /**
     * @notice Adds new rewards to the distribution pool for the current epoch
     * @dev Can only be called by the authorized reward distributor address
     *      Automatically registers new tokens the first time they're used
     *      Rewards added during the current epoch become claimable in the next epoch
     *      Emits a NotifyReward event with details about the distribution
     * @param token The address of the reward token to distribute
     * @param amount The amount of rewards to add to the distribution pool
     */
    function notifyRewardAmount(address token, uint256 amount) external;

    /**
     * @notice Notifies the contract that a new token has been created
     * @dev Intended to update internal state or trigger logic after a veNFT creation event
     *      Can only be called by authorized contracts, typically after a creation operation
     * @param _tokenId The ID of the token (veNFT) that has been created
     */
    function _notifyTokenMinted(uint256 _tokenId) external;

    /**
     * @notice Updates the address authorized to add rewards to the contract
     * @dev Can only be called by the current reward distributor
     *      This is a critical permission that controls who can distribute rewards
     * @param newRewardDistributor The address of the new reward distributor
     */
    function setRewardDistributor(address newRewardDistributor) external;

    /**
     * @notice Recovers tokens that were directly transferred to the contract without using notifyRewardAmount
     * @dev Can only be called by the reward distributor
     *      This is a safety feature to recover tokens that might be accidentally sent to the contract
     *      Recovered tokens are returned to the current reward distributor address
     *      Only operates on tokens that have not been properly registered through notifyRewardAmount
     */
    function recoverTokens() external;
}
