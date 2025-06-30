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

contract RevenueReward is IRevenueReward, ERC2771Context, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IDustLock public dustLock;

    /// @inheritdoc IRevenueReward
    uint256 public constant DURATION = 7 days;

    /// @inheritdoc IRevenueReward
    mapping(address => mapping(uint256 => uint256)) public lastEarnTime;

    /// @inheritdoc IRevenueReward
    mapping(uint256 => mapping(uint256 => uint256)) public claimed;

    /// @inheritdoc IRevenueReward
    mapping(address => bool) public isReward;
    /// @inheritdoc IRevenueReward
    address[] public rewards;
    /// @inheritdoc IRevenueReward
    mapping(address => mapping(uint256 => uint256)) public tokenRewardsPerEpoch;

    constructor(address _forwarder, address _dustLock) ERC2771Context(_forwarder) {
        dustLock = IDustLock(_dustLock);
    }

    /// @inheritdoc IRevenueReward
    function getReward(uint256 tokenId, address[] memory tokens) external virtual nonReentrant {
        uint256 _length = tokens.length;
        address _owner = dustLock.ownerOf(tokenId);

        for (uint256 i = 0; i < _length; i++) {
            uint256 _reward = earned(tokens[i], tokenId);

            lastEarnTime[tokens[i]][tokenId] = block.timestamp;

            if (_reward > 0) IERC20(tokens[i]).safeTransfer(_owner, _reward);

            emit ClaimRewards(_owner, tokens[i], _reward);
        }
    }

    /// @inheritdoc IRevenueReward
    /// @notice Reward amounts added during the epoch are added to be claimable at the end of the epoch
    function notifyRewardAmount(address token, uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        if (!isReward[token]) {
            isReward[token] = true;
            rewards.push(token);
        }

        address sender = _msgSender();
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

}