// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";

import {IUserVaultRegistry} from "../interfaces/IUserVaultRegistry.sol";

import {CommonChecksLibrary} from "../libraries/CommonChecksLibrary.sol";

/**
 * @title UserVaultRegistry
 * @author Neverland
 * @notice Registry contract for UserVaults
 */
contract UserVaultRegistry is IUserVaultRegistry, Ownable2Step {
    /*//////////////////////////////////////////////////////////////
                          STORAGE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IUserVaultRegistry
    address public override executor;

    /// @inheritdoc IUserVaultRegistry
    uint256 public override maxSwapSlippageBps;

    /// @notice Mapping of supported aggregators
    mapping(address => bool) private supportedAggregators;

    /*//////////////////////////////////////////////////////////////
                                ADMIN
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IUserVaultRegistry
    function setExecutor(address _executor) external onlyOwner {
        CommonChecksLibrary.revertIfZeroAddress(_executor);
        address old = executor;
        executor = _executor;
        emit ExecutorUpdated(old, _executor);
    }

    /// @inheritdoc IUserVaultRegistry
    function setSupportedAggregators(address aggregator, bool isActive) external onlyOwner {
        supportedAggregators[aggregator] = isActive;
        emit AggregatorSupportUpdated(aggregator, isActive);
    }

    /// @inheritdoc IUserVaultRegistry
    function setMaxSwapSlippageBps(uint256 newMaxSwapSlippageBps) external onlyOwner {
        uint256 old = maxSwapSlippageBps;
        maxSwapSlippageBps = newMaxSwapSlippageBps;
        emit MaxSwapSlippageUpdated(old, newMaxSwapSlippageBps);
    }

    /// @notice Disabled to prevent accidental renouncement of ownership
    function renounceOwnership() public view override onlyOwner {
        revert();
    }

    /*//////////////////////////////////////////////////////////////
                                 VIEWS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IUserVaultRegistry
    function isSupportedAggregator(address aggregator) external view returns (bool) {
        return supportedAggregators[aggregator];
    }
}
