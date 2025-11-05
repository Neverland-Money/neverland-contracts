// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {CommonChecksLibrary} from "../libraries/CommonChecksLibrary.sol";
import {IEpochManager} from "../interfaces/IEpochManager.sol";

/**
 * @title EpochManager
 * @author Neverland
 * @notice Manages leaderboard epochs for the Neverland points system
 * @dev Emits events that the subgraph listens to for epoch transitions
 */
contract EpochManager is IEpochManager, Ownable {
    /*//////////////////////////////////////////////////////////////
                          STORAGE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Current epoch number
    uint256 public currentEpoch;

    /// @notice Block number when current epoch started
    uint256 public currentEpochStartBlock;

    /// @notice Timestamp when current epoch started
    uint256 public currentEpochStartTime;

    /// @notice Mapping of epoch number to start block
    mapping(uint256 => uint256) public epochStartBlocks;

    /// @notice Mapping of epoch number to start timestamp
    mapping(uint256 => uint256) public epochStartTimes;

    /// @notice Mapping of epoch number to end block
    mapping(uint256 => uint256) public epochEndBlocks;

    /// @notice Mapping of epoch number to end timestamp
    mapping(uint256 => uint256) public epochEndTimes;

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initialize the manager (leaderboard not started yet)
     * @param _initialOwner Initial owner for Ownable
     */
    constructor(address _initialOwner) {
        _transferOwnership(_initialOwner);
        CommonChecksLibrary.revertIfZeroAddress(_initialOwner);
        // currentEpoch starts at 0 (leaderboard not started)
    }

    /*//////////////////////////////////////////////////////////////
                               ACTIONS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IEpochManager
    function startNewEpoch() external onlyOwner {
        if (currentEpoch != 0 && epochEndBlocks[currentEpoch] == 0) revert EpochStillActive();

        uint256 previousEpoch = currentEpoch;
        uint256 previousEndBlock = epochEndBlocks[previousEpoch];
        uint256 previousEndTime = epochEndTimes[previousEpoch];

        // Start new epoch
        ++currentEpoch;
        currentEpochStartBlock = block.number;
        currentEpochStartTime = block.timestamp;

        epochStartBlocks[currentEpoch] = block.number;
        epochStartTimes[currentEpoch] = block.timestamp;

        emit EpochStarted(currentEpoch, block.number, block.timestamp, previousEpoch, previousEndBlock, previousEndTime);
    }

    /// @inheritdoc IEpochManager
    function endCurrentEpoch() external onlyOwner {
        if (currentEpoch == 0) revert NoEpochToEnd();
        if (epochEndBlocks[currentEpoch] != 0) revert EpochAlreadyEnded();

        uint256 epochNumber = currentEpoch;
        uint256 startBlock = currentEpochStartBlock;
        uint256 startTime = currentEpochStartTime;

        // End current epoch
        epochEndBlocks[currentEpoch] = block.number;
        epochEndTimes[currentEpoch] = block.timestamp;
        uint256 duration = block.timestamp - currentEpochStartTime;

        // Clear current epoch tracking (in gap period now)
        currentEpochStartBlock = 0;
        currentEpochStartTime = 0;

        emit EpochEnded(epochNumber, block.number, block.timestamp, startBlock, startTime, duration);
    }

    /*//////////////////////////////////////////////////////////////
                                 VIEWS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IEpochManager
    function getEpochDetails(uint256 epochNumber)
        external
        view
        returns (uint256 startBlock, uint256 startTime, uint256 endBlock, uint256 endTime)
    {
        return (
            epochStartBlocks[epochNumber],
            epochStartTimes[epochNumber],
            epochEndBlocks[epochNumber],
            epochEndTimes[epochNumber]
        );
    }

    /// @inheritdoc IEpochManager
    function isEpochActive(uint256 epochNumber) external view returns (bool) {
        return epochNumber == currentEpoch && epochEndBlocks[currentEpoch] == 0;
    }

    /// @inheritdoc IEpochManager
    function hasStarted() external view returns (bool) {
        return currentEpoch > 0;
    }

    /// @inheritdoc IEpochManager
    function isInGapPeriod() external view returns (bool) {
        return currentEpoch > 0 && epochEndBlocks[currentEpoch] > 0;
    }
}
