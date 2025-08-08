// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.10;

import {VersionedInitializable} from
    "@aave/core-v3/contracts/protocol/libraries/aave-upgradeability/VersionedInitializable.sol";
import {SafeCast} from "@aave/core-v3/contracts/dependencies/openzeppelin/contracts/SafeCast.sol";
import {IScaledBalanceToken} from "@aave/core-v3/contracts/interfaces/IScaledBalanceToken.sol";
import {RewardsDistributor} from "@aave-v3-periphery/contracts/rewards/RewardsDistributor.sol";
import {IDustRewardsController} from "../interfaces/IDustRewardsController.sol";
import {IDustTransferStrategy} from "../interfaces/IDustTransferStrategy.sol";
import {RewardsDataTypes} from "@aave-v3-periphery/contracts/rewards/libraries/RewardsDataTypes.sol";

/**
 * @title DustRewardsController
 * @notice Modified Aave's RewardsController contract to pass lockTime and
 *         tokenId to the `IDustTransferStrategy` and remove rewards oracles.
 * @author Aave
 * @author Neverland
 */
contract DustRewardsController is RewardsDistributor, VersionedInitializable, IDustRewardsController {
    using SafeCast for uint256;

    uint256 public constant REVISION = 1;

    // This mapping allows whitelisted addresses to claim on behalf of others
    // useful for contracts that hold tokens to be rewarded but don't have any native logic to claim Liquidity Mining rewards
    mapping(address => address) internal _authorizedClaimers;

    // reward => transfer strategy implementation contract
    // The TransferStrategy contract abstracts the logic regarding
    // the source of the reward and how to transfer it to the user.
    mapping(address => IDustTransferStrategy) internal _transferStrategy;

    modifier onlyAuthorizedClaimers(address claimer, address user) {
        if (_authorizedClaimers[user] != claimer) revert ClaimerUnauthorized();
        _;
    }

    constructor(address emissionManager) RewardsDistributor(emissionManager) {}

    /**
     * @dev Initialize for RewardsController
     * @dev It expects an address as argument since its initialized via PoolAddressesProvider._updateImpl()
     */
    function initialize(address) external initializer {}

    /// @inheritdoc IDustRewardsController
    function getClaimer(address user) external view override returns (address) {
        return _authorizedClaimers[user];
    }

    /**
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

    /// @inheritdoc IDustRewardsController
    function configureAssets(RewardsDataTypes.RewardsConfigInput[] memory config)
        external
        override
        onlyEmissionManager
    {
        for (uint256 i = 0; i < config.length; i++) {
            // Get the current Scaled Total Supply of AToken or Debt token
            config[i].totalSupply = IScaledBalanceToken(config[i].asset).scaledTotalSupply();

            // Install TransferStrategy logic at IncentivesController
            _installTransferStrategy(config[i].reward, IDustTransferStrategy(address(config[i].transferStrategy)));
        }
        _configureAssets(config);
    }

    /// @inheritdoc IDustRewardsController
    function setTransferStrategy(address reward, IDustTransferStrategy transferStrategy) external onlyEmissionManager {
        _installTransferStrategy(reward, transferStrategy);
    }

    /// @inheritdoc IDustRewardsController
    function handleAction(address user, uint256 totalSupply, uint256 userBalance) external override {
        _updateData(msg.sender, user, userBalance, totalSupply);
    }

    /// @inheritdoc IDustRewardsController
    function claimRewards(
        address[] calldata assets,
        uint256 amount,
        address to,
        address reward,
        uint256 lockTime,
        uint256 tokenId
    ) external override returns (uint256) {
        if (to == address(0)) revert InvalidToAddress();
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
        if (user == address(0)) revert InvalidUserAddress();
        if (to == address(0)) revert InvalidToAddress();
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
        if (to == address(0)) revert InvalidToAddress();
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
        if (user == address(0)) revert InvalidUserAddress();
        if (to == address(0)) revert InvalidToAddress();
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

    /// @inheritdoc IDustRewardsController
    function setClaimer(address user, address caller) external override {
        if (msg.sender != user) {
            // If not the user themselves, require admin permission
            if (msg.sender != _emissionManager) revert OnlyEmissionManagerOrSelf();
        }
        _authorizedClaimers[user] = caller;
        emit ClaimerSet(user, caller);
    }

    /**
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
        userAssetBalances = new RewardsDataTypes.UserAssetBalance[](assets.length);
        for (uint256 i = 0; i < assets.length; i++) {
            userAssetBalances[i].asset = assets[i];
            (userAssetBalances[i].userBalance, userAssetBalances[i].totalSupply) =
                IScaledBalanceToken(assets[i]).getScaledUserBalanceAndSupply(user);
        }
        return userAssetBalances;
    }

    /**
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
        for (uint256 i = 0; i < assets.length; i++) {
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
     * @dev Claims one type of reward for a user on behalf, on all the assets of the pool, accumulating the pending rewards.
     * @param assets List of assets to check eligible distributions before claiming rewards
     * @param claimer Address of the claimer on behalf of user
     * @param user Address to check and claim rewards
     * @param to Address that will be receiving the rewards
     * @param lockTime Optional lock time for supported rewards
     * @param tokenId Optional tokenId for supported rewards
     * @return
     *   rewardsList List of reward addresses
     *   claimedAmount List of claimed amounts, follows "rewardsList" items order
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

        for (uint256 i = 0; i < assets.length; i++) {
            address asset = assets[i];
            for (uint256 j = 0; j < rewardsListLength; j++) {
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
        for (uint256 i = 0; i < rewardsListLength; i++) {
            _transferRewards(to, rewardsList[i], claimedAmounts[i], lockTime, tokenId);
            emit RewardsClaimed(user, rewardsList[i], to, claimer, claimedAmounts[i]);
        }
        return (rewardsList, claimedAmounts);
    }

    /**
     * @dev Internal function to transfer rewards to the recipient using the configured transfer strategy
     * @notice This function delegates the actual reward transfer to the strategy contract specified for each reward token
     * @notice The transfer strategy may handle specialized behaviors like creating/extending locks
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
     * @dev Returns true if `account` is a contract.
     * @param account The address of the account
     * @return bool, true if contract, false otherwise
     */
    function _isContract(address account) internal view returns (bool) {
        // This method relies on extcodesize, which returns 0 for contracts in
        // construction, since the code is only stored at the end of the
        // constructor execution.

        uint256 size;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            size := extcodesize(account)
        }
        return size > 0;
    }

    /**
     * @dev Internal function to call the optional install hook at the TransferStrategy
     * @param reward The address of the reward token
     * @param transferStrategy The address of the reward TransferStrategy
     */
    function _installTransferStrategy(address reward, IDustTransferStrategy transferStrategy) internal {
        if (address(transferStrategy) == address(0)) revert StrategyZeroAddress();
        if (_isContract(address(transferStrategy)) != true) revert StrategyNotContract();

        _transferStrategy[reward] = transferStrategy;

        emit TransferStrategyInstalled(reward, address(transferStrategy));
    }
}
