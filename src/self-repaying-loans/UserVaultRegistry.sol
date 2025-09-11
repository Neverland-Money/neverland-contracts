// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

import {IRevenueReward} from "../interfaces/IRevenueReward.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IUserVaultRegistry} from "../interfaces/IUserVaultRegistry.sol";

contract UserVaultRegistry is IUserVaultRegistry, Ownable {
    address public executor;
    mapping(address => bool) private supportedAggregators;
    uint256 public maxSwapSlippageBps;

    function setExecutor(address _executor) external onlyOwner {
        executor = _executor;
    }

    function setSupportedAggregators(address aggregator, bool isActive) external onlyOwner {
        supportedAggregators[aggregator] = isActive;
    }

    function isSupportedAggregator(address aggregator) external view returns (bool) {
        return supportedAggregators[aggregator];
    }

    function setMaxSwapSlippageBps(uint256 newMaxSwapSlippageBps) external onlyOwner {
        maxSwapSlippageBps = newMaxSwapSlippageBps;
    }
}
