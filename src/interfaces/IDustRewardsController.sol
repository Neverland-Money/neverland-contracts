// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import {IRewardsDistributor} from "@aave-v3-periphery/contracts/rewards/interfaces/IRewardsDistributor.sol";
import {IDustTransferStrategy} from "../interfaces/IDustTransferStrategy.sol";
import {RewardsDataTypes} from "@aave-v3-periphery/contracts/rewards/libraries/RewardsDataTypes.sol";

/**
 * @title IDustRewardsController
 * @author Aave
 * @author Neverland
 * @notice Defines the interface for the DustRewardsController that manages token rewards distribution
 * @dev Extends Aave's IRewardsDistributor with additional functionality for Neverland's veNFT system
 *      This controller manages the distribution of rewards to veNFT holders with options for
 *      time-locks and specific NFT targeting
 *      Modified from Aave's `IRewardsController` to pass lockTime and tokenId to transfer strategies,
 *      enabling integration with Neverland's veNFT locking ecosystem
 */
interface IDustRewardsController is IRewardsDistributor {
    /// Errors
    
    /// @notice Error thrown when a user is not authorized to claim rewards on behalf of another user
    error ClaimerUnauthorized();

    /// @notice Error thrown when the to address is invalid
    error InvalidToAddress();

    /// @notice Error thrown when the user address is invalid
    error InvalidUserAddress();

    /// @notice Error thrown when the caller is not the emission manager or self
    error OnlyEmissionManagerOrSelf();

    /// @notice Error thrown when a transfer error occurs
    error TransferError();

    /// @notice Error thrown when the strategy address is zero
    error StrategyZeroAddress();

    /// @notice Error thrown when the strategy is not a contract
    error StrategyNotContract();

    /// Events

    /**
     * @notice Emitted when a new address is whitelisted as claimer of rewards on behalf of a user
     * @param user The address of the user
     * @param claimer The address of the claimer
     */
    event ClaimerSet(address indexed user, address indexed claimer);

    /**
     * @notice Emitted when rewards are claimed
     * @param user The address of the user rewards has been claimed on behalf of
     * @param reward The address of the token reward is claimed
     * @param to The address of the receiver of the rewards
     * @param claimer The address of the claimer
     * @param amount The amount of rewards claimed
     */
    event RewardsClaimed(
        address indexed user, address indexed reward, address indexed to, address claimer, uint256 amount
    );

    /**
     * @notice Emitted when a transfer strategy is installed for the reward distribution
     * @param reward The address of the token reward
     * @param transferStrategy The address of TransferStrategy contract
     */
    event TransferStrategyInstalled(address indexed reward, address indexed transferStrategy);

    /// Functions

    /**
     * @notice Authorizes an address to claim rewards on behalf of another user
     * @dev Establishes a delegation relationship for reward claiming
     *      This is useful for integrating with other protocols or allowing
     *      trusted services to manage reward claims for users
     *      Only callable by users for their own accounts or by admin
     * @param user The address of the user granting claim permission
     * @param claimer The address being authorized to claim on behalf of the user
     */
    function setClaimer(address user, address claimer) external;

    /**
     * @notice Sets the transfer strategy implementation for a specific reward token
     * @dev Each reward token can have its own unique transfer logic
     *      For veNFT integration, typically set to a DustLockTransferStrategy
     *      which handles locking tokens into veNFTs during claiming
     *      Only callable by contract admin
     * @param reward The address of the reward token to configure
     * @param transferStrategy The implementation of IDustTransferStrategy that will handle reward transfers
     */
    function setTransferStrategy(address reward, IDustTransferStrategy transferStrategy) external;

    /**
     * @notice Returns the address authorized to claim rewards on behalf of a specific user
     * @dev Used to verify permission when claimRewardsOnBehalf is called
     *      Returns the zero address if no claimer has been set
     * @param user The address of the user whose authorized claimer is being queried
     * @return The address authorized to claim on behalf of the user, or address(0) if none
     */
    function getClaimer(address user) external view returns (address);

    /**
     * @notice Returns the transfer strategy implementation for a specific reward token
     * @dev Each reward token can have its own dedicated transfer strategy implementation
     *      The returned address implements the IDustTransferStrategy interface
     * @param reward The address of the reward token
     * @return The address of the transfer strategy contract for the specified reward token
     */
    function getTransferStrategy(address reward) external view returns (address);

    /**
     * @notice Configures incentivized assets with emission schedules and reward rates
     * @dev Sets up reward distributions for assets with specified emission rates
     *      Each asset can be configured with its own reward token, distribution schedule, and transfer strategy
     *      Only callable by the contract admin
     * @param config Array of configuration inputs with the following fields for each asset:
     *   - emissionPerSecond: Rate of reward distribution per second (in reward token units)
     *   - totalSupply: Current total supply of the incentivized asset
     *   - distributionEnd: Timestamp when reward distribution ends
     *   - asset: Address of the asset being incentivized
     *   - reward: Address of the reward token to distribute
     *   - transferStrategy: Implementation of IDustTransferStrategy for reward transfers
     *   - rewardOracle: Not used in Neverland implementation, can be set to address(0)
     */
    function configureAssets(RewardsDataTypes.RewardsConfigInput[] memory config) external;

    /**
     * @notice Updates reward accrual when a user's balance or asset state changes
     * @dev Called by incentivized assets as a hook during transfers or other balance-changing operations
     *      Records snapshots of user and global state to ensure accurate reward calculation
     *      Must be called by the incentivized asset contract before making any changes to balances
     * @param user The address of the user whose balance is changing
     * @param totalSupply The total supply of the asset before the balance change
     * @param userBalance The user's balance before the change is applied
     */
    function handleAction(address user, uint256 totalSupply, uint256 userBalance) external;

    /**
     * @notice Claims specified amount of rewards for a user across multiple assets
     * @dev Calculates and transfers accumulated rewards to the specified recipient
     *      When integrated with DustLockTransferStrategy, supports automatic locking of rewards into veNFTs
     * @param assets Array of asset addresses to check for eligible distributions
     * @param amount The amount of rewards to claim (use type(uint256).max for all available rewards)
     * @param to The address that will receive the rewards
     * @param reward The address of the reward token to claim
     * @param lockTime Optional lock duration in seconds when claiming as veNFT (0 for no lock)
     * @param tokenId Optional veNFT ID when adding rewards to an existing position (0 for new position)
     * @return The actual amount of rewards claimed
     */
    function claimRewards(
        address[] calldata assets,
        uint256 amount,
        address to,
        address reward,
        uint256 lockTime,
        uint256 tokenId
    ) external returns (uint256);

    /**
     * @notice Claims rewards on behalf of another user (requires authorization)
     * @dev Allows a whitelisted claimer to claim rewards for another user
     *      The claimer must be previously authorized via setClaimer function
     *      When integrated with DustLockTransferStrategy, supports automatic locking of rewards into veNFTs
     * @param assets Array of asset addresses to check for eligible distributions
     * @param amount The amount of rewards to claim (use type(uint256).max for all available rewards)
     * @param user The address of the user whose rewards are being claimed
     * @param to The address that will receive the rewards
     * @param reward The address of the reward token to claim
     * @param lockTime Optional lock duration in seconds when claiming as veNFT (0 for no lock)
     * @param tokenId Optional veNFT ID when adding rewards to an existing position (0 for new position)
     * @return The actual amount of rewards claimed
     */
    function claimRewardsOnBehalf(
        address[] calldata assets,
        uint256 amount,
        address user,
        address to,
        address reward,
        uint256 lockTime,
        uint256 tokenId
    ) external returns (uint256);

    /**
     * @notice Claims rewards for the caller (msg.sender) across multiple assets
     * @dev Convenience function that claims rewards and sends them to the caller
     *      Equivalent to calling claimRewards with 'to' set to msg.sender
     *      When integrated with DustLockTransferStrategy, supports automatic locking of rewards into veNFTs
     * @param assets Array of asset addresses to check for eligible distributions
     * @param amount The amount of rewards to claim (use type(uint256).max for all available rewards)
     * @param reward The address of the reward token to claim
     * @param lockTime Optional lock duration in seconds when claiming as veNFT (0 for no lock)
     * @param tokenId Optional veNFT ID when adding rewards to an existing position (0 for new position)
     * @return The actual amount of rewards claimed
     */
    function claimRewardsToSelf(
        address[] calldata assets,
        uint256 amount,
        address reward,
        uint256 lockTime,
        uint256 tokenId
    ) external returns (uint256);

    /**
     * @notice Claims all available rewards across all reward tokens for a user
     * @dev Processes all reward types in a single transaction for efficiency
     *      Returns two parallel arrays with reward tokens and their claimed amounts
     *      When integrated with DustLockTransferStrategy, supports automatic locking of rewards into veNFTs
     * @param assets Array of asset addresses to check for eligible distributions
     * @param to The address that will receive the rewards
     * @param lockTime Optional lock duration in seconds when claiming as veNFT (0 for no lock)
     * @param tokenId Optional veNFT ID when adding rewards to an existing position (0 for new position)
     * @return rewardsList Array of addresses of all claimed reward tokens
     * @return claimedAmounts Array of claimed amounts, with indices matching the rewardsList array
     */
    function claimAllRewards(address[] calldata assets, address to, uint256 lockTime, uint256 tokenId)
        external
        returns (address[] memory rewardsList, uint256[] memory claimedAmounts);

    /**
     * @notice Claims all available rewards across all reward tokens for a user on behalf of someone else
     * @dev Similar to claimAllRewards but allows a whitelisted claimer to claim on behalf of another user
     *      The claimer must be previously authorized by the user with setClaimer via "allowClaimOnBehalf" function
     *      When integrated with DustLockTransferStrategy, supports automatic locking of rewards into veNFTs
     * @param assets Array of asset addresses to check for eligible distributions
     * @param user The address of the user whose rewards are being claimed
     * @param to The address that will receive the rewards
     * @param lockTime Optional lock duration in seconds when claiming as veNFT (0 for no lock)
     * @param tokenId Optional veNFT ID when adding rewards to an existing position (0 for new position)
     * @return rewardsList Array of addresses of all claimed reward tokens
     * @return claimedAmounts Array of claimed amounts, with indices matching the rewardsList array
     */
    function claimAllRewardsOnBehalf(
        address[] calldata assets,
        address user,
        address to,
        uint256 lockTime,
        uint256 tokenId
    ) external returns (address[] memory rewardsList, uint256[] memory claimedAmounts);

    /**
     * @dev Claims all reward for msg.sender, on all the assets of the pool, accumulating the pending rewards
     * @param assets The list of assets to check eligible distributions before claiming rewards
     * @param lockTime Optional lock time for supported rewards
     * @param tokenId Optional tokenId for supported rewards
     * @return rewardsList List of addresses of the reward tokens
     * @return claimedAmounts List that contains the claimed amount per reward, following same order as "rewardsList"
     */
    function claimAllRewardsToSelf(address[] calldata assets, uint256 lockTime, uint256 tokenId)
        external
        returns (address[] memory rewardsList, uint256[] memory claimedAmounts);
}
