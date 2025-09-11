// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

/**
 * @title EpochTimeLibrary
 * @author Extended by Neverland
 * @notice Shared helpers for epoch time calculations
 */
library EpochTimeLibrary {
    uint256 internal constant WEEK = 7 days;

    /**
     * @notice Returns the start time of the current epoch containing the given timestamp
     * @dev Calculates the beginning of a week period by removing the remainder when dividing by WEEK
     * @param timestamp The timestamp to calculate the epoch start for
     * @return The timestamp for the start of the current epoch
     */
    function epochStart(uint256 timestamp) internal pure returns (uint256) {
        unchecked {
            return timestamp - (timestamp % WEEK);
        }
    }

    /**
     * @notice Returns the start time of the next epoch after the given timestamp
     * @dev Calculates the beginning of the next week period by removing the remainder when dividing by WEEK and adding one WEEK
     * @param timestamp The timestamp to calculate the next epoch from
     * @return The timestamp for the start of the next epoch
     */
    function epochNext(uint256 timestamp) internal pure returns (uint256) {
        unchecked {
            return timestamp - (timestamp % WEEK) + WEEK;
        }
    }

    /**
     * @notice Returns the start time of the voting window within the current epoch
     * @dev Voting begins 1 hour after the start of the epoch
     * @param timestamp The timestamp within the current epoch
     * @return The timestamp when voting begins in the current epoch
     */
    function epochVoteStart(uint256 timestamp) internal pure returns (uint256) {
        unchecked {
            return timestamp - (timestamp % WEEK) + 1 hours;
        }
    }

    /**
     * @notice Returns the end time of the voting window within the current epoch
     * @dev Voting ends 1 hour before the end of the epoch
     * @param timestamp The timestamp within the current epoch
     * @return The timestamp when voting ends in the current epoch
     */
    function epochVoteEnd(uint256 timestamp) internal pure returns (uint256) {
        unchecked {
            return timestamp - (timestamp % WEEK) + WEEK - 1 hours;
        }
    }
}
