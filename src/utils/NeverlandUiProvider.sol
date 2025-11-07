// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPoolAddressesProvider} from "@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol";
import {IPriceOracleGetter} from "@aave/core-v3/contracts/interfaces/IPriceOracleGetter.sol";
import {IPoolDataProvider} from "@aave/core-v3/contracts/interfaces/IPoolDataProvider.sol";

import {IDustLock} from "../interfaces/IDustLock.sol";
import {IRevenueReward} from "../interfaces/IRevenueReward.sol";
import {IDustRewardsController} from "../interfaces/IDustRewardsController.sol";
import {INeverlandUiProvider} from "../interfaces/INeverlandUiProvider.sol";
import {INeverlandDustHelper} from "../interfaces/INeverlandDustHelper.sol";

import {CommonChecksLibrary} from "../libraries/CommonChecksLibrary.sol";
import {EpochTimeLibrary} from "../libraries/EpochTimeLibrary.sol";

/**
 * @title NeverlandUiProvider
 * @author Neverland
 * @notice Aggregates data from DustLock, RevenueReward, and DustRewardsController for efficient UI queries
 * @dev This contract is purely for data aggregation and contains no state-changing functions
 */
contract NeverlandUiProvider is INeverlandUiProvider {
    /*//////////////////////////////////////////////////////////////
                             CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice USD oracle unit (8 decimals)
    uint256 private constant USD_PRICE_UNIT = 1e8;

    /*//////////////////////////////////////////////////////////////
                          IMMUTABLE CONTRACTS
    //////////////////////////////////////////////////////////////*/

    /// @notice DustLock contract for veNFT and voting power data
    IDustLock public immutable DUST_LOCK;

    /// @notice RevenueReward contract for revenue distribution data
    IRevenueReward public immutable REVENUE_REWARD;

    /// @notice DustRewardsController contract for emission rewards data
    IDustRewardsController public immutable DUST_REWARDS_CONTROLLER;

    /// @notice DustOracle contract for DUST price data
    INeverlandDustHelper public immutable DUST_HELPER;

    /// @notice Aave Lending Pool Address Provider for protocol integration
    IPoolAddressesProvider public immutable AAVE_LENDING_POOL_ADDRESS_PROVIDER;

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initialize the NeverlandUiProvider with core contract addresses
     * @param _dustLock Address of the DustLock contract
     * @param _revenueReward Address of the RevenueReward contract
     * @param _dustRewardsController Address of the DustRewardsController contract
     * @param _dustOracle Address of the DUST price oracle
     * @param _aaveLendingPoolAddressProvider Address of the Aave Lending Pool Address Provider
     */
    constructor(
        address _dustLock,
        address _revenueReward,
        address _dustRewardsController,
        address _dustOracle,
        address _aaveLendingPoolAddressProvider
    ) {
        CommonChecksLibrary.revertIfZeroAddress(_dustLock);
        CommonChecksLibrary.revertIfZeroAddress(_revenueReward);
        CommonChecksLibrary.revertIfZeroAddress(_dustRewardsController);
        CommonChecksLibrary.revertIfZeroAddress(_dustOracle);
        CommonChecksLibrary.revertIfZeroAddress(_aaveLendingPoolAddressProvider);

        DUST_LOCK = IDustLock(_dustLock);
        REVENUE_REWARD = IRevenueReward(_revenueReward);
        DUST_REWARDS_CONTROLLER = IDustRewardsController(_dustRewardsController);
        DUST_HELPER = INeverlandDustHelper(_dustOracle);
        AAVE_LENDING_POOL_ADDRESS_PROVIDER = IPoolAddressesProvider(_aaveLendingPoolAddressProvider);
    }

    /*//////////////////////////////////////////////////////////////
                           MAIN UI FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc INeverlandUiProvider
    function getUserTokenCount(address user) external view override returns (uint256 count) {
        CommonChecksLibrary.revertIfZeroAddress(user);
        return DUST_LOCK.balanceOf(user);
    }

    /// @inheritdoc INeverlandUiProvider
    function getUserDashboard(address user, uint256 offset, uint256 limit)
        public
        view
        override
        returns (UserDashboardData memory)
    {
        CommonChecksLibrary.revertIfZeroAddress(user);

        uint256 tokenCount = DUST_LOCK.balanceOf(user);
        uint256 start = offset > tokenCount ? tokenCount : offset;
        uint256 end = tokenCount;
        unchecked {
            // clamp end to start+limit if it doesn't overflow and is smaller than tokenCount
            uint256 remaining = tokenCount - start;
            if (limit < remaining) end = start + limit;
        }
        uint256 pageLen = end - start;

        uint256[] memory tokenIds = new uint256[](pageLen);
        for (uint256 i; i < pageLen;) {
            try DUST_LOCK.ownerToNFTokenIdList(user, start + i) returns (uint256 tokenId) {
                tokenIds[i] = tokenId;
            } catch {
                tokenIds[i] = 0;
            }
            unchecked {
                ++i;
            }
        }

        (LockInfo[] memory locks, RewardSummary[] memory rewardSummaries) = _getBatchTokenDetailsInternal(tokenIds);

        uint256 totalVotingPower;
        uint256 totalLockedAmount;
        for (uint256 i; i < pageLen;) {
            totalVotingPower += locks[i].votingPower;
            totalLockedAmount += locks[i].amount;
            unchecked {
                ++i;
            }
        }

        UserDashboardData memory dash;
        dash.user = user;
        dash.tokenIds = tokenIds;
        dash.locks = locks;
        dash.rewardSummaries = rewardSummaries;
        dash.totalVotingPower = totalVotingPower;
        dash.totalLockedAmount = totalLockedAmount;
        return dash;
    }

    /// @inheritdoc INeverlandUiProvider
    function getGlobalStats() public view override returns (GlobalStats memory) {
        address[] memory rewardTokens = REVENUE_REWARD.getRewardTokens();
        uint256[] memory totalRewardsPerToken = new uint256[](rewardTokens.length);

        for (uint256 i; i < rewardTokens.length;) {
            totalRewardsPerToken[i] = REVENUE_REWARD.totalRewardsPerToken(rewardTokens[i]);
            unchecked {
                ++i;
            }
        }

        GlobalStats memory stats;
        stats.totalSupply = DUST_LOCK.supply();
        stats.totalVotingPower = DUST_LOCK.totalSupplyAt(block.timestamp);
        stats.permanentLockBalance = DUST_LOCK.permanentLockBalance();
        stats.rewardTokens = rewardTokens;
        stats.totalRewardsPerToken = totalRewardsPerToken;
        stats.epoch = DUST_LOCK.epoch();
        stats.activeTokenCount = DUST_LOCK.tokenId();
        return stats;
    }

    /// @inheritdoc INeverlandUiProvider
    function getUserRewardsSummary(address user, address[] calldata rewardTokens)
        public
        view
        override
        returns (UserRewardsSummary memory summary)
    {
        CommonChecksLibrary.revertIfZeroAddress(user);
        return _getUserRewardsSummaryInternal(user, rewardTokens);
    }

    /**
     * @notice Internal function to get user rewards summary
     * @param user The user address
     * @param rewardTokens Array of reward token addresses
     * @return summary User rewards summary
     */
    function _getUserRewardsSummaryInternal(address user, address[] memory rewardTokens)
        internal
        view
        returns (UserRewardsSummary memory summary)
    {
        uint256[] memory tokenIds = _getUserRelatedTokenIds(user);
        uint256 tokenCount = tokenIds.length;
        uint256 rewardTokenCount = rewardTokens.length;

        summary.totalRevenue = new uint256[](rewardTokenCount);
        summary.totalEmissions = new uint256[](rewardTokenCount);

        address[] memory revTokens = REVENUE_REWARD.getRewardTokens();
        if (revTokens.length > 0 && tokenCount > 0) {
            (, uint256[] memory totalsPerToken) = REVENUE_REWARD.earnedRewardsAll(revTokens, tokenIds);
            for (uint256 j; j < rewardTokenCount;) {
                address t = rewardTokens[j];
                for (uint256 r; r < revTokens.length;) {
                    if (revTokens[r] == t) {
                        summary.totalRevenue[j] = totalsPerToken[r];
                        break;
                    }
                    unchecked {
                        ++r;
                    }
                }
                unchecked {
                    ++j;
                }
            }
        }

        address[] memory emissionTokens = DUST_REWARDS_CONTROLLER.getRewardsList();
        for (uint256 j; j < rewardTokenCount;) {
            address rewardToken = rewardTokens[j];
            for (uint256 k; k < emissionTokens.length;) {
                if (emissionTokens[k] == rewardToken) {
                    summary.totalEmissions[j] = _getUserEmissionRewards(user, rewardToken);
                    break;
                }
                unchecked {
                    ++k;
                }
            }
            unchecked {
                ++j;
            }
        }
    }

    /**
     * @notice Get all tokenIds that contribute rewards to `user`: owned tokens and tokens forwarding rewards to `user` (self-repay loan)
     * @param user The user address
     * @return ids Array of tokenIds
     */
    function _getUserRelatedTokenIds(address user) internal view returns (uint256[] memory ids) {
        uint256 owned = DUST_LOCK.balanceOf(user);
        uint256[] memory srl = REVENUE_REWARD.getUserTokensWithSelfRepayingLoan(user);

        if (owned == 0 && srl.length == 0) return new uint256[](0);

        // Preallocate max size, then shrink
        uint256[] memory tmp = new uint256[](owned + srl.length);
        uint256 n = 0;

        // Add owned tokenIds (unique by ERC721 invariant)
        for (uint256 i; i < owned;) {
            try DUST_LOCK.ownerToNFTokenIdList(user, i) returns (uint256 tokenId) {
                tmp[n] = tokenId;
                unchecked {
                    ++n;
                }
            } catch {
                // Skip corrupted enumeration entries
            }
            unchecked {
                ++i;
            }
        }

        // Add SRL tokenIds, dedup only against owned set (SRL itself is an EnumerableSet -> unique)
        if (srl.length > 0) {
            for (uint256 j; j < srl.length;) {
                uint256 tokenId = srl[j];
                bool duplicate = false;
                // Check only the first `owned` entries (owned set) for duplicates
                for (uint256 k; k < owned;) {
                    if (tmp[k] == tokenId) {
                        duplicate = true;
                        break;
                    }
                    unchecked {
                        ++k;
                    }
                }
                if (!duplicate) {
                    tmp[n] = tokenId;
                    unchecked {
                        ++n;
                    }
                }
                unchecked {
                    ++j;
                }
            }
        }

        // Resize to actual length
        ids = new uint256[](n);
        for (uint256 i; i < n;) {
            ids[i] = tmp[i];
            unchecked {
                ++i;
            }
        }
    }

    /// @inheritdoc INeverlandUiProvider
    function getUserEmissionBreakdown(address user, address rewardToken)
        public
        view
        override
        returns (address[] memory assets, uint256[] memory amounts)
    {
        CommonChecksLibrary.revertIfZeroAddress(user);
        assets = _getAllLendingPoolAssets();
        uint256 n = assets.length;
        amounts = new uint256[](n);
        for (uint256 i; i < n;) {
            amounts[i] = _tryUserRewardsSingle(user, assets[i], rewardToken);
            unchecked {
                ++i;
            }
        }
    }

    /// @inheritdoc INeverlandUiProvider
    function getUserEmissions(address user)
        public
        view
        override
        returns (address[] memory rewardTokens, uint256[] memory totalRewards)
    {
        CommonChecksLibrary.revertIfZeroAddress(user);

        rewardTokens = DUST_REWARDS_CONTROLLER.getRewardsList();
        uint256 n = rewardTokens.length;
        totalRewards = new uint256[](n);

        for (uint256 i; i < n;) {
            totalRewards[i] = _getUserEmissionRewards(user, rewardTokens[i]);
            unchecked {
                ++i;
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                           UTILITY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc INeverlandUiProvider
    function getUnlockSchedule(address user)
        public
        view
        override
        returns (uint256[] memory unlockTimes, uint256[] memory amounts, uint256[] memory tokenIds)
    {
        CommonChecksLibrary.revertIfZeroAddress(user);

        uint256 tokenCount = DUST_LOCK.balanceOf(user);
        uint256 unlockCount = 0;
        for (uint256 i; i < tokenCount;) {
            try DUST_LOCK.ownerToNFTokenIdList(user, i) returns (uint256 tokenId) {
                IDustLock.LockedBalance memory locked = DUST_LOCK.locked(tokenId);
                if (!locked.isPermanent && locked.end > block.timestamp) {
                    ++unlockCount;
                }
            } catch {
                // Skip corrupted enumeration entries
            }
            unchecked {
                ++i;
            }
        }

        unlockTimes = new uint256[](unlockCount);
        amounts = new uint256[](unlockCount);
        tokenIds = new uint256[](unlockCount);

        uint256 index = 0;
        for (uint256 i; i < tokenCount;) {
            try DUST_LOCK.ownerToNFTokenIdList(user, i) returns (uint256 tokenId) {
                IDustLock.LockedBalance memory locked = DUST_LOCK.locked(tokenId);

                if (!locked.isPermanent && locked.end > block.timestamp) {
                    unlockTimes[index] = locked.end;
                    amounts[index] = uint256(locked.amount);
                    tokenIds[index] = tokenId;
                    ++index;
                }
            } catch {
                // Skip corrupted enumeration entries
            }
            unchecked {
                ++i;
            }
        }
    }

    /// @inheritdoc INeverlandUiProvider
    function getEssentialUserView(address user, uint256 offset, uint256 limit)
        public
        view
        override
        returns (EssentialUserView memory)
    {
        CommonChecksLibrary.revertIfZeroAddress(user);
        EssentialUserView memory v;
        v.user = getUserDashboard(user, offset, limit);
        v.globalStats = getGlobalStats();
        (v.emissions.rewardTokens, v.emissions.totalRewards) = getUserEmissions(user);
        v.marketData = getMarketData();
        return v;
    }

    /// @inheritdoc INeverlandUiProvider
    function getExtendedUserView(address user, uint256 offset, uint256 limit)
        public
        view
        override
        returns (ExtendedUserView memory)
    {
        CommonChecksLibrary.revertIfZeroAddress(user);
        ExtendedUserView memory ext;

        // Build unlock schedule for the requested page only using dashboard page tokenIds
        UserDashboardData memory pageDash = getUserDashboard(user, offset, limit);
        uint256 nT = pageDash.tokenIds.length;
        uint256 count;
        for (uint256 i; i < nT;) {
            IDustLock.LockedBalance memory lockInfo = DUST_LOCK.locked(pageDash.tokenIds[i]);
            if (!lockInfo.isPermanent && lockInfo.end > block.timestamp) {
                unchecked {
                    ++count;
                }
            }
            unchecked {
                ++i;
            }
        }
        uint256[] memory uts = new uint256[](count);
        uint256[] memory ams = new uint256[](count);
        uint256[] memory tids = new uint256[](count);
        uint256 idx;
        for (uint256 i; i < nT;) {
            uint256 tid = pageDash.tokenIds[i];
            IDustLock.LockedBalance memory lockInfo2 = DUST_LOCK.locked(tid);
            if (!lockInfo2.isPermanent && lockInfo2.end > block.timestamp) {
                uts[idx] = lockInfo2.end;
                ams[idx] = uint256(lockInfo2.amount);
                tids[idx] = tid;
                unchecked {
                    ++idx;
                }
            }
            unchecked {
                ++i;
            }
        }
        ext.unlockSchedule = UnlockSchedule({unlockTimes: uts, amounts: ams, tokenIds: tids});
        ext.allPrices = getAllPrices();

        return ext;
    }

    /*//////////////////////////////////////////////////////////////
                         COMPREHENSIVE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc INeverlandUiProvider
    function getMarketData() public view override returns (MarketData memory) {
        address[] memory rewardTokens = REVENUE_REWARD.getRewardTokens();
        uint256 length = rewardTokens.length;

        uint256[] memory balances = new uint256[](length);
        uint256[] memory rates = new uint256[](length);
        uint256[] memory epochRewards = new uint256[](length);
        uint256[] memory nextEpochRewards = new uint256[](length);

        uint256 currentEpoch = EpochTimeLibrary.epochStart(block.timestamp);
        uint256 nextEpoch = EpochTimeLibrary.epochNext(block.timestamp);

        for (uint256 i; i < length;) {
            address token = rewardTokens[i];
            balances[i] = IERC20(token).balanceOf(address(REVENUE_REWARD));
            uint256 perEpoch = REVENUE_REWARD.tokenRewardsPerEpoch(token, currentEpoch);
            rates[i] = perEpoch;
            epochRewards[i] = perEpoch;
            nextEpochRewards[i] = REVENUE_REWARD.tokenRewardsPerEpoch(token, nextEpoch);
            unchecked {
                ++i;
            }
        }

        MarketData memory m;
        m.rewardTokens = rewardTokens;
        m.rewardTokenBalances = balances;
        m.distributionRates = rates;
        m.nextEpochTimestamp = nextEpoch;
        m.currentEpoch = DUST_LOCK.epoch();
        m.epochRewards = epochRewards;
        m.nextEpochRewards = nextEpochRewards;
        m.totalValueLockedUSD = DUST_HELPER.getDustValueInUSD(DUST_LOCK.supply());
        return m;
    }

    /// @inheritdoc INeverlandUiProvider
    function getAllPrices() public view override returns (PriceData memory) {
        address[] memory rewardTokens = REVENUE_REWARD.getRewardTokens();
        uint256 length = rewardTokens.length + 1;

        PriceData memory p;
        p.tokens = new address[](length);
        p.prices = new uint256[](length);
        p.lastUpdated = new uint256[](length);

        p.tokens[0] = DUST_LOCK.token();
        (p.prices[0],) = DUST_HELPER.getPrice();
        p.lastUpdated[0] = DUST_HELPER.latestTimestamp();
        for (uint256 i; i < rewardTokens.length;) {
            uint256 idx = i + 1;
            address t = rewardTokens[i];
            p.tokens[idx] = t;
            p.prices[idx] = _getTokenPriceInUSD(t);
            p.lastUpdated[idx] = block.timestamp;
            unchecked {
                ++i;
            }
        }
        return p;
    }

    /// @inheritdoc INeverlandUiProvider
    function getNetworkData() public view override returns (NetworkData memory) {
        NetworkData memory n;
        n.currentBlock = block.number;
        n.currentTimestamp = block.timestamp;
        n.gasPrice = tx.gasprice;
        return n;
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL HELPERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Internal function to get batch token details
     * @param tokenIds Array of veNFT token IDs
     * @return locks Array of detailed lock information
     * @return rewards Array of reward summaries
     */
    function _getBatchTokenDetailsInternal(uint256[] memory tokenIds)
        internal
        view
        returns (LockInfo[] memory locks, RewardSummary[] memory rewards)
    {
        uint256 length = tokenIds.length;
        locks = new LockInfo[](length);
        rewards = new RewardSummary[](length);

        address[] memory rewardTokens = REVENUE_REWARD.getRewardTokens();
        for (uint256 i = 0; i < length; ++i) {
            uint256 tokenId = tokenIds[i];
            locks[i] = _getLockInfo(tokenId);
            rewards[i] = _getRewardSummary(tokenId, rewardTokens);
        }
    }

    /**
     * @notice Get detailed lock information for a token
     * @param tokenId The veNFT token ID
     * @return LockInfo Detailed lock information
     */
    function _getLockInfo(uint256 tokenId) internal view returns (LockInfo memory) {
        IDustLock.LockedBalance memory locked = DUST_LOCK.locked(tokenId);
        address owner = DUST_LOCK.ownerOf(tokenId);
        uint256 votingPower = DUST_LOCK.balanceOfNFT(tokenId);
        address rewardReceiver = REVENUE_REWARD.tokenRewardReceiver(tokenId);

        LockInfo memory info;
        info.tokenId = tokenId;
        info.amount = uint256(locked.amount);
        info.end = locked.end;
        info.effectiveStart = locked.effectiveStart;
        info.isPermanent = locked.isPermanent;
        info.votingPower = votingPower;
        info.rewardReceiver = rewardReceiver;
        info.owner = owner;
        return info;
    }

    /**
     * @notice Get reward summary for a token
     * @param tokenId The veNFT token ID
     * @param rewardTokens Array of reward token addresses
     * @return RewardSummary Reward summary for the token
     */
    function _getRewardSummary(uint256 tokenId, address[] memory rewardTokens)
        internal
        view
        returns (RewardSummary memory)
    {
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId;

        uint256 length = rewardTokens.length;
        uint256[] memory revenueRewardsResult = new uint256[](length);

        // Only call earnedRewardsAll if there are reward tokens
        if (rewardTokens.length > 0) {
            try REVENUE_REWARD.earnedRewardsAll(rewardTokens, tokenIds) returns (
                uint256[][] memory matrix, uint256[] memory
            ) {
                revenueRewardsResult = matrix.length > 0 ? matrix[0] : new uint256[](length);
            } catch {
                // If earnedRewardsAll fails (e.g., UnknownRewardToken), return zeros
                revenueRewardsResult = new uint256[](length);
            }
        }

        RewardSummary memory summary;
        summary.tokenId = tokenId;
        summary.revenueRewards = revenueRewardsResult;
        summary.rewardTokens = rewardTokens;
        return summary;
    }

    /// @inheritdoc INeverlandUiProvider
    function getProtocolMeta() public view returns (ProtocolMeta memory meta) {
        meta.dustLock = address(DUST_LOCK);
        meta.revenueReward = address(REVENUE_REWARD);
        meta.dustRewardsController = address(DUST_REWARDS_CONTROLLER);
        meta.dustOracle = address(DUST_HELPER);
        meta.earlyWithdrawPenalty = DUST_LOCK.earlyWithdrawPenalty();
        meta.minLockAmount = DUST_LOCK.minLockAmount();
        try REVENUE_REWARD.rewardDistributor() returns (address rd) {
            meta.rewardDistributor = rd;
        } catch {
            meta.rewardDistributor = address(0);
        }
        meta.revenueRewardTokens = REVENUE_REWARD.getRewardTokens();
        meta.emissionRewardTokens = DUST_REWARDS_CONTROLLER.getRewardsList();
        meta.emissionStrategies = new address[](meta.emissionRewardTokens.length);
        for (uint256 i; i < meta.emissionRewardTokens.length;) {
            meta.emissionStrategies[i] = DUST_REWARDS_CONTROLLER.getTransferStrategy(meta.emissionRewardTokens[i]);
            unchecked {
                ++i;
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                         ONE-CALL UI AGGREGATES
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc INeverlandUiProvider
    function getUiBootstrap() public view override returns (UiBootstrap memory boot) {
        boot.meta = getProtocolMeta();
        boot.globalStats = getGlobalStats();
        boot.marketData = getMarketData();
        boot.allPrices = getAllPrices();
        boot.network = getNetworkData();
    }

    /// @inheritdoc INeverlandUiProvider
    function getUiFullBundle(address user, uint256 offset, uint256 limit)
        public
        view
        override
        returns (UiFullBundle memory bundle)
    {
        CommonChecksLibrary.revertIfZeroAddress(user);
        bundle.meta = getProtocolMeta();
        bundle.essential = getEssentialUserView(user, offset, limit);
        bundle.extended = getExtendedUserView(user, offset, limit);
        bundle.network = getNetworkData();
    }

    /*//////////////////////////////////////////////////////////////
                         EMISSION REWARD HELPERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get user's total emission rewards for a specific reward token
     * @param user User address
     * @param rewardToken Reward token address
     * @return totalRewards Total emission rewards for the user
     */
    function _getUserEmissionRewards(address user, address rewardToken) internal view returns (uint256 totalRewards) {
        address[] memory assets = _getAllLendingPoolAssets();

        for (uint256 i = 0; i < assets.length; ++i) {
            address asset = assets[i];
            totalRewards += _tryUserRewardsSingle(user, asset, rewardToken);
        }
    }

    /**
     * @notice Get all lending pool assets from Aave Protocol Data Provider
     * @return assets Array of lending pool asset addresses (ATokens + Variable Debt Tokens)
     */
    function _getAllLendingPoolAssets() internal view returns (address[] memory assets) {
        address dataProviderAddr = AAVE_LENDING_POOL_ADDRESS_PROVIDER.getPoolDataProvider();
        if (dataProviderAddr == address(0)) {
            return new address[](0);
        }

        IPoolDataProvider dp = IPoolDataProvider(dataProviderAddr);
        IPoolDataProvider.TokenData[] memory reserveTokens = dp.getAllReservesTokens();

        uint256 reserveTokensLen = reserveTokens.length;
        if (reserveTokensLen == 0) return new address[](0);

        assets = new address[](reserveTokensLen * 2);
        uint256 assetCount = 0;

        for (uint256 i = 0; i < reserveTokensLen; ++i) {
            try dp.getReserveTokensAddresses(reserveTokens[i].tokenAddress) returns (
                address aTokenAddr, address, /*stableDebt*/ address variableDebtTokenAddr
            ) {
                if (aTokenAddr != address(0)) {
                    assets[assetCount] = aTokenAddr;
                    unchecked {
                        ++assetCount;
                    }
                }

                if (variableDebtTokenAddr != address(0)) {
                    assets[assetCount] = variableDebtTokenAddr;
                    unchecked {
                        ++assetCount;
                    }
                }
            } catch {
                continue;
            }
        }

        if (assetCount != reserveTokensLen * 2) {
            address[] memory resizedAssets = new address[](assetCount);
            for (uint256 i = 0; i < assetCount; ++i) {
                resizedAssets[i] = assets[i];
            }
            assets = resizedAssets;
        }
    }

    /**
     * @notice Get user's balance in a specific lending pool asset
     * @param user User address
     * @param asset Asset address (aToken)
     * @return balance User's balance in the asset
     */
    function _getUserAssetBalance(address user, address asset) internal view returns (uint256 balance) {
        try IERC20(asset).balanceOf(user) returns (uint256 userBalance) {
            balance = userBalance;
        } catch {
            balance = 0;
        }
    }

    /// @notice Tries to read user rewards via controller for a single asset
    /// @param user The user address
    /// @param asset The asset address
    /// @param rewardToken The reward token address
    /// @return amount Rewards amount (0 on failure)
    function _tryUserRewardsSingle(address user, address asset, address rewardToken)
        internal
        view
        returns (uint256 amount)
    {
        address[] memory singleAsset = new address[](1);
        singleAsset[0] = asset;
        try DUST_REWARDS_CONTROLLER.getUserRewards(singleAsset, user, rewardToken) returns (uint256 userRewards) {
            return userRewards;
        } catch {
            return 0;
        }
    }

    /// @notice Returns token USD price (8 decimals) using DustHelper for DUST and Aave Oracle for pool assets
    /// @param token The token address
    /// @return price USD price (8 decimals)
    function _getTokenPriceInUSD(address token) internal view returns (uint256 price) {
        if (token == DUST_LOCK.token()) {
            (price,) = DUST_HELPER.getPrice();
            return price;
        }

        address oracleAddr = AAVE_LENDING_POOL_ADDRESS_PROVIDER.getPriceOracle();
        if (oracleAddr == address(0)) revert PriceOracleUnavailable();

        IPriceOracleGetter oracle = IPriceOracleGetter(oracleAddr);
        uint256 unit;
        try oracle.BASE_CURRENCY_UNIT() returns (uint256 u) {
            unit = u;
        } catch {
            revert PriceOracleUnavailable();
        }
        if (unit < 1) revert PriceOracleUnavailable();

        uint256 p;
        try oracle.getAssetPrice(token) returns (uint256 price_) {
            p = price_;
        } catch {
            revert PriceOracleUnavailable();
        }
        if (p < 1) revert AssetPriceUnavailable(token);

        if (unit == USD_PRICE_UNIT) return p;
        return (p * USD_PRICE_UNIT) / unit;
    }
}
