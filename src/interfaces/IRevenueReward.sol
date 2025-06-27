// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {IDustLock} from "../interfaces/IDustLock.sol";

interface IRevenueReward {
    /// @dev Emitted when a user claims rewards.
    event ClaimRewards(address indexed user, address indexed token, uint256 amount);

    /// @dev Emitted when new rewards are added to the contract.
    event NotifyReward(address indexed from, address indexed token, uint256 epoch, uint256 amount);

    /// @dev Thrown when a zero amount is provided for rewards.
    error ZeroAmount();

    /// @notice Claims the accumulated rewards for a specific veNFT.
    /// @param tokenId The ID of the veNFT.
    /// @param tokens The list of reward token addresses to claim.
    function getReward(uint256 tokenId, address[] memory tokens) external;

    /// @notice Called by a reward distributor to notify the contract of new rewards.
    /// @param token The address of the reward token.
    /// @param amount The amount of rewards being added.
    function notifyRewardAmount(address token, uint256 amount) external;

    /// @notice The address of the DustLock contract.
    function dustLock() external view returns (IDustLock);

    /// @notice The duration of a reward epoch.
    function DURATION() external view returns (uint256);

    /// @notice Returns the last time rewards were claimed for a specific token and veNFT.
    function lastEarnTime(address token, uint256 tokenId) external view returns (uint256);

    /// @notice Returns the amount claimed for a specific veNFT in a given epoch.
    function claimed(uint256 tokenId, uint256 epoch) external view returns (uint256);

    /// @notice Checks if a token is a registered reward token.
    function isReward(address token) external view returns (bool);

    /// @notice Returns the reward token at a specific index in the list of rewards.
    function rewards(uint256 index) external view returns (address);

    /// @notice Returns the amount of rewards for a token in a specific epoch.
    function tokenRewardsPerEpoch(address token, uint256 epoch) external view returns (uint256);
}