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

    uint256 private constant REWARDS_REMAINING_SCALE = 1e18;

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
    mapping(uint256 => uint256) public tokenMintTime;

    /*//////////////////////////////////////////////////////////////
                            ACCESS CONTROL
    //////////////////////////////////////////////////////////////*/

    modifier onlyDustLock() {
        if (_msgSender() != address(dustLock)) revert NotDustLock();
        _;
    }

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
    function notifyAfterTokenTransferred(uint256 tokenId, address from)
        external
        virtual
        override
        nonReentrant
        onlyDustLock
    {
        _claimRewardsTo(tokenId, from);
        _removeToken(tokenId, from);
    }

    /// @inheritdoc IRevenueReward
    function notifyAfterTokenBurned(uint256 tokenId, address from)
        external
        virtual
        override
        nonReentrant
        onlyDustLock
    {
        _claimRewardsTo(tokenId, from);
        _removeToken(tokenId, from);
    }

    /// @inheritdoc IRevenueReward
    function notifyAfterTokenMerged(uint256 fromToken, uint256 toToken, address owner)
        external
        override
        nonReentrant
        onlyDustLock
    {
        _claimRewardsTo(fromToken, owner);

        uint256 length = rewardTokens.length;
        for (uint256 i = 0; i < length; i++) {
            tokenRewardsRemainingAccScaled[rewardTokens[i]][toToken] +=
                tokenRewardsRemainingAccScaled[rewardTokens[i]][fromToken];
            tokenRewardsRemainingAccScaled[rewardTokens[i]][fromToken] = 0;
        }

        _removeToken(fromToken, owner);
    }

    /// @inheritdoc IRevenueReward
    function notifyAfterTokenSplit(
        uint256 fromToken,
        uint256 tokenId1,
        uint256 token1Amount,
        uint256 tokenId2,
        uint256 token2Amount,
        address owner
    ) external override nonReentrant onlyDustLock {
        _claimRewardsTo(fromToken, owner);

        tokenMintTime[tokenId1] = block.timestamp;
        tokenMintTime[tokenId2] = block.timestamp;

        uint256 newTokenAmount = token1Amount + token2Amount;

        uint256 length = rewardTokens.length;
        for (uint256 i = 0; i < length; i++) {
            uint256 acc = tokenRewardsRemainingAccScaled[rewardTokens[i]][fromToken];
            if (acc != 0) {
                uint256 a1 = Math.mulDiv(token1Amount, acc, newTokenAmount);
                uint256 a2 = acc - a1;

                tokenRewardsRemainingAccScaled[rewardTokens[i]][tokenId1] = a1;
                tokenRewardsRemainingAccScaled[rewardTokens[i]][tokenId2] = a2;
                tokenRewardsRemainingAccScaled[rewardTokens[i]][fromToken] = 0;
            }
        }

        _removeToken(fromToken, owner);
    }

    /// @inheritdoc IRevenueReward
    function notifyTokenMinted(uint256 tokenId) external override onlyDustLock {
        tokenMintTime[tokenId] = block.timestamp;
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
            EarnedResult memory _earnedResult = _earned(token, tokenId, rewardPeriodEndTs);

            if (_earnedResult.success) {
                lastEarnTime[token][tokenId] = rewardPeriodEndTs;
                tokenRewardsRemainingAccScaled[token][tokenId] = _earnedResult.rewardRemainders;
                if (_earnedResult.unclaimedRewards > 0) {
                    IERC20(token).safeTransfer(receiver, _earnedResult.unclaimedRewards);
                }
            }

            emit ClaimRewards(receiver, token, _earnedResult.unclaimedRewards);
        }
    }

    /* === view functions === */

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
    function earnedRewards(address token, uint256 tokenId, uint256 endTs) public view override returns (uint256) {
        EarnedResult memory earnedResult = _earned(token, tokenId, endTs);
        return earnedResult.unclaimedRewards;
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
        CommonChecksLibrary.revertIfZeroAddress(token);

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

    struct EarnedResult {
        uint256 unclaimedRewards;
        uint256 rewardRemainders;
        bool success;
    }

    /**
     * @notice Calculates and accrues rewards from the last claim (or mint) up to `endTs`
     * @dev Uses epoch-based accounting to prevent reward manipulation:
     *      1. Iterates all epochs between the last processed time and `endTs`
     *      2. For each epoch, computes whole-token rewards and fractional remainders
     *      3. Accumulates whole rewards immediately and carries fractional remainders
     *         forward in a scaled accumulator for future realization
     * @param token The reward token address to calculate earnings for
     * @param tokenId The ID of the veNFT to calculate earnings for
     * @param endTs Timestamp of the end duration that token rewards are calculated up to
     * @return Total unclaimed rewards accrued since last claim
     */
    function _earned(address token, uint256 tokenId, uint256 endTs) internal view returns (EarnedResult memory) {
        if (endTs > block.timestamp) {
            revert EndTimestampMoreThanCurrent();
        }

        uint256 lastTokenEarnTime = Math.max(lastEarnTime[token][tokenId], tokenMintTime[tokenId]);
        uint256 startTs = EpochTimeLibrary.epochNext(lastTokenEarnTime);
        uint256 endTsEpoch = EpochTimeLibrary.epochStart(endTs);

        if (startTs > endTsEpoch) return EarnedResult(0, 0, false);

        uint256 numEpochs = (endTsEpoch - startTs) / DURATION;

        uint256 accumulatedReward = 0;
        uint256 currTs = startTs;

        uint256 accumulatedRemainder = tokenRewardsRemainingAccScaled[token][tokenId];

        for (uint256 i = 0; i <= numEpochs; i++) {
            uint256 tokenSupplyBalanceCurrTs = dustLock.totalSupplyAt(currTs);
            if (tokenSupplyBalanceCurrTs == 0) {
                currTs += DURATION;
                continue;
            }

            (uint256 rewardAmount, uint256 scaledRemainder) =
                _calculateEpochReward(token, tokenId, currTs, tokenSupplyBalanceCurrTs);

            accumulatedReward += rewardAmount;
            accumulatedRemainder += scaledRemainder;

            currTs += DURATION;
        }

        uint256 rewardFromRemaining = accumulatedRemainder / REWARDS_REMAINING_SCALE;
        uint256 newRemainder = accumulatedRemainder - rewardFromRemaining * REWARDS_REMAINING_SCALE;

        return EarnedResult(accumulatedReward + rewardFromRemaining, newRemainder, true);
    }

    /**
     * @notice Calculates reward for a single epoch with overflow protection
     * @param token The reward token address
     * @param tokenId The veNFT token ID
     * @param epochTs The epoch timestamp
     * @param totalSupply Total voting power supply at the epoch
     * @return rewardAmount The whole-token reward amount for this epoch
     * @return scaledRemainder The scaled fractional remainder to accumulate
     */
    function _calculateEpochReward(address token, uint256 tokenId, uint256 epochTs, uint256 totalSupply)
        internal
        view
        returns (uint256 rewardAmount, uint256 scaledRemainder)
    {
        uint256 rewardsThisEpoch = tokenRewardsPerEpoch[token][epochTs];
        uint256 userBalanceThisEpoch = dustLock.balanceOfNFTAt(tokenId, epochTs);

        // whole units: floor(rewardsThisEpoch * userBalanceThisEpoch / totalSupply)
        rewardAmount = Math.mulDiv(rewardsThisEpoch, userBalanceThisEpoch, totalSupply);

        // fractional remainder scaled
        uint256 remainder = mulmod(rewardsThisEpoch, userBalanceThisEpoch, totalSupply);
        scaledRemainder = Math.mulDiv(remainder, REWARDS_REMAINING_SCALE, totalSupply);
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
