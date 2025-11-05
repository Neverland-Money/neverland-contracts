// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

/**
 * @title IEpochManager
 * @author Neverland
 * @notice Interface for managing leaderboard epochs
 */
interface IEpochManager {
    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown when trying to start epoch while previous is still active
    error EpochStillActive();

    /// @notice Thrown when trying to end epoch but none is active
    error NoEpochToEnd();

    /// @notice Thrown when trying to end an already ended epoch
    error EpochAlreadyEnded();

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Emitted when a new epoch starts
     * @param epochNumber The new epoch number
     * @param startBlock Block number when epoch started
     * @param startTime Timestamp when epoch started
     * @param previousEpochNumber The previous epoch number (0 if first)
     * @param previousEpochEndBlock Block when previous epoch ended (0 if first)
     * @param previousEpochEndTime Timestamp when previous epoch ended (0 if first)
     */
    event EpochStarted(
        uint256 indexed epochNumber,
        uint256 startBlock,
        uint256 startTime,
        uint256 previousEpochNumber,
        uint256 previousEpochEndBlock,
        uint256 previousEpochEndTime
    );

    /**
     * @notice Emitted when an epoch ends
     * @param epochNumber The epoch number that ended
     * @param endBlock Block number when epoch ended
     * @param endTime Timestamp when epoch ended
     * @param startBlock Block number when this epoch started
     * @param startTime Timestamp when this epoch started
     * @param duration Duration of the epoch in seconds
     */
    event EpochEnded(
        uint256 indexed epochNumber,
        uint256 endBlock,
        uint256 endTime,
        uint256 startBlock,
        uint256 startTime,
        uint256 duration
    );

    /*//////////////////////////////////////////////////////////////
                               ACTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Starts a new epoch
     * @dev If currentEpoch is 0 (leaderboard not started), this starts epoch 1
     * @dev Otherwise, starts the next epoch (previous must be ended first)
     * @dev This allows gaps between epochs for prize distribution, etc.
     */
    function startNewEpoch() external;

    /**
     * @notice Ends the current epoch without starting a new one
     * @dev Allows for gap periods between epochs
     * @dev Reverts if no epoch is active or epoch already ended
     */
    function endCurrentEpoch() external;

    /*//////////////////////////////////////////////////////////////
                                 VIEWS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get the current epoch number
     * @return Current epoch number
     */
    function currentEpoch() external view returns (uint256);

    /**
     * @notice Get the current epoch start block
     * @return Block number when current epoch started
     */
    function currentEpochStartBlock() external view returns (uint256);

    /**
     * @notice Get the current epoch start timestamp
     * @return Timestamp when current epoch started
     */
    function currentEpochStartTime() external view returns (uint256);

    /**
     * @notice Get epoch details by epoch number
     * @param epochNumber The epoch number to query
     * @return startBlock Block when epoch started
     * @return startTime Timestamp when epoch started
     * @return endBlock Block when epoch ended (0 if current)
     * @return endTime Timestamp when epoch ended (0 if current)
     */
    function getEpochDetails(uint256 epochNumber)
        external
        view
        returns (uint256 startBlock, uint256 startTime, uint256 endBlock, uint256 endTime);

    /**
     * @notice Check if an epoch is active
     * @param epochNumber The epoch number to check
     * @return True if epoch is current and active
     */
    function isEpochActive(uint256 epochNumber) external view returns (bool);

    /**
     * @notice Check if the leaderboard has started
     * @return True if at least one epoch has been started (currentEpoch > 0)
     */
    function hasStarted() external view returns (bool);

    /**
     * @notice Check if currently in a gap period (between epochs)
     * @return True if leaderboard has started but no epoch is currently active
     */
    function isInGapPeriod() external view returns (bool);
}
