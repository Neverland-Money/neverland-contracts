// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {ERC2771Context} from "@openzeppelin/contracts/metatx/ERC2771Context.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {IDustLock} from "../interfaces/IDustLock.sol";
import {IRevenueReward} from "../interfaces/IRevenueReward.sol";

import {CommonChecksLibrary} from "../libraries/CommonChecksLibrary.sol";
import {EpochTimeLibrary} from "../libraries/EpochTimeLibrary.sol";

/**
 * @title RevenueReward
 * @notice Stores ERC20 token rewards and provides them to veDUST owners
 */
contract RevenueReward is IRevenueReward, ERC2771Context, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.UintSet;
    using EnumerableSet for EnumerableSet.AddressSet;

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address _forwarder, address _dustLock, address _rewardDistributor) ERC2771Context(_forwarder) {
        CommonChecksLibrary.revertIfZeroAddress(_forwarder);
        CommonChecksLibrary.revertIfZeroAddress(_dustLock);
        CommonChecksLibrary.revertIfZeroAddress(_rewardDistributor);

        dustLock = IDustLock(_dustLock);
        rewardDistributor = _rewardDistributor;
    }

    /*//////////////////////////////////////////////////////////////
                            CONSTANTS
    //////////////////////////////////////////////////////////////*/

    uint256 private constant REWARDS_REMAINING_SCALE = 1e8;

    /*//////////////////////////////////////////////////////////////
                        STORAGE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IRevenueReward
    IDustLock public dustLock;
    /// @inheritdoc IRevenueReward
    address public rewardDistributor;
    /// @inheritdoc IRevenueReward
    uint256 public constant DURATION = 7 days;

    /// @inheritdoc IRevenueReward
    mapping(address => mapping(uint256 => uint256)) public lastEarnTime;
    /// @inheritdoc IRevenueReward
    mapping(address => bool) public isRewardToken;
    /// @inheritdoc IRevenueReward
    address[] public rewardTokens;
    /// @inheritdoc IRevenueReward
    mapping(address => uint256) public totalRewardsPerToken;
    /// @inheritdoc IRevenueReward
    mapping(address => mapping(uint256 => uint256)) public tokenRewardsPerEpoch;
    /// @inheritdoc IRevenueReward
    mapping(address => mapping(uint256 => uint256)) public tokenRewardsRemainingAccScaled;

    /// @inheritdoc IRevenueReward
    mapping(uint256 => address) public tokenRewardReceiver;
    mapping(address => EnumerableSet.UintSet) private userTokensWithSelfRepayingLoan;
    EnumerableSet.AddressSet private usersWithSelfRepayingLoan;

    /// tokenId -> block.timestamp of token_id minted
    mapping(uint256 => uint256) tokenMintTime;

    /*//////////////////////////////////////////////////////////////
                           SELF REPAYING LOANS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IRevenueReward
    function enableSelfRepayLoan(uint256 tokenId, address rewardReceiver) external virtual override nonReentrant {
        CommonChecksLibrary.revertIfZeroAddress(rewardReceiver);
        address sender = _msgSender();
        if (sender != dustLock.ownerOf(tokenId)) revert NotOwner();

        tokenRewardReceiver[tokenId] = rewardReceiver;
        usersWithSelfRepayingLoan.add(sender);
        userTokensWithSelfRepayingLoan[sender].add(tokenId);

        emit SelfRepayingLoanUpdate(tokenId, rewardReceiver, true);
    }

    /// @inheritdoc IRevenueReward
    function disableSelfRepayLoan(uint256 tokenId) external virtual override nonReentrant {
        address sender = _msgSender();
        address tokenOwner = dustLock.ownerOf(tokenId);
        if (sender != tokenOwner) revert NotOwner();

        _removeToken(tokenId, tokenOwner);

        emit SelfRepayingLoanUpdate(tokenId, address(0), false);
    }

    /// @inheritdoc IRevenueReward
    function _notifyAfterTokenTransferred(uint256 tokenId, address from) public virtual override nonReentrant {
        if (_msgSender() != address(dustLock)) revert NotDustLock();
        _claimRewardsTo(tokenId, from);
        _removeToken(tokenId, from);
    }

    /// @inheritdoc IRevenueReward
    function _notifyAfterTokenBurned(uint256 tokenId, address from) public virtual override nonReentrant {
        if (_msgSender() != address(dustLock)) revert NotDustLock();
        _claimRewardsTo(tokenId, from);
        _removeToken(tokenId, from);
    }

    /**
     * @notice Claims accumulated rewards for a specific veNFT across all registered reward tokens up to the current timestamp
     * @dev Calculates earned rewards for each token using epoch-based accounting and transfers them to the provided receiver.
     *      Emits a ClaimRewards event per token. Updates lastEarnTime to the current timestamp.
     * @param tokenId The ID of the veNFT to claim rewards for
     * @param receiver The address to receive the rewards
     */
    function _claimRewardsTo(uint256 tokenId, address receiver) internal {
        address[] memory tokens = rewardTokens;
        _claimRewardsUntilTs(tokenId, receiver, tokens, block.timestamp);
    }

    /**
     * @notice Claims accumulated rewards for a specific veNFT across multiple reward tokens up to a specified timestamp
     * @dev Calculates earned rewards for each specified token using epoch-based accounting and transfers them to the provided receiver.
     *      Emits a ClaimRewards event per token. Updates lastEarnTime to rewardPeriodEndTs.
     *      Reverts if rewardPeriodEndTs is in the future (via _earned).
     * @param tokenId The ID of the veNFT to claim rewards for
     * @param receiver The address to receive the rewards
     * @param tokens Array of reward token addresses to claim (must be registered reward tokens)
     * @param rewardPeriodEndTs The end timestamp to calculate rewards up to (must not be in the future)
     */
    function _claimRewardsUntilTs(uint256 tokenId, address receiver, address[] memory tokens, uint256 rewardPeriodEndTs)
        internal
    {
        uint256 length = tokens.length;
        for (uint256 i = 0; i < length; i++) {
            address token = tokens[i];
            uint256 _reward = _earned(token, tokenId, rewardPeriodEndTs);
            lastEarnTime[token][tokenId] = rewardPeriodEndTs;
            if (_reward > 0) {
                IERC20(token).safeTransfer(receiver, _reward);
            }
            emit ClaimRewards(receiver, token, _reward);
        }
    }

    /* === view functions === */

    /// @inheritdoc IRevenueReward
    function earnedRewards(address token, uint256 tokenId, uint256 endTs) public view override returns (uint256) {
        if (endTs > block.timestamp) {
            revert EndTimestampMoreThanCurrent();
        }

        uint256 lastTokenEarnTime = Math.max(lastEarnTime[token][tokenId], tokenMintTime[tokenId]);
        uint256 startTs = EpochTimeLibrary.epochNext(lastTokenEarnTime);
        uint256 endEpochTs = EpochTimeLibrary.epochStart(endTs);

        if (startTs > endEpochTs) return 0;

        uint256 numEpochs = (endEpochTs - startTs) / DURATION;
        uint256 accumulatedReward = 0;
        uint256 currTs = startTs;

        uint256 scaledRemainder = tokenRewardsRemainingAccScaled[token][tokenId];

        for (uint256 i = 0; i <= numEpochs; i++) {
            uint256 totalSupplyAtEpoch = dustLock.totalSupplyAt(currTs);
            if (totalSupplyAtEpoch == 0) {
                currTs += DURATION;
                continue;
            }

            uint256 rewardsThisEpoch = tokenRewardsPerEpoch[token][currTs];
            uint256 userBalanceAtEpoch = dustLock.balanceOfNFTAt(tokenId, currTs);

            // whole payout (floor)
            uint256 rewardAmount = Math.mulDiv(rewardsThisEpoch, userBalanceAtEpoch, totalSupplyAtEpoch);
            accumulatedReward += rewardAmount;

            // fractional remainder scaled
            uint256 remainder = mulmod(rewardsThisEpoch, userBalanceAtEpoch, totalSupplyAtEpoch);
            scaledRemainder += Math.mulDiv(remainder, REWARDS_REMAINING_SCALE, totalSupplyAtEpoch);

            currTs += DURATION;
        }

        uint256 rewardFromRemaining = scaledRemainder / REWARDS_REMAINING_SCALE;
        return accumulatedReward + rewardFromRemaining;
    }

    /// @inheritdoc IRevenueReward
    function earnedRewardsAll(address[] memory tokens, uint256 tokenId)
        external
        view
        override
        returns (uint256[] memory rewards)
    {
        return earnedRewardsAllUntilTs(tokens, tokenId, block.timestamp);
    }

    /// @inheritdoc IRevenueReward
    function earnedRewardsAllUntilTs(address[] memory tokens, uint256 tokenId, uint256 endTs)
        public
        view
        override
        returns (uint256[] memory rewards)
    {
        if (endTs > block.timestamp) revert EndTimestampMoreThanCurrent();
        uint256 len = tokens.length;
        rewards = new uint256[](len);
        for (uint256 i = 0; i < len; i++) {
            rewards[i] = earnedRewards(tokens[i], tokenId, endTs);
        }
    }

    /// @inheritdoc IRevenueReward
    function getUsersWithSelfRepayingLoan(uint256 from, uint256 to) external view override returns (address[] memory) {
        CommonChecksLibrary.revertIfInvalidRange(from, to);
        uint256 length = usersWithSelfRepayingLoan.length();
        if (from >= length) return new address[](0);
        if (to > length) to = length;

        uint256 resultLen = to - from;
        address[] memory users = new address[](resultLen);
        for (uint256 i = 0; i < resultLen; i++) {
            users[i] = usersWithSelfRepayingLoan.at(from + i);
        }
        return users;
    }

    /// @inheritdoc IRevenueReward
    function getUserTokensWithSelfRepayingLoan(address user)
        external
        view
        override
        returns (uint256[] memory tokenIds)
    {
        uint256 len = userTokensWithSelfRepayingLoan[user].length();
        tokenIds = new uint256[](len);
        for (uint256 i = 0; i < len; i++) {
            tokenIds[i] = userTokensWithSelfRepayingLoan[user].at(i);
        }
    }

    /* === helper functions === */

    function _removeToken(uint256 tokenId, address tokenOwner) internal {
        tokenRewardReceiver[tokenId] = address(0);
        userTokensWithSelfRepayingLoan[tokenOwner].remove(tokenId);
        if (userTokensWithSelfRepayingLoan[tokenOwner].length() <= 0) {
            usersWithSelfRepayingLoan.remove(tokenOwner);
        }
    }

    /*//////////////////////////////////////////////////////////////
                                REWARDS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IRevenueReward
    function setRewardDistributor(address newRewardDistributor) external override {
        CommonChecksLibrary.revertIfZeroAddress(newRewardDistributor);
        if (_msgSender() != rewardDistributor) revert NotRewardDistributor();

        rewardDistributor = newRewardDistributor;
    }

    /// @inheritdoc IRevenueReward
    function getReward(uint256 tokenId, address[] memory tokens) public virtual override {
        getRewardUntilTs(tokenId, tokens, block.timestamp);
    }

    /// @inheritdoc IRevenueReward
    function getRewardUntilTs(uint256 tokenId, address[] memory tokens, uint256 rewardPeriodEndTs)
        public
        virtual
        override
        nonReentrant
    {
        if (address(dustLock) != _msgSender()) {
            if (dustLock.ownerOf(tokenId) != _msgSender()) revert NotOwner();
        }

        address rewardsReceiver = _resolveRewardsReceiver(tokenId);
        _claimRewardsUntilTs(tokenId, rewardsReceiver, tokens, rewardPeriodEndTs);
    }

    /// @inheritdoc IRevenueReward
    function notifyRewardAmount(address token, uint256 amount) external override nonReentrant {
        CommonChecksLibrary.revertIfZeroAmount(amount);
        if (_msgSender() != rewardDistributor) revert NotRewardDistributor();
        if (!isRewardToken[token]) {
            isRewardToken[token] = true;
            rewardTokens.push(token);
        }

        address sender = _msgSender();

        totalRewardsPerToken[token] += amount;
        IERC20(token).safeTransferFrom(sender, address(this), amount);

        uint256 epochNext = EpochTimeLibrary.epochNext(block.timestamp);
        tokenRewardsPerEpoch[token][epochNext] += amount;

        emit NotifyReward(sender, token, epochNext, amount);
    }

    /// @inheritdoc IRevenueReward
    function _notifyTokenMinted(uint256 tokenId) public override {
        if (_msgSender() != address(dustLock)) revert NotDustLock();
        tokenMintTime[tokenId] = block.timestamp;
    }

    /**
     * @notice Calculates token's reward from last claimed start epoch until current start epoch
     * @dev Uses epoch-based accounting to prevent reward manipulation:
     *      1. Finds epochs between last claimed (or token mint time) and endTs
     *      2. For each epoch, calculates proportion of rewards based on user's veNFT balance vs total supply
     *      3. Accumulates rewards across all epochs
     * @param token The reward token address to calculate earnings for
     * @param tokenId The ID of the veNFT to calculate earnings for
     * @param endTs Timestamp of the end duration that token id rewards are calculated
     * @return Total unclaimed rewards accrued since last claim
     */
    function _earned(address token, uint256 tokenId, uint256 endTs) internal returns (uint256) {
        if (endTs > block.timestamp) {
            revert EndTimestampMoreThanCurrent();
        }

        uint256 lastTokenEarnTime = Math.max(lastEarnTime[token][tokenId], tokenMintTime[tokenId]);
        uint256 startTs = EpochTimeLibrary.epochNext(lastTokenEarnTime);
        uint256 endTsEpoch = EpochTimeLibrary.epochStart(endTs);

        if (startTs > endTsEpoch) return 0;

        // get epochs between last claimed staring epoch and current stating epoch
        uint256 numEpochs = (endTsEpoch - startTs) / DURATION;

        uint256 accumulatedReward = 0;
        uint256 currTs = startTs;
        for (uint256 i = 0; i <= numEpochs; i++) {
            uint256 tokenSupplyBalanceCurrTs = dustLock.totalSupplyAt(currTs);
            if (tokenSupplyBalanceCurrTs == 0) {
                currTs += DURATION;
                continue;
            }

            accumulatedReward += _calculateEpochReward(token, tokenId, currTs, tokenSupplyBalanceCurrTs);
            currTs += DURATION;
        }

        uint256 rewardFromRemaining = 0;
        if (tokenRewardsRemainingAccScaled[token][tokenId] >= REWARDS_REMAINING_SCALE) {
            rewardFromRemaining = tokenRewardsRemainingAccScaled[token][tokenId] / REWARDS_REMAINING_SCALE;
            tokenRewardsRemainingAccScaled[token][tokenId] -= rewardFromRemaining * REWARDS_REMAINING_SCALE;
        }

        return accumulatedReward + rewardFromRemaining;
    }

    /**
     * @notice Calculates reward for a single epoch with overflow protection
     * @param token The reward token address
     * @param tokenId The veNFT token ID
     * @param epochTs The epoch timestamp
     * @param totalSupply Total voting power supply at the epoch
     * @return The reward amount for this epoch
     */
    function _calculateEpochReward(address token, uint256 tokenId, uint256 epochTs, uint256 totalSupply)
        internal
        returns (uint256)
    {
        uint256 rewardsThisEpoch = tokenRewardsPerEpoch[token][epochTs];
        uint256 userBalanceThisEpoch = dustLock.balanceOfNFTAt(tokenId, epochTs);

        // whole units: floor(rewardsThisEpoch * userBalanceThisEpoch / totalSupply)
        uint256 rewardAmount = Math.mulDiv(rewardsThisEpoch, userBalanceThisEpoch, totalSupply);

        // fractional remainder → scaled accumulator (overflow-safe)
        uint256 remainder = mulmod(rewardsThisEpoch, userBalanceThisEpoch, totalSupply);
        tokenRewardsRemainingAccScaled[token][tokenId] += Math.mulDiv(remainder, REWARDS_REMAINING_SCALE, totalSupply);

        return rewardAmount;
    }

    /**
     * @notice Resolves the rewards receiver for a given tokenId
     * @dev Prefers the configured tokenRewardReceiver; falls back to current owner (ownerOf reverts if token doesn't exist)
     * @param tokenId The veNFT token id to resolve the receiver for
     * @return receiver The address that should receive rewards
     */
    function _resolveRewardsReceiver(uint256 tokenId) internal view returns (address receiver) {
        receiver = tokenRewardReceiver[tokenId];
        if (receiver == address(0)) receiver = dustLock.ownerOf(tokenId);
    }

    /*//////////////////////////////////////////////////////////////
                                RECOVERY
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IRevenueReward
    function recoverTokens() external override {
        if (_msgSender() != rewardDistributor) revert NotRewardDistributor();

        for (uint256 i = 0; i < rewardTokens.length; i++) {
            address token = rewardTokens[i];
            uint256 balance = IERC20(token).balanceOf(address(this));
            uint256 credited = totalRewardsPerToken[token];
            if (balance > credited) {
                uint256 unnotifiedTokenAmount = balance - credited;
                IERC20(token).safeTransfer(rewardDistributor, unnotifiedTokenAmount);
                emit RecoverTokens(token, unnotifiedTokenAmount);
            }
        }
    }
}
