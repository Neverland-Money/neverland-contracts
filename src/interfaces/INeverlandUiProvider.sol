// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

/**
 * @title INeverlandUiProvider
 * @author Neverland
 * @notice Interface for the Neverland UI data provider contract
 * @dev Aggregates data from multiple contracts for efficient frontend queries
 */
interface INeverlandUiProvider {
    /// @notice Thrown when the price oracle for non-DUST assets is not configured or inaccessible
    error PriceOracleUnavailable();

    /// @notice Thrown when a non-DUST asset price cannot be retrieved or is zero
    error AssetPriceUnavailable(address token);

    /*//////////////////////////////////////////////////////////////
                               STRUCTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Complete dashboard data for a user
     * @param user The user address
     * @param tokenIds Array of all veNFT token IDs owned by the user
     * @param locks Array of lock information for each token
     * @param rewardSummaries Array of reward summaries for each token
     * @param totalVotingPower User's total current voting power across all tokens
     * @param totalLockedAmount Total DUST locked across all user's tokens
     */
    struct UserDashboardData {
        address user;
        uint256[] tokenIds;
        LockInfo[] locks;
        RewardSummary[] rewardSummaries;
        uint256 totalVotingPower;
        uint256 totalLockedAmount;
    }

    /**
     * @notice Detailed information about a specific lock
     * @param tokenId The veNFT token ID
     * @param amount Amount of DUST locked
     * @param end Unlock timestamp (0 for permanent locks)
     * @param effectiveStart Effective start time for weighted calculations
     * @param isPermanent Whether this is a permanent lock
     * @param votingPower Current voting power of this token
     * @param rewardReceiver Address that receives rewards (for self-repaying loans)
     * @param owner Current owner of the token
     */
    struct LockInfo {
        uint256 tokenId;
        uint256 amount;
        uint256 end;
        uint256 effectiveStart;
        bool isPermanent;
        uint256 votingPower;
        address rewardReceiver;
        address owner;
    }

    /**
     * @notice Summary of rewards for a specific token
     * @param tokenId The veNFT token ID
     * @param revenueRewards Array of pending revenue rewards per reward token
     * @param emissionRewards Array of pending emission rewards per reward token
     * @param rewardTokens Array of reward token addresses
     * @param totalEarned Array of total rewards earned historically per token
     */
    struct RewardSummary {
        uint256 tokenId;
        uint256[] revenueRewards;
        uint256[] emissionRewards;
        address[] rewardTokens;
        uint256[] totalEarned;
    }

    /**
     * @notice Protocol-wide statistics
     * @param totalSupply Total DUST locked in the protocol
     * @param totalVotingPower Total voting power across all tokens
     * @param permanentLockBalance Total DUST in permanent locks
     * @param rewardTokens Array of all reward tokens
     * @param totalRewardsPerToken Total rewards distributed per token
     * @param epoch Current global epoch
     * @param activeTokenCount Number of active veNFT tokens
     */
    struct GlobalStats {
        uint256 totalSupply;
        uint256 totalVotingPower;
        uint256 permanentLockBalance;
        address[] rewardTokens;
        uint256[] totalRewardsPerToken;
        uint256 epoch;
        uint256 activeTokenCount;
    }

    /*//////////////////////////////////////////////////////////////
                           VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get user dashboard with all veNFT positions and rewards
     * @param user The user address to get data for
     * @param offset Start index for paginated token list
     * @param limit Maximum number of tokens to include
     * @return Complete user dashboard information
     */
    function getUserDashboard(address user, uint256 offset, uint256 limit)
        external
        view
        returns (UserDashboardData memory);

    /**
     * @notice Returns the total number of veDUST tokens owned by a user
     * @param user The user address
     * @return count Number of owned veDUST tokens
     */
    function getUserTokenCount(address user) external view returns (uint256 count);

    /**
     * @notice Get detailed information for a specific token
     * @param tokenId The veNFT token ID
     * @return LockInfo Detailed lock information
     * @return RewardSummary Reward summary for the token
     */
    function getTokenDetails(uint256 tokenId) external view returns (LockInfo memory, RewardSummary memory);

    /**
     * @notice Get detailed information for multiple tokens efficiently
     * @param tokenIds Array of veNFT token IDs
     * @return locks Array of lock information
     * @return rewards Array of reward summaries
     */
    function getBatchTokenDetails(uint256[] calldata tokenIds)
        external
        view
        returns (LockInfo[] memory locks, RewardSummary[] memory rewards);

    /**
     * @notice Get protocol-wide statistics
     * @return GlobalStats Protocol statistics
     */
    function getGlobalStats() external view returns (GlobalStats memory);

    /**
     * @notice User reward summary data structure
     * @param totalRevenue Total pending revenue rewards per reward token
     * @param totalEmissions Total pending emission rewards per reward token
     * @param totalHistorical Total historical rewards earned per reward token
     */
    struct UserRewardsSummary {
        uint256[] totalRevenue;
        uint256[] totalEmissions;
        uint256[] totalHistorical;
    }

    /**
     * @notice Returns comprehensive reward summary for a user across specified reward tokens
     * @dev Aggregates all rewards earned by user's veNFTs for the given tokens
     *      Provides separate totals for revenue rewards, emission rewards, and historical rewards
     * @param user The address to query rewards for
     * @param rewardTokens Array of reward token addresses to check
     * @return summary User rewards summary containing all reward arrays
     */
    function getUserRewardsSummary(address user, address[] calldata rewardTokens)
        external
        view
        returns (UserRewardsSummary memory summary);

    /**
     * @notice Returns user revenue rewards for specified reward tokens (simpler array return)
     * @param user The address to query rewards for
     * @param rewardTokens Array of reward token addresses to check
     * @return revenueRewards Array of total revenue rewards per token
     */
    function getUserRevenueRewards(address user, address[] calldata rewardTokens)
        external
        view
        returns (uint256[] memory revenueRewards);

    /**
     * @notice Returns user emission rewards for specified reward tokens (simpler array return)
     * @param user The address to query rewards for
     * @param rewardTokens Array of reward token addresses to check
     * @return emissionRewards Array of total emission rewards per token
     */
    function getUserEmissionRewards(address user, address[] calldata rewardTokens)
        external
        view
        returns (uint256[] memory emissionRewards);

    /**
     * @notice Returns per-asset emission rewards for a specific reward token
     * @dev Lists Aave assets (aTokens and variable debt tokens) that contribute to the user's emissions
     *      and the corresponding reward amounts per asset for the given reward token
     * @param user The address to query rewards for
     * @param rewardToken The reward token address to break down
     * @return assets Array of asset addresses contributing to emissions
     * @return amounts Array of rewards per asset (parallel to `assets`)
     */
    function getUserEmissionBreakdown(address user, address rewardToken)
        external
        view
        returns (address[] memory assets, uint256[] memory amounts);

    /**
     * @notice Get unlock schedule for user's tokens
     * @param user The user address
     * @return unlockTimes Array of unlock timestamps
     * @return amounts Array of amounts unlocking at each timestamp
     * @return tokenIds Array of token IDs for each unlock
     */
    function getUnlockSchedule(address user)
        external
        view
        returns (uint256[] memory unlockTimes, uint256[] memory amounts, uint256[] memory tokenIds);

    /*//////////////////////////////////////////////////////////////
                         COMPREHENSIVE DATA STRUCTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Market and economic data
     * @param rewardTokens Array of reward token addresses
     * @param rewardTokenBalances Available reward balances in contracts
     * @param distributionRates Rewards distributed per epoch (current epoch)
     * @param nextEpochTimestamp When next reward epoch starts
     * @param currentEpoch Current epoch number
     * @param epochRewards Total rewards for current epoch per token
     * @param nextEpochRewards Total rewards already scheduled for the next epoch per token
     * @param totalValueLockedUSD Total protocol TVL in USD (8 decimals)
     */
    struct MarketData {
        address[] rewardTokens;
        uint256[] rewardTokenBalances;
        uint256[] distributionRates;
        uint256 nextEpochTimestamp;
        uint256 currentEpoch;
        uint256[] epochRewards;
        uint256[] nextEpochRewards;
        uint256 totalValueLockedUSD;
    }

    /**
     * @notice Static and semi-static protocol metadata for bootstrapping the UI
     * @param dustLock Address of DustLock contract
     * @param revenueReward Address of RevenueReward contract
     * @param dustRewardsController Address of DustRewardsController
     * @param dustOracle Address of NeverlandDustHelper
     * @param earlyWithdrawPenalty Early withdraw penalty in basis points
     * @param minLockAmount Minimum DUST required to create a lock
     * @param rewardDistributor Current revenue reward distributor address
     * @param revenueRewardTokens List of revenue reward tokens
     * @param emissionRewardTokens List of emission reward tokens
     * @param emissionStrategies List of transfer strategies (parallel to emissionRewardTokens)
     */
    struct ProtocolMeta {
        address dustLock;
        address revenueReward;
        address dustRewardsController;
        address dustOracle;
        uint256 earlyWithdrawPenalty;
        uint256 minLockAmount;
        address rewardDistributor;
        address[] revenueRewardTokens;
        address[] emissionRewardTokens;
        address[] emissionStrategies;
    }

    /**
     * @notice Price data for all tokens
     * @param tokens Array of token addresses
     * @param prices USD prices (18 decimals)
     * @param lastUpdated Price update timestamps
     * @param isStale Price staleness flags
     */
    struct PriceData {
        address[] tokens;
        uint256[] prices;
        uint256[] lastUpdated;
        bool[] isStale;
    }

    /**
     * @notice Network and system status information
     * @param currentBlock Current block number
     * @param currentTimestamp Current timestamp
     * @param gasPrice Current gas price estimate
     */
    struct NetworkData {
        uint256 currentBlock;
        uint256 currentTimestamp;
        uint256 gasPrice;
    }

    /*//////////////////////////////////////////////////////////////
                         BUNDLED VIEW STRUCTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice User emission rewards data
     * @param rewardTokens Array of emission reward token addresses
     * @param totalRewards Array of total rewards per token
     */
    struct EmissionData {
        address[] rewardTokens;
        uint256[] totalRewards;
    }

    /**
     * @notice Unlock schedule for a user
     * @param unlockTimes Array of unlock timestamps
     * @param amounts Array of amounts unlocking
     * @param tokenIds Array of token IDs unlocking
     */
    struct UnlockSchedule {
        uint256[] unlockTimes;
        uint256[] amounts;
        uint256[] tokenIds;
    }

    /**
     * @notice Essential user data combining core dashboard elements
     * @param user Core user dashboard data
     * @param globalStats Global protocol statistics
     * @param emissions User emission rewards data
     * @param marketData Market and economic data
     */
    struct EssentialUserView {
        UserDashboardData user;
        GlobalStats globalStats;
        EmissionData emissions;
        MarketData marketData;
    }

    /**
     * @notice Extended user data with additional detailed information
     * @param unlockSchedule Scheduled unlock times and amounts
     * @param rewardsSummary Comprehensive rewards breakdown
     * @param allPrices Token price information
     */
    struct ExtendedUserView {
        UnlockSchedule unlockSchedule;
        UserRewardsSummary rewardsSummary;
        PriceData allPrices;
        EmissionAssetBreakdown[] emissionBreakdowns;
    }

    /**
     * @notice Complete protocol bootstrap data for UI in a single call
     * @param meta Protocol metadata and core addresses
     * @param globalStats Protocol-wide statistics
     * @param marketData Market and economic data
     * @param allPrices Price information for relevant tokens
     * @param network Network status and system information
     */
    struct UiBootstrap {
        ProtocolMeta meta;
        GlobalStats globalStats;
        MarketData marketData;
        PriceData allPrices;
        NetworkData network;
    }

    /**
     * @notice Complete user-focused UI data in a single call
     * @param meta Protocol metadata and core addresses
     * @param essential Essential user view (dashboard + emissions + global + market)
     * @param extended Extended user view (unlock schedule + rewards summary + prices)
     * @param network Network status and system information
     */
    struct UiFullBundle {
        ProtocolMeta meta;
        EssentialUserView essential;
        ExtendedUserView extended;
        NetworkData network;
    }

    /**
     * @notice Per-asset emission breakdown for a given reward token
     * @param rewardToken Emission reward token address
     * @param assets List of contributing assets (aTokens and variable debt tokens)
     * @param amounts Parallel list of rewards per asset
     */
    struct EmissionAssetBreakdown {
        address rewardToken;
        address[] assets;
        uint256[] amounts;
    }

    /*//////////////////////////////////////////////////////////////
                         BUNDLED VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get essential user view with core data
     * @param user The user address
     * @param offset Start index for paginated token list
     * @param limit Maximum number of tokens to include
     * @return Essential user data bundle
     */
    function getEssentialUserView(address user, uint256 offset, uint256 limit)
        external
        view
        returns (EssentialUserView memory);

    /**
     * @notice Get extended user view with detailed analysis data
     * @param user The user address
     * @param offset Start index for paginated token list
     * @param limit Maximum number of tokens to include
     * @return Extended user data bundle
     */
    function getExtendedUserView(address user, uint256 offset, uint256 limit)
        external
        view
        returns (ExtendedUserView memory);

    /**
     * @notice Get user emission rewards data
     * @param user The user address
     * @return rewardTokens Array of emission reward token addresses
     * @return totalRewards Array of total rewards per token
     */
    function getUserEmissions(address user)
        external
        view
        returns (address[] memory rewardTokens, uint256[] memory totalRewards);

    /**
     * @notice Get market and economic data
     * @return MarketData Market data including prices and TVL
     */
    function getMarketData() external view returns (MarketData memory);

    /**
     * @notice Get all token prices
     * @return PriceData Price information for all tokens
     */
    function getAllPrices() external view returns (PriceData memory);

    /**
     * @notice Get protocol metadata for UI bootstrapping in one call
     * @return meta ProtocolMeta containing core addresses, settings, and token lists
     */
    function getProtocolMeta() external view returns (ProtocolMeta memory meta);

    /**
     * @notice Get network and system data
     * @return NetworkData Network status and system information
     */
    function getNetworkData() external view returns (NetworkData memory);

    /**
     * @notice Get protocol bootstrap data in one call
     * @return boot UiBootstrap containing protocol + market + prices + network
     */
    function getUiBootstrap() external view returns (UiBootstrap memory boot);

    /**
     * @notice Get complete user bundle in one call (protocol + user views)
     * @param user The user address
     * @param offset Start index for paginated token list
     * @param limit Maximum number of tokens to include
     * @return bundle UiFullBundle containing meta, essential, extended, and network
     */
    function getUiFullBundle(address user, uint256 offset, uint256 limit)
        external
        view
        returns (UiFullBundle memory bundle);
}
