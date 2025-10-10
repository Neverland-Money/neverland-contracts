// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

import {RewardsDataTypes} from "@aave-v3-periphery/contracts/rewards/libraries/RewardsDataTypes.sol";
import {RewardsDistributor} from "@aave-v3-periphery/contracts/rewards/RewardsDistributor.sol";
import {IScaledBalanceToken} from "@aave/core-v3/contracts/interfaces/IScaledBalanceToken.sol";
import {SafeCast} from "@aave/core-v3/contracts/dependencies/openzeppelin/contracts/SafeCast.sol";
import {VersionedInitializable} from
    "@aave/core-v3/contracts/protocol/libraries/aave-upgradeability/VersionedInitializable.sol";

import {IDustRewardsController} from "../interfaces/IDustRewardsController.sol";
import {IDustTransferStrategy} from "../interfaces/IDustTransferStrategy.sol";

import {CommonChecksLibrary} from "../libraries/CommonChecksLibrary.sol";
import {CommonLibrary} from "../libraries/CommonLibrary.sol";

/**
 * @title DustRewardsController
 * @author Original implementation by Aave
 * @author Extended by Neverland
 * @notice Modified Aave's RewardsController contract to pass lockTime and
 *         tokenId to the `IDustTransferStrategy` and remove rewards oracles.
 */
contract DustRewardsController is RewardsDistributor, VersionedInitializable, IDustRewardsController {
    using SafeCast for uint256;

    /*//////////////////////////////////////////////////////////////
                             CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Implementation revision number for proxy upgrades bookkeeping
    uint256 public constant REVISION = 1;

    /*//////////////////////////////////////////////////////////////
                          STORAGE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Mapping of users to their authorized claimers for reward delegation.
     *      Useful for contracts holding rewarded tokens without native claiming logic
     */
    mapping(address => address) internal _authorizedClaimers;

    /**
     * @dev Mapping of reward tokens to their corresponding transfer strategy contracts.
     *      Transfer strategies abstract reward source logic and transfer mechanisms
     */
    mapping(address => IDustTransferStrategy) internal _transferStrategy;

    /*//////////////////////////////////////////////////////////////
                           ACCESS CONTROL
    //////////////////////////////////////////////////////////////*/

    modifier onlyAuthorizedClaimers(address claimer, address user) {
        if (_authorizedClaimers[user] != claimer) revert ClaimerUnauthorized();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Constructs the rewards controller
     * @param emissionManager The address of the emission manager (Aave semantics)
     */
    constructor(address emissionManager) RewardsDistributor(emissionManager) {}

    /*//////////////////////////////////////////////////////////////
                           INITIALIZER
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initialize for RewardsController (no-op)
     * @dev It expects an address as argument since its initialized via PoolAddressesProvider._updateImpl()
     */
    function initialize(address) external initializer {}

    /*//////////////////////////////////////////////////////////////
                                VIEWS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IDustRewardsController
    function getClaimer(address user) external view override returns (address) {
        return _authorizedClaimers[user];
    }

    /**
     * @notice Returns the implementation revision used by Aave's initializer pattern
     * @dev Returns the revision of the implementation contract
     * @return uint256, current revision version
     */
    function getRevision() internal pure override returns (uint256) {
        return REVISION;
    }

    /// @inheritdoc IDustRewardsController
    function getTransferStrategy(address reward) external view override returns (address) {
        return address(_transferStrategy[reward]);
    }

    /*//////////////////////////////////////////////////////////////
                               ADMIN
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IDustRewardsController
    function configureAssets(RewardsDataTypes.RewardsConfigInput[] calldata config)
        external
        override
        onlyEmissionManager
    {
        RewardsDataTypes.RewardsConfigInput[] memory configCopy = config;
        uint256 assetsLength = config.length;
        for (uint256 i = 0; i < assetsLength; ++i) {
            // Get the current Scaled Total Supply of AToken or Debt token
            configCopy[i].totalSupply = IScaledBalanceToken(configCopy[i].asset).scaledTotalSupply();

            // Install TransferStrategy logic at IncentivesController
            _installTransferStrategy(
                configCopy[i].reward, IDustTransferStrategy(address(configCopy[i].transferStrategy))
            );
        }
        _configureAssets(configCopy);
    }

    /// @inheritdoc IDustRewardsController
    function setTransferStrategy(address reward, IDustTransferStrategy transferStrategy) external onlyEmissionManager {
        _installTransferStrategy(reward, transferStrategy);
    }

    /// @inheritdoc IDustRewardsController
    function setClaimer(address user, address claimer) external override {
        if (msg.sender != user && msg.sender != EMISSION_MANAGER) revert OnlyEmissionManagerOrSelf();

        _authorizedClaimers[user] = claimer;

        emit ClaimerSet(user, claimer);
    }

    /*//////////////////////////////////////////////////////////////
                            REWARDS ACTIONS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IDustRewardsController
    function handleAction(address user, uint256 totalSupply, uint256 userBalance) external override {
        _updateData(msg.sender, user, userBalance, totalSupply);
    }

    /*//////////////////////////////////////////////////////////////
                           REWARDS CLAIMING
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IDustRewardsController
    function claimRewards(
        address[] calldata assets,
        uint256 amount,
        address to,
        address reward,
        uint256 lockTime,
        uint256 tokenId
    ) external override returns (uint256) {
        CommonChecksLibrary.revertIfInvalidToAddress(to);

        return _claimRewards(assets, amount, msg.sender, msg.sender, to, reward, lockTime, tokenId);
    }

    /// @inheritdoc IDustRewardsController
    function claimRewardsOnBehalf(
        address[] calldata assets,
        uint256 amount,
        address user,
        address to,
        address reward,
        uint256 lockTime,
        uint256 tokenId
    ) external override onlyAuthorizedClaimers(msg.sender, user) returns (uint256) {
        CommonChecksLibrary.revertIfInvalidToAddress(to);
        if (user == address(0)) revert InvalidUserAddress();

        return _claimRewards(assets, amount, msg.sender, user, to, reward, lockTime, tokenId);
    }

    /// @inheritdoc IDustRewardsController
    function claimRewardsToSelf(
        address[] calldata assets,
        uint256 amount,
        address reward,
        uint256 lockTime,
        uint256 tokenId
    ) external override returns (uint256) {
        return _claimRewards(assets, amount, msg.sender, msg.sender, msg.sender, reward, lockTime, tokenId);
    }

    /// @inheritdoc IDustRewardsController
    function claimAllRewards(address[] calldata assets, address to, uint256 lockTime, uint256 tokenId)
        external
        override
        returns (address[] memory rewardsList, uint256[] memory claimedAmounts)
    {
        CommonChecksLibrary.revertIfInvalidToAddress(to);

        return _claimAllRewards(assets, msg.sender, msg.sender, to, lockTime, tokenId);
    }

    /// @inheritdoc IDustRewardsController
    function claimAllRewardsOnBehalf(
        address[] calldata assets,
        address user,
        address to,
        uint256 lockTime,
        uint256 tokenId
    )
        external
        override
        onlyAuthorizedClaimers(msg.sender, user)
        returns (address[] memory rewardsList, uint256[] memory claimedAmounts)
    {
        CommonChecksLibrary.revertIfInvalidToAddress(to);
        if (user == address(0)) revert InvalidUserAddress();

        return _claimAllRewards(assets, msg.sender, user, to, lockTime, tokenId);
    }

    /// @inheritdoc IDustRewardsController
    function claimAllRewardsToSelf(address[] calldata assets, uint256 lockTime, uint256 tokenId)
        external
        override
        returns (address[] memory rewardsList, uint256[] memory claimedAmounts)
    {
        return _claimAllRewards(assets, msg.sender, msg.sender, msg.sender, lockTime, tokenId);
    }

    /*//////////////////////////////////////////////////////////////
                               INTERNAL
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get user balances and total supply for a list of assets
     * @dev Get user balances and total supply of all the assets specified by the assets parameter
     * @param assets List of assets to retrieve user balance and total supply
     * @param user Address of the user
     * @return userAssetBalances contains a list of structs with user balance and total supply of the given assets
     */
    function _getUserAssetBalances(address[] calldata assets, address user)
        internal
        view
        override
        returns (RewardsDataTypes.UserAssetBalance[] memory userAssetBalances)
    {
        uint256 assetsLength = assets.length;
        userAssetBalances = new RewardsDataTypes.UserAssetBalance[](assetsLength);
        for (uint256 i = 0; i < assetsLength; ++i) {
            userAssetBalances[i].asset = assets[i];
            (userAssetBalances[i].userBalance, userAssetBalances[i].totalSupply) =
                IScaledBalanceToken(assets[i]).getScaledUserBalanceAndSupply(user);
        }
        return userAssetBalances;
    }

    /**
     * @notice Internal helper to claim a single reward type across assets
     * @dev Claims one type of reward for a user on behalf, on all the assets of the pool, accumulating the pending rewards.
     * @param assets List of assets to check eligible distributions before claiming rewards
     * @param amount Amount of rewards to claim
     * @param claimer Address of the claimer who claims rewards on behalf of user
     * @param user Address to check and claim rewards
     * @param to Address that will be receiving the rewards
     * @param reward Address of the reward token
     * @param lockTime Optional lock time for supported rewards
     * @param tokenId Optional tokenId for supported rewards
     * @return Rewards claimed
     */
    function _claimRewards(
        address[] calldata assets,
        uint256 amount,
        address claimer,
        address user,
        address to,
        address reward,
        uint256 lockTime,
        uint256 tokenId
    ) internal returns (uint256) {
        if (amount == 0) {
            return 0;
        }
        uint256 totalRewards;

        _updateDataMultiple(user, _getUserAssetBalances(assets, user));
        uint256 assetsLength = assets.length;
        for (uint256 i = 0; i < assetsLength; ++i) {
            address asset = assets[i];
            totalRewards += _assets[asset].rewards[reward].usersData[user].accrued;

            if (totalRewards <= amount) {
                _assets[asset].rewards[reward].usersData[user].accrued = 0;
            } else {
                uint256 difference = totalRewards - amount;
                totalRewards -= difference;
                _assets[asset].rewards[reward].usersData[user].accrued = difference.toUint128();
                break;
            }
        }

        if (totalRewards == 0) {
            return 0;
        }

        _transferRewards(to, reward, totalRewards, lockTime, tokenId);

        emit RewardsClaimed(user, reward, to, claimer, totalRewards);
        return totalRewards;
    }

    /**
     * @notice Internal helper to claim all reward types across assets
     * @dev Claims one type of reward for a user on behalf, on all the assets of the pool, accumulating the pending rewards.
     * @param assets List of assets to check eligible distributions before claiming rewards
     * @param claimer Address of the claimer on behalf of user
     * @param user Address to check and claim rewards
     * @param to Address that will be receiving the rewards
     * @param lockTime Optional lock time for supported rewards
     * @param tokenId Optional tokenId for supported rewards
     * @return rewardsList List of reward addresses
     * @return claimedAmounts List of claimed amounts, follows "rewardsList" items order
     */
    function _claimAllRewards(
        address[] calldata assets,
        address claimer,
        address user,
        address to,
        uint256 lockTime,
        uint256 tokenId
    ) internal returns (address[] memory rewardsList, uint256[] memory claimedAmounts) {
        uint256 rewardsListLength = _rewardsList.length;
        rewardsList = new address[](rewardsListLength);
        claimedAmounts = new uint256[](rewardsListLength);

        _updateDataMultiple(user, _getUserAssetBalances(assets, user));
        uint256 assetsLength = assets.length;
        for (uint256 i = 0; i < assetsLength; ++i) {
            address asset = assets[i];
            for (uint256 j = 0; j < rewardsListLength; ++j) {
                if (rewardsList[j] == address(0)) {
                    rewardsList[j] = _rewardsList[j];
                }
                uint256 rewardAmount = _assets[asset].rewards[rewardsList[j]].usersData[user].accrued;
                if (rewardAmount != 0) {
                    claimedAmounts[j] += rewardAmount;
                    _assets[asset].rewards[rewardsList[j]].usersData[user].accrued = 0;
                }
            }
        }
        for (uint256 i = 0; i < rewardsListLength; ++i) {
            _transferRewards(to, rewardsList[i], claimedAmounts[i], lockTime, tokenId);

            emit RewardsClaimed(user, rewardsList[i], to, claimer, claimedAmounts[i]);
        }
        return (rewardsList, claimedAmounts);
    }

    /**
     * @notice Internal function to transfer rewards to the recipient using the configured transfer strategy
     * @dev This function delegates the actual reward transfer to the strategy contract specified for each reward token.
     *      The transfer strategy may handle specialized behaviors like creating/extending locks
     * @param to Recipient address to receive the rewards
     * @param reward Address of the reward token being transferred
     * @param amount Amount of reward tokens to transfer
     * @param lockTime Optional lock duration in seconds (for strategies that create/extend locks)
     * @param tokenId Optional tokenId for strategies that interact with existing veNFTs
     */
    function _transferRewards(address to, address reward, uint256 amount, uint256 lockTime, uint256 tokenId) internal {
        IDustTransferStrategy transferStrategy = _transferStrategy[reward];

        bool success = transferStrategy.performTransfer(to, reward, amount, lockTime, tokenId);

        if (!success) revert TransferError();
    }

    /**
     * @notice Installs or updates the transfer strategy for a reward token
     * @dev Internal function to register the TransferStrategy implementation for a reward token
     * @param reward The address of the reward token
     * @param transferStrategy The address of the reward TransferStrategy
     */
    function _installTransferStrategy(address reward, IDustTransferStrategy transferStrategy) internal {
        if (reward == address(0)) revert InvalidRewardAddress();
        if (address(transferStrategy) == address(0)) revert StrategyZeroAddress();
        if (!CommonLibrary.isContract(address(transferStrategy))) revert StrategyNotContract();

        _transferStrategy[reward] = transferStrategy;

        emit TransferStrategyInstalled(reward, address(transferStrategy));
    }
}
