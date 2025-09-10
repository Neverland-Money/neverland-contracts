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
    /// @notice Error thrown when a non-distributor address attempts to notify rewards
    error NotRewardDistributor();

    /// @notice Error thrown when a non-owner address attempts a restricted operation
    error NotOwner();

    /// @notice Error thrown when a non-DustLock address attempts a restricted operation
    error NotDustLock();

    /// @notice Error thrown when end timestamp used for calculating rewards is greater than the current time
    error EndTimestampMoreThanCurrent();

    /// @notice Error thrown when provided arrays are empty or exceed soft size limits
    error InvalidArrayLengths();

    /// @notice Error thrown when a provided reward token is not registered
    error UnknownRewardToken();

    /**
     * @notice Emitted when rewards are claimed
     * @param tokenId The veNFT id that produced the rewards
     * @param user The address that received the rewards (owner or configured receiver)
     * @param token Address of the reward token being claimed
     * @param amount Amount of rewards claimed
     */
    event ClaimRewards(uint256 indexed tokenId, address indexed user, address indexed token, uint256 amount);

    /**
     * @notice Emitted when new rewards are notified to the contract
     * @param from Address that notified the rewards (typically the reward distributor)
     * @param token Address of the reward token being added
     * @param epoch Reward epoch start timestamp (i.e., start of the week) the amount is credited to
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

    /**
     * @notice Emitted when the reward distributor address is updated
     * @param oldDistributor The previous reward distributor
     * @param newDistributor The new reward distributor
     */
    event RewardDistributorUpdated(address indexed oldDistributor, address indexed newDistributor);

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

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
     * @notice Maximum number of tokenIds allowed in a single batch claim.
     */
    function MAX_TOKENIDS() external view returns (uint256);

    /**
     * @notice Maximum number of reward tokens allowed in a single batch claim.
     */
    function MAX_TOKENS() external view returns (uint256);

    /*//////////////////////////////////////////////////////////////
                            STORAGE GETTERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the timestamp of the last successfully processed reward claim for a token and veNFT
     * @dev Used to calculate the amount of rewards earned since the last claim. Value is advanced to the
     *      claim period end only when there were epochs to process; otherwise it remains unchanged.
     * @param token The address of the reward token
     * @param tokenId The ID of the veNFT
     * @return The timestamp (seconds) when rewards were last processed up to
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
     * @notice Returns the accumulated fractional remainder of rewards for a veNFT and token, scaled by 1e18.
     * @dev During per-epoch reward calculations, integer division can leave a remainder that cannot be paid out.
     *      This function exposes the running sum of those remainders for the given (token, tokenId) pair,
     *      scaled by a factor of 1e18 to preserve precision (i.e., value is remainder * 1e18 / totalSupplyAt(epoch)).
     *      This value is informational and not directly claimable; it helps off-chain analytics understand
     *      the uncredited fractional rewards that have accumulated over time due to rounding.
     * @param token The address of the reward token being tracked.
     * @param tokenId The ID of the veNFT whose fractional remainder is queried.
     * @return scaledRemainder The accumulated fractional rewards remainder, scaled by 1e18.
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

    /*//////////////////////////////////////////////////////////////
                                ADMIN
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Updates the address authorized to add rewards to the contract
     * @dev Can only be called by the current reward distributor
     *      This is a critical permission that controls who can distribute rewards
     * @param newRewardDistributor The address of the new reward distributor
     */
    function setRewardDistributor(address newRewardDistributor) external;

    /**
     * @notice Adds new rewards to the distribution pool for the next epoch
     * @dev Can only be called by the authorized reward distributor address.
     *      Automatically registers new tokens the first time they're used.
     *      Rewards added during the current epoch become claimable starting the next epoch.
     *      Emits a NotifyReward event with details about the distribution.
     *      Reverts: NotRewardDistributor, zero address/amount checks enforced by implementation.
     * @param token The address of the reward token to distribute
     * @param amount The amount of rewards to add to the distribution pool
     */
    function notifyRewardAmount(address token, uint256 amount) external;

    /**
     * @notice Recovers unnotified balances of registered reward tokens
     * @dev Can only be called by the reward distributor
     *      For each registered reward token, if the contract's token balance exceeds the credited amount
     *      tracked by totalRewardsPerToken[token], transfers the excess to the reward distributor and emits
     *      a RecoverTokens event.
     */
    function recoverTokens() external;

    /*//////////////////////////////////////////////////////////////
                            NOTIFICATIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Notifies the contract that a new token has been created
     * @dev Intended to update internal state or trigger logic after a veNFT creation event
     *      Can only be called by the DustLock contract.
     * @param tokenId The ID of the token (veNFT) that has been created
     */
    function notifyTokenMinted(uint256 tokenId) external;

    /**
     * @notice Handles necessary operations after a veNFT token is transferred
     * @dev This function is called by the DustLock contract just after transferring a token
     *      It performs two main actions:
     *      1. Claims all pending rewards for the token being transferred
     *      2. Removes the token from the self-repaying loan tracking if enabled
     *      Can only be called by the DustLock contract.
     * @param tokenId The ID of the veNFT token that was transferred
     * @param from The address of the previous token owner (sender of the transfer)
     */
    function notifyAfterTokenTransferred(uint256 tokenId, address from) external;

    /**
     * @notice Handles necessary operations after a veNFT token is burned
     * @dev This function is called by the DustLock contract just after burning a token
     *      It performs two main actions:
     *      1. Claims all pending rewards for the token being burned
     *      2. Removes the token from the self-repaying loan tracking if enabled
     *      Can only be called by the DustLock contract.
     * @param tokenId The ID of the veNFT token that was burned
     * @param from The address of the previous token owner
     */
    function notifyAfterTokenBurned(uint256 tokenId, address from) external;

    /**
     * @notice Handles bookkeeping after two veNFTs are merged.
     * @dev Callable only by the DustLock contract.
     * @param fromToken The tokenId that was merged and is no longer active (source).
     * @param toToken The tokenId that survives the merge and should receive consolidated accounting (destination).
     * @param owner The tokens' owner.
     */
    function notifyAfterTokenMerged(uint256 fromToken, uint256 toToken, address owner) external;

    /**
     * @notice Handles bookkeeping after a veNFT is split into two new veNFTs.
     * @dev Callable only by the DustLock contract.
     *      - Initializes mint timestamps for the two new tokenIds.
     *      - Proportionally splits the accumulated fractional rewards remainder (scaled by 1e18)
     *        from `fromToken` between `tokenId1` and `tokenId2` using their provided amounts.
     *      - Clears the remainder accumulator for `fromToken` and removes it from any self-repaying
     *        loan tracking if applicable.
     * @param fromToken The original tokenId that was split (source).
     * @param tokenId1 The first resulting tokenId after the split.
     * @param token1Amount The amount (voting power/shares) assigned to `tokenId1` in the split.
     * @param tokenId2 The second resulting tokenId after the split.
     * @param token2Amount The amount (voting power/shares) assigned to `tokenId2` in the split.
     * @param owner The owner of the tokens involved in the split.
     */
    function notifyAfterTokenSplit(
        uint256 fromToken,
        uint256 tokenId1,
        uint256 token1Amount,
        uint256 tokenId2,
        uint256 token2Amount,
        address owner
    ) external;

    /*//////////////////////////////////////////////////////////////
                               CLAIMING
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Claims accumulated rewards for a specific veNFT across multiple reward tokens
     * @dev Calculates earned rewards for each specified token using epoch-based accounting and transfers them
     *      to the appropriate recipient. Emits a ClaimRewards event per token. If a reward receiver is configured
     *      via enableSelfRepayLoan, rewards go to that address; otherwise, rewards are sent to the veNFT owner.
     *      Updates lastEarnTime to track future accruals (only if there were epochs to process).
     *      Access: callable by the veNFT owner or an approved operator. The DustLock contract may also call.
     *      Reverts: NotOwner, UnknownRewardToken, InvalidArrayLengths.
     * @param tokenId The ID of the veNFT to claim rewards for
     * @param tokens Array of reward token addresses to claim (must be registered reward tokens)
     */
    function getReward(uint256 tokenId, address[] calldata tokens) external;

    /**
     * @notice Claims accumulated rewards for a specific veNFT across multiple reward tokens up to a specified timestamp
     * @dev Similar to getReward, but allows specifying a custom end timestamp for the reward calculation period.
     *      Calculates earned rewards for each specified token using epoch-based accounting and transfers them to the
     *      appropriate recipient. Emits a ClaimRewards event per token. If a reward receiver is configured via
     *      enableSelfRepayLoan, rewards go to that address; otherwise, rewards are sent to the veNFT owner.
     *      Updates lastEarnTime to rewardPeriodEndTs to track future accruals (only if there were epochs to process).
     *      Access: callable by the veNFT owner or an approved operator. The DustLock contract may also call.
     *      Reverts: NotOwner, EndTimestampMoreThanCurrent, UnknownRewardToken, InvalidArrayLengths.
     * @param tokenId The ID of the veNFT to claim rewards for
     * @param tokens Array of reward token addresses to claim (must be registered reward tokens)
     * @param rewardPeriodEndTs The end timestamp to calculate rewards up to (must not be in the future)
     */
    function getRewardUntilTs(uint256 tokenId, address[] calldata tokens, uint256 rewardPeriodEndTs) external;

    /**
     * @notice Batch claim rewards for many tokenIds across a set of tokens.
     * @dev Access: callable by the veNFT owner or an approved operator. Reverts on invalid arrays or unknown tokens.
     * @param tokenIds Array of veNFT ids to claim for.
     * @param tokens Array of reward token addresses to claim.
     */
    function getRewardBatch(uint256[] calldata tokenIds, address[] calldata tokens) external;

    /**
     * @notice Batch claim rewards for many tokenIds across a set of tokens up to a specific timestamp.
     * @dev Access: callable by the veNFT owner or an approved operator. Reverts on invalid arrays, unknown tokens,
     *      or if `rewardPeriodEndTs` is in the future.
     * @param tokenIds Array of veNFT ids to claim for.
     * @param tokens Array of reward token addresses to claim.
     * @param rewardPeriodEndTs End timestamp for calculation (<= now).
     */
    function getRewardUntilTsBatch(uint256[] calldata tokenIds, address[] calldata tokens, uint256 rewardPeriodEndTs)
        external;

    /*//////////////////////////////////////////////////////////////
                         SELF-REPAYING LOANS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Enables the self-repaying loan feature for a specific veNFT
     * @dev Configures a custom reward receiver address (typically a loan contract).
     *      This allows veNFT owners to use their rewards to automatically repay loans.
     *      The getReward function must still be called to trigger the reward claim.
     *      Access: callable only by the veNFT owner.
     *      Reverts: NotOwner, zero rewardReceiver.
     * @param tokenId The ID of the veNFT to configure self-repaying loan for
     * @param rewardReceiver The address that will receive this veNFT's rewards
     */
    function enableSelfRepayLoan(uint256 tokenId, address rewardReceiver) external;

    /**
     * @notice Disables the self-repaying loan feature for a specific veNFT
     * @dev Removes the custom reward receiver configuration, returning to default behavior.
     *      After disabling, all future rewards will go directly to the veNFT owner.
     *      Access: callable only by the veNFT owner.
     *      Reverts: NotOwner.
     * @param tokenId The ID of the veNFT to restore default reward routing for
     */
    function disableSelfRepayLoan(uint256 tokenId) external;

    /**
     * @notice Batch enable self-repaying loan with a single receiver for many tokenIds.
     * @dev Each tokenId must be owned by the caller. Reverts on zero rewardReceiver.
     * @param tokenIds Array of veNFT ids to configure.
     * @param rewardReceiver The address that will receive rewards for all provided ids.
     */
    function enableSelfRepayLoanBatch(uint256[] calldata tokenIds, address rewardReceiver) external;

    /**
     * @notice Batch disable self-repaying loan for many tokenIds.
     * @dev Each tokenId must be owned by the caller.
     * @param tokenIds Array of veNFT ids to restore default reward routing.
     */
    function disableSelfRepayLoanBatch(uint256[] calldata tokenIds) external;

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Preview unclaimed rewards for a single reward token up to a specific timestamp.
     * @dev Read-only mirror of claim math; does not mutate state, does not advance checkpoints.
     *      Reverts: EndTimestampMoreThanCurrent if `endTs` is in the future, UnknownRewardToken if not registered.
     * @param token Reward token address to preview.
     * @param tokenId veNFT id to preview for.
     * @param endTs Timestamp (<= now) up to which to compute rewards.
     * @return amount Total rewards that would be claimable if claimed up to `endTs`.
     */
    function earnedRewards(address token, uint256 tokenId, uint256 endTs) external view returns (uint256 amount);

    /**
     * @notice Preview unclaimed rewards for multiple tokenIds and multiple tokens at the current timestamp.
     * @dev Convenience wrapper that uses block.timestamp internally. Returns a matrix of rewards per
     *      tokenId (outer) per token (inner), and totals per token.
     *      Reverts: InvalidArrayLengths on bad inputs, UnknownRewardToken if a token is not registered.
     * @param tokens Array of reward token addresses.
     * @param tokenIds Array of veNFT ids.
     * @return matrix Rewards matrix with shape [tokenIds.length][tokens.length].
     * @return totals Totals per token across all tokenIds with shape [tokens.length].
     */
    function earnedRewardsAll(address[] calldata tokens, uint256[] calldata tokenIds)
        external
        view
        returns (uint256[][] memory matrix, uint256[] memory totals);

    /**
     * @notice Preview unclaimed rewards for multiple tokenIds and multiple tokens up to a specific timestamp.
     * @dev Read-only; does not mutate state, does not advance checkpoints.
     *      Reverts: EndTimestampMoreThanCurrent if `endTs` is in the future, InvalidArrayLengths on bad inputs,
     *      UnknownRewardToken if a token is not registered.
     * @param tokens Array of reward token addresses.
     * @param tokenIds Array of veNFT ids.
     * @param endTs Timestamp (<= now) up to which to compute rewards.
     * @return matrix Rewards matrix with shape [tokenIds.length][tokens.length].
     * @return totals Totals per token across all tokenIds with shape [tokens.length].
     */
    function earnedRewardsAllUntilTs(address[] calldata tokens, uint256[] calldata tokenIds, uint256 endTs)
        external
        view
        returns (uint256[][] memory matrix, uint256[] memory totals);

    /**
     * @notice Returns the number of registered reward tokens
     * @return The count of reward tokens
     */
    function rewardTokensLength() external view returns (uint256);

    /**
     * @notice Returns the full list of registered reward tokens
     * @return tokens An array containing all reward token addresses
     */
    function getRewardTokens() external view returns (address[] memory tokens);

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
}
