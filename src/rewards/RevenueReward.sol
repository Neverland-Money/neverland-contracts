// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {ERC2771Context} from "@openzeppelin/contracts/metatx/ERC2771Context.sol";
import {EpochTimeLibrary} from "../libraries/EpochTimeLibrary.sol";
import {IDustLock} from "../interfaces/IDustLock.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IRevenueReward} from "../interfaces/IRevenueReward.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {console2} from "forge-std/console2.sol";

/// @title RevenueReward
/// @notice Stores ERC20 token rewards and provides them to veDUST owners
contract RevenueReward is IRevenueReward, ERC2771Context, ReentrancyGuard {
    using SafeERC20 for IERC20;

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
    mapping(uint256 => address) public tokenRewardReceiver;

    constructor(address _forwarder, address _dustLock, address _rewardDistributor) ERC2771Context(_forwarder) {
        dustLock = IDustLock(_dustLock);
        rewardDistributor = _rewardDistributor;
    }

    /// @inheritdoc IRevenueReward
    function enableSelfRepayLoan(uint256 tokenId, address rewardReceiver) external virtual nonReentrant {
        if (_msgSender() != dustLock.ownerOf(tokenId)) revert NotOwner();
        tokenRewardReceiver[tokenId] = rewardReceiver;
        emit SelfRepayingLoanUpdate(tokenId, rewardReceiver, true);
    }

    /// @inheritdoc IRevenueReward
    function disableSelfRepayLoan(uint256 tokenId) external virtual nonReentrant {
        if (_msgSender() != dustLock.ownerOf(tokenId)) revert NotOwner();
        tokenRewardReceiver[tokenId] = address(0);
        emit SelfRepayingLoanUpdate(tokenId, address(0), false);
    }

    /// @inheritdoc IRevenueReward
    function getReward(uint256 tokenId, address[] memory tokens) external virtual nonReentrant {
        address rewardsReceiver = tokenRewardReceiver[tokenId];
        if(rewardsReceiver == address(0)) {
            rewardsReceiver = dustLock.ownerOf(tokenId);
        }

        uint256 _length = tokens.length;
        for (uint256 i = 0; i < _length; i++) {
            uint256 _reward = earned(tokens[i], tokenId);

            lastEarnTime[tokens[i]][tokenId] = block.timestamp;

            if (_reward > 0) IERC20(tokens[i]).safeTransfer(rewardsReceiver, _reward);

            emit ClaimRewards(rewardsReceiver, tokens[i], _reward);
        }
    }

    /// @inheritdoc IRevenueReward
    /// @notice Reward amounts added during the epoch are added to be claimable at the end of the epoch
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

    /// @notice Calculates token's reward from last claimed start epoch until current start epoch
    function earned(address token, uint256 tokenId) internal view returns (uint256) {
        // take start epoch of last claimed, as starting point
        uint256 _startTs = EpochTimeLibrary.epochNext(lastEarnTime[token][tokenId]);
        uint256 _endTs = EpochTimeLibrary.epochStart(block.timestamp);

        if(_startTs > _endTs) return 0;

        // get epochs between last claimed staring epoch and current stating epoch
        uint256 _numEpochs = (_endTs - _startTs) / DURATION;

        uint256 reward = 0;
        uint256 _currTs = _startTs;
        if (_numEpochs > 0) {
            for (uint256 i = 0; i <= _numEpochs; i++) {
                uint256 tokenSupplyBalanceCurrTs = dustLock.totalSupplyAt(_currTs);
                if (tokenSupplyBalanceCurrTs == 0) {
                    _currTs += DURATION;
                    continue;
                }
                // totalRewardPerEpoch * tokenBalanceCurrTs / tokenSupplyBalanceCurrTs
                reward += (tokenRewardsPerEpoch[token][_currTs] * dustLock.balanceOfNFTAt(tokenId, _currTs) / tokenSupplyBalanceCurrTs);
                _currTs += DURATION;
            }
        }

        return reward;
    }

    function setRewardDistributor(address newRewardDistributor) external {
        if (_msgSender() != rewardDistributor) revert NotRewardDistributor();
        rewardDistributor = newRewardDistributor;
    }

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