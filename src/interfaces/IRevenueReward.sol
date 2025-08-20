// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {IDustLock} from "../interfaces/IDustLock.sol";

/**
 * @title IRevenueReward Interface
 * @notice Interface for the RevenueReward contract that manages token rewards distribution
 * @dev Handles reward epochs, claiming rewards, and self-repaying loan functionality
 */
interface IRevenueReward {
    /// Errors

    /// @notice Error thrown when a non-distributor address attempts to notify rewards
    error NotRewardDistributor();

    /// @notice Error thrown when a non-owner address attempts a restricted operation
    error NotOwner();

    /// @notice Error thrown when a non-DustLock address attempts a restricted operation
    error NotDustLock();

    /// @notice Error thrown when end timestamp when calculating rewards is more that current
    error EndTimestampMoreThanCurrent();

    /// Events

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

    /// Functions

    /**
     * @notice The address of the DustLock contract that manages veNFTs
     * @return The IDustLock interface of the connected DustLock contract
     */
    function dustLock() external view returns (IDustLock);

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
     * @notice Returns the amount of rewards allocated for a specific token at a given epoch start
     * @dev Rewards are tracked by epoch start timestamp (seconds), with each epoch lasting DURATION seconds.
     * @param token The address of the reward token
     * @param epoch The epoch start timestamp (i.e., start of the week)
     * @return The amount of rewards allocated for the token at that epoch start
     */
    function tokenRewardsPerEpoch(address token, uint256 epoch) external view returns (uint256);

    /**
     * @notice Returns the accumulated fractional remainder of rewards for a veNFT and token, scaled by 1e8.
     * @dev During per-epoch reward calculations, integer division can leave a remainder that cannot be paid out.
     *      This function exposes the running sum of those remainders for the given (token, tokenId) pair,
     *      scaled by a factor of 1e8 to preserve precision (i.e., value is remainder * 1e8 / totalSupplyAt(epoch)).
     *      This value is informational and not directly claimable; it helps off-chain analytics understand
     *      the uncredited fractional rewards that have accumulated over time due to rounding.
     * @param token The address of the reward token being tracked.
     * @param tokenId The ID of the veNFT whose fractional remainder is queried.
     * @return scaledRemainder The accumulated fractional rewards remainder, scaled by 1e8.
     */
    function tokenRewardsRemainingAccScaled(address token, uint256 tokenId) external view returns (uint256);

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
     * @dev Calculates earned rewards for each specified token using epoch-based accounting and transfers them
     *      to the appropriate recipient. Emits a ClaimRewards event per token. If a reward receiver is configured
     *      via enableSelfRepayLoan, rewards go to that address; otherwise, rewards are sent to the veNFT owner.
     *      Updates lastEarnTime to track future accruals.
     * @param tokenId The ID of the veNFT to claim rewards for
     * @param tokens Array of reward token addresses to claim (must be registered reward tokens)
     */
    function getReward(uint256 tokenId, address[] memory tokens) external;

    /**
     * @notice Claims accumulated rewards for a specific veNFT across multiple reward tokens up to a specified timestamp
     * @dev Similar to getReward, but allows specifying a custom end timestamp for the reward calculation period.
     *      Calculates earned rewards for each specified token using epoch-based accounting and transfers them to the
     *      appropriate recipient. Emits a ClaimRewards event per token. If a reward receiver is configured via
     *      enableSelfRepayLoan, rewards go to that address; otherwise, rewards are sent to the veNFT owner.
     *      Updates lastEarnTime to rewardPeriodEndTs to track future accruals.
     * @param tokenId The ID of the veNFT to claim rewards for
     * @param tokens Array of reward token addresses to claim (must be registered reward tokens)
     * @param rewardPeriodEndTs The end timestamp to calculate rewards up to (must not be in the future)
     */
    function getRewardUntilTs(uint256 tokenId, address[] memory tokens, uint256 rewardPeriodEndTs) external;

    /**
     * @notice Enables the self-repaying loan feature for a specific veNFT
     * @dev Configures a custom reward receiver address (typically a loan contract)
     *      This allows veNFT owners to use their rewards to automatically repay loans
     *      The getReward function must still be called to trigger the reward claim
     *      Can only be called by the veNFT owner
     * @param tokenId The ID of the veNFT to configure
     * @param rewardReceiver The address that will receive this veNFT's rewards
     */
    function enableSelfRepayLoan(uint256 tokenId, address rewardReceiver) external;

    /**
     * @notice Disables the self-repaying loan feature for a specific veNFT
     * @dev Removes the custom reward receiver configuration, returning to default behavior
     *      After disabling, all future rewards will go directly to the veNFT owner
     *      Can only be called by the veNFT owner
     * @param tokenId The ID of the veNFT to restore default reward routing for
     */
    function disableSelfRepayLoan(uint256 tokenId) external;

    /**
     * @notice Notifies the contract that a new token has been created
     * @dev Intended to update internal state or trigger logic after a veNFT creation event
     *      Can only be called by authorized contracts, typically after a creation operation
     *      External but prefixed with `_` to signal system-only use.
     *      Callable only by DustLock.
     * @param tokenId The ID of the token (veNFT) that has been created
     */
    function _notifyTokenMinted(uint256 tokenId) external;

    /**
     * @notice Handles necessary operations after a veNFT token is transferred
     * @dev This function is called by the DustLock contract just after transferring a token
     *      It performs two main actions:
     *      1. Claims all pending rewards for the token being transferred
     *      2. Removes the token from the self-repaying loan tracking if enabled
     *      External but prefixed with `_` to signal system-only use.
     *      Callable only by DustLock.
     * @param tokenId The ID of the veNFT token that was transferred
     * @param from The address of the previous token owner (sender of the transfer)
     */
    function _notifyAfterTokenTransferred(uint256 tokenId, address from) external;

    /**
     * @notice Handles necessary operations after a veNFT token is burned
     * @dev This function is called by the DustLock contract just after burning a token
     *      It performs two main actions:
     *      1. Claims all pending rewards for the token being burned
     *      2. Removes the token from the self-repaying loan tracking if enabled
     *      External but prefixed with `_` to signal system-only use.
     *      Callable only by DustLock.
     * @param tokenId The ID of the veNFT token that was burned
     * @param from The address of the previous token owner
     */
    function _notifyAfterTokenBurned(uint256 tokenId, address from) external;

    /**
     * @notice Preview unclaimed rewards for a single reward token up to a specific timestamp.
     * @dev Read-only mirror of claim math; does not mutate state, does not advance checkpoints.
     *      Reverts with EndTimestampMoreThanCurrent if `endTs` is in the future.
     * @param token Reward token address to preview.
     * @param tokenId veNFT id to preview for.
     * @param endTs Timestamp (<= now) up to which to compute rewards.
     * @return amount Total rewards that would be claimable if claimed up to `endTs`.
     */
    function earnedRewards(address token, uint256 tokenId, uint256 endTs) external view returns (uint256 amount);

    /**
     * @notice Preview unclaimed rewards for multiple tokens at the current timestamp.
     * @dev Convenience wrapper that uses block.timestamp internally.
     * @param tokens Array of reward token addresses.
     * @param tokenId veNFT id to preview for.
     * @return rewards Array of amounts in the same order as `tokens`.
     */
    function earnedRewardsAll(address[] memory tokens, uint256 tokenId)
        external
        view
        returns (uint256[] memory rewards);

    /**
     * @notice Preview unclaimed rewards for multiple tokens up to a specific timestamp.
     * @dev Read-only; does not mutate state, does not advance checkpoints.
     *      Reverts with EndTimestampMoreThanCurrent if `endTs` is in the future.
     * @param tokens Array of reward token addresses.
     * @param tokenId veNFT id to preview for.
     * @param endTs Timestamp (<= now) up to which to compute rewards.
     * @return rewards Array of amounts in the same order as `tokens`.
     */
    function earnedRewardsAllUntilTs(address[] memory tokens, uint256 tokenId, uint256 endTs)
        external
        view
        returns (uint256[] memory rewards);

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
     * @notice Updates the address authorized to add rewards to the contract
     * @dev Can only be called by the current reward distributor
     *      This is a critical permission that controls who can distribute rewards
     * @param newRewardDistributor The address of the new reward distributor
     */
    function setRewardDistributor(address newRewardDistributor) external;

    /**
     * @notice Recovers unnotified balances of registered reward tokens
     * @dev Can only be called by the reward distributor
     *      For each registered reward token, if the contract's token balance exceeds the credited amount
     *      tracked by totalRewardsPerToken[token], transfers the excess to the reward distributor and emits
     *      a RecoverTokens event.
     */
    function recoverTokens() external;
}
