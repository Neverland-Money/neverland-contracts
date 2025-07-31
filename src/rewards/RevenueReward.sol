// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {ERC2771ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/metatx/ERC2771ContextUpgradeable.sol";
import {ERC2771Context} from "@openzeppelin/contracts/metatx/ERC2771Context.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {EpochTimeLibrary} from "../libraries/EpochTimeLibrary.sol";
import {IDustLock} from "../interfaces/IDustLock.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IRevenueReward} from "../interfaces/IRevenueReward.sol";
import {IUserVaultFactory} from "../interfaces/IUserVaultFactory.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title RevenueReward
 * @notice Stores ERC20 token rewards and provides them to veDUST owners
 */
contract RevenueReward is Initializable, ReentrancyGuardUpgradeable, ERC2771ContextUpgradeable, IRevenueReward {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.UintSet;
    using EnumerableSet for EnumerableSet.AddressSet;

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address _forwarder) ERC2771ContextUpgradeable(_forwarder) {
        _disableInitializers();
    }

    /*//////////////////////////////////////////////////////////////
                        STORAGE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IRevenueReward
    IDustLock public dustLock;
    /// @inheritdoc IRevenueReward
    IUserVaultFactory public userVaultFactory;
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
    mapping(uint256 => address) public tokenRewardReceiver;
    mapping(address => EnumerableSet.UintSet) private userTokensWithSelfRepayingLoan;
    EnumerableSet.AddressSet private usersWithSelfRepayingLoan;

    /// tokenId -> block.timestamp of token_id minted
    mapping(uint256 => uint256) tokenMintTime;

    function initialize(IDustLock _dustLock, address _rewardDistributor, IUserVaultFactory _userVaultFactory)
        public
        initializer
    {
        dustLock = _dustLock;
        userVaultFactory = _userVaultFactory;
        rewardDistributor = _rewardDistributor;
    }

    /*//////////////////////////////////////////////////////////////
                           SELF REPAYING LOANS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IRevenueReward
    function enableSelfRepayLoan(uint256 tokenId) external virtual nonReentrant {
        address sender = _msgSender();
        if (sender != dustLock.ownerOf(tokenId)) revert NotOwner();

        address userVault = userVaultFactory.getUserVault(_msgSender());

        tokenRewardReceiver[tokenId] = userVault;
        usersWithSelfRepayingLoan.add(sender);
        userTokensWithSelfRepayingLoan[sender].add(tokenId);

        emit SelfRepayingLoanUpdate(tokenId, userVault, true);
    }

    /// @inheritdoc IRevenueReward
    function disableSelfRepayLoan(uint256 tokenId) external virtual nonReentrant {
        address sender = _msgSender();
        address tokenOwner = dustLock.ownerOf(tokenId);
        if (sender != tokenOwner) revert NotOwner();

        _removeToken(tokenId, tokenOwner);

        emit SelfRepayingLoanUpdate(tokenId, address(0), false);
    }

    function _notifyTokenTransferred(uint256 _tokenId, address _from) public {
        if (_msgSender() != address(dustLock)) revert NotDustLock();
        _removeToken(_tokenId, _from);
    }

    function _notifyBeforeTokenBurned(uint256 _tokenId, address _from) public {
        if (_msgSender() != address(dustLock)) revert NotDustLock();
        getReward(_tokenId, rewardTokens);
        _removeToken(_tokenId, _from);
    }

    /* === view functions === */

    /// @inheritdoc IRevenueReward
    function getUsersWithSelfRepayingLoan(uint256 from, uint256 to) external view returns (address[] memory) {
        require(to >= from, "Invalid range");
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
    function getUserTokensWithSelfRepayingLoan(address user) external view returns (uint256[] memory tokenIds) {
        uint256 len = userTokensWithSelfRepayingLoan[user].length();
        tokenIds = new uint256[](len);
        for (uint256 i = 0; i < len; i++) {
            tokenIds[i] = userTokensWithSelfRepayingLoan[user].at(i);
        }
    }

    /* === helper functions === */

    function _removeToken(uint256 _tokenId, address _tokenOwner) internal {
        tokenRewardReceiver[_tokenId] = address(0);
        userTokensWithSelfRepayingLoan[_tokenOwner].remove(_tokenId);
        if (userTokensWithSelfRepayingLoan[_tokenOwner].length() <= 0) {
            usersWithSelfRepayingLoan.remove(_tokenOwner);
        }
    }

    /*//////////////////////////////////////////////////////////////
                                REWARDS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Sets the address authorized to notify new rewards
     * @dev Only callable by the current reward distributor
     * @param newRewardDistributor The new address authorized to notify new rewards
     */
    function setRewardDistributor(address newRewardDistributor) external {
        if (_msgSender() != rewardDistributor) revert NotRewardDistributor();
        rewardDistributor = newRewardDistributor;
    }

    /// @inheritdoc IRevenueReward
    function getReward(uint256 tokenId, address[] memory tokens) public virtual {
        getRewardUntilTs(tokenId, tokens, block.timestamp);
    }

    /// @inheritdoc IRevenueReward
    function getRewardUntilTs(uint256 tokenId, address[] memory tokens, uint256 rewardPeriodEndTs)
        public
        virtual
        nonReentrant
    {
        address rewardsReceiver = tokenRewardReceiver[tokenId];
        if (rewardsReceiver == address(0)) {
            rewardsReceiver = dustLock.ownerOf(tokenId);
        }

        uint256 _length = tokens.length;

        for (uint256 i = 0; i < _length; i++) {
            uint256 _reward = earned(tokens[i], tokenId, rewardPeriodEndTs);

            if (_reward > 0) {
                lastEarnTime[tokens[i]][tokenId] = rewardPeriodEndTs;
                IERC20(tokens[i]).safeTransfer(rewardsReceiver, _reward);
            }

            emit ClaimRewards(rewardsReceiver, tokens[i], _reward);
        }
    }

    /// @inheritdoc IRevenueReward
    function notifyRewardAmount(address token, uint256 amount) external nonReentrant {
        if (_msgSender() != rewardDistributor) revert NotRewardDistributor();
        if (amount == 0) revert ZeroAmount();
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

    function _notifyTokenMinted(uint256 _tokenId) public {
        if (_msgSender() != address(dustLock)) revert NotDustLock();
        tokenMintTime[_tokenId] = block.timestamp;
    }

    /* === helper functions === */

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
    function earned(address token, uint256 tokenId, uint256 endTs) internal view returns (uint256) {
        if (endTs > block.timestamp) {
            revert EndTimestampMoreThanCurrent();
        }

        uint256 lastTokenEarnTime = Math.max(lastEarnTime[token][tokenId], tokenMintTime[tokenId]);
        uint256 _startTs = EpochTimeLibrary.epochNext(lastTokenEarnTime);
        uint256 _endTs = EpochTimeLibrary.epochStart(endTs);

        if (_startTs > _endTs) return 0;

        // get epochs between last claimed staring epoch and current stating epoch
        uint256 _numEpochs = (_endTs - _startTs) / DURATION;

        uint256 reward = 0;
        uint256 _currTs = _startTs;
        for (uint256 i = 0; i <= _numEpochs; i++) {
            uint256 tokenSupplyBalanceCurrTs = dustLock.totalSupplyAt(_currTs);
            if (tokenSupplyBalanceCurrTs == 0) {
                _currTs += DURATION;
                continue;
            }
            // totalRewardPerEpoch * tokenBalanceCurrTs / tokenSupplyBalanceCurrTs
            reward += (
                tokenRewardsPerEpoch[token][_currTs] * dustLock.balanceOfNFTAt(tokenId, _currTs)
                    / tokenSupplyBalanceCurrTs
            );
            _currTs += DURATION;
        }

        return reward;
    }

    /*//////////////////////////////////////////////////////////////
                                RECOVERY
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Recovers unnotified rewards from the contract
     * @dev Only callable by the current reward distributor
     * @dev Transfers any unnotified rewards to the distributor
     */
    function recoverTokens() external {
        if (_msgSender() != rewardDistributor) revert NotRewardDistributor();

        for (uint256 i = 0; i < rewardTokens.length; i++) {
            address token = rewardTokens[i];
            uint256 balance = IERC20(token).balanceOf(address(this));
            uint256 unnotifiedTokenAmount = balance - totalRewardsPerToken[token];
            if (unnotifiedTokenAmount > 0) {
                IERC20(token).safeTransfer(rewardDistributor, unnotifiedTokenAmount);
                emit RecoverTokens(token, balance);
            }
        }
    }
}
