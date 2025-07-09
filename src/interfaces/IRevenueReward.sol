// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {IDustLock} from "../interfaces/IDustLock.sol";

interface IRevenueReward {
    event ClaimRewards(address indexed user, address indexed token, uint256 amount);
    event NotifyReward(address indexed from, address indexed token, uint256 epoch, uint256 amount);
    event RecoverTokens(address indexed token, uint256 amount);
    event SelfRepayingLoanUpdate(uint256 indexed token, address rewardReceiver, bool isEnabled);

    error ZeroAmount();
    error NotRewardDistributor();
    error NotOwner();

    /// @notice The address of the DustLock contract.
    function dustLock() external view returns (IDustLock);

    /// @notice The duration of a reward epoch.
    function DURATION() external view returns (uint256);

    /// @notice Returns the last time rewards were claimed for a specific token and veNFT.
    function lastEarnTime(address token, uint256 tokenId) external view returns (uint256);

    /// @notice Returns the address allowed to add rewards to contract.
    function rewardDistributor() external view returns (address);

    /// @notice Checks if a token is a registered reward token.
    function isRewardToken(address token) external view returns (bool);

    /// @notice Returns the reward token at a specific index in the list of rewards.
    function rewardTokens(uint256 index) external view returns (address);

    /// @notice Returns the sum of all rewards per token
    function totalRewardsPerToken(address token) external view returns (uint256);

    /// @notice Returns the amount of rewards for a token in a specific epoch.
    function tokenRewardsPerEpoch(address token, uint256 epoch) external view returns (uint256);

    /// @notice Claims the accumulated rewards for a specific veNFT.
    /// @param tokenId The ID of the veNFT.
    /// @param tokens The list of reward token addresses to claim.
    function getReward(uint256 tokenId, address[] memory tokens) external;

    /// @notice Called by a reward distributor to notify the contract of new rewards.
    /// @param token The address of the reward token.
    /// @param amount The amount of rewards being added.
    function notifyRewardAmount(address token, uint256 amount) external;

    /// @notice Sets the address allowed to add rewards to contract.
    function setRewardDistributor(address newRewardDistributor) external;

    /// @notice Returns tokens that were transferred and not notified back the current rewards distributor.
    function recoverTokens() external;
}