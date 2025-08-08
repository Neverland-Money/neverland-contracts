// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {IDustLock} from "../interfaces/IDustLock.sol";
import {SafeCastLibrary} from "./SafeCastLibrary.sol";

library BalanceLogicLibrary {
    using SafeCastLibrary for uint256;
    using SafeCastLibrary for int128;

    /// Constants
    uint256 internal constant WEEK = 1 weeks;
    uint256 internal constant MAX_USER_POINTS = 1_000_000_000;
    uint256 internal constant MAX_CHECKPOINT_ITERATIONS = 255;

    /**
     * @notice Binary search to get the user point index for a token id at or prior to a given timestamp
     * @dev If a user point does not exist prior to the timestamp, this will return 0.
     * @param _userPointEpoch State of all user point epochs
     * @param _userPointHistory State of all user point history
     * @param _tokenId The ID of the veNFT to query
     * @param _timestamp The timestamp to find the user point at or before
     * @return User point index
     */
    function getPastUserPointIndex(
        mapping(uint256 => uint256) storage _userPointEpoch,
        mapping(uint256 => IDustLock.UserPoint[MAX_USER_POINTS]) storage _userPointHistory,
        uint256 _tokenId,
        uint256 _timestamp
    ) internal view returns (uint256) {
        uint256 _userEpoch = _userPointEpoch[_tokenId];
        if (_userEpoch == 0) return 0;
        // First check most recent balance
        if (_userPointHistory[_tokenId][_userEpoch].ts <= _timestamp) return (_userEpoch);
        // Next check implicit zero balance
        if (_userPointHistory[_tokenId][1].ts > _timestamp) return 0;

        uint256 lower = 0;
        uint256 upper = _userEpoch;
        while (upper > lower) {
            uint256 center = upper - (upper - lower) / 2; // ceil, avoiding overflow
            IDustLock.UserPoint storage userPoint = _userPointHistory[_tokenId][center];
            if (userPoint.ts == _timestamp) {
                return center;
            } else if (userPoint.ts < _timestamp) {
                lower = center;
            } else {
                upper = center - 1;
            }
        }
        return lower;
    }

    /**
     * @notice Binary search to get the global point index at or prior to a given timestamp
     * @dev If a checkpoint does not exist prior to the timestamp, this will return 0.
     * @param _epoch Current global point epoch
     * @param _pointHistory State of all global point history
     * @param _timestamp The timestamp to find the global point at or before
     * @return Global point index
     */
    function getPastGlobalPointIndex(
        uint256 _epoch,
        mapping(uint256 => IDustLock.GlobalPoint) storage _pointHistory,
        uint256 _timestamp
    ) internal view returns (uint256) {
        if (_epoch == 0) return 0;
        // First check most recent balance
        if (_pointHistory[_epoch].ts <= _timestamp) return (_epoch);
        // Next check implicit zero balance
        if (_pointHistory[1].ts > _timestamp) return 0;

        uint256 lower = 0;
        uint256 upper = _epoch;
        while (upper > lower) {
            uint256 center = upper - (upper - lower) / 2; // ceil, avoiding overflow
            IDustLock.GlobalPoint storage globalPoint = _pointHistory[center];
            if (globalPoint.ts == _timestamp) {
                return center;
            } else if (globalPoint.ts < _timestamp) {
                lower = center;
            } else {
                upper = center - 1;
            }
        }
        return lower;
    }

    /**
     * @notice Get the current voting power for `_tokenId`
     * @dev Adheres to the ERC20 `balanceOf` interface for Aragon compatibility
     *      Fetches last user point prior to a certain timestamp, then walks forward to timestamp.
     * @param _userPointEpoch State of all user point epochs
     * @param _userPointHistory State of all user point history
     * @param _tokenId NFT for lock
     * @param _t Epoch time to return voting power at
     * @return User voting power
     */
    function balanceOfNFTAt(
        mapping(uint256 => uint256) storage _userPointEpoch,
        mapping(uint256 => IDustLock.UserPoint[MAX_USER_POINTS]) storage _userPointHistory,
        uint256 _tokenId,
        uint256 _t
    ) external view returns (uint256) {
        uint256 _epoch = getPastUserPointIndex(_userPointEpoch, _userPointHistory, _tokenId, _t);
        // epoch 0 is an empty point
        if (_epoch == 0) return 0;
        IDustLock.UserPoint memory lastPoint = _userPointHistory[_tokenId][_epoch];
        if (lastPoint.permanent != 0) {
            return lastPoint.permanent;
        } else {
            // Time difference in seconds, slope is in WAD format
            // slope * time_seconds gives WAD result
            lastPoint.bias -= lastPoint.slope * int256(_t - lastPoint.ts);
            if (lastPoint.bias < 0) {
                lastPoint.bias = 0;
            }
            // Convert from WAD (18 decimals) back to token units with proper rounding
            return uint256(lastPoint.bias) / 1e18;
        }
    }

    /**
     * @notice Calculate total voting power at some point in the past
     * @param _slopeChanges State of all slopeChanges
     * @param _pointHistory State of all global point history
     * @param _epoch The epoch to start search from
     * @param _t Time to calculate the total voting power at
     * @return Total voting power at that time
     */
    function supplyAt(
        mapping(uint256 => int256) storage _slopeChanges,
        mapping(uint256 => IDustLock.GlobalPoint) storage _pointHistory,
        uint256 _epoch,
        uint256 _t
    ) external view returns (uint256) {
        uint256 epoch_ = getPastGlobalPointIndex(_epoch, _pointHistory, _t);
        // epoch 0 is an empty point
        if (epoch_ == 0) return 0;
        IDustLock.GlobalPoint memory _point = _pointHistory[epoch_];
        int256 bias = _point.bias;
        int256 slope = _point.slope;
        uint256 ts = _point.ts;
        uint256 t_i = (ts / WEEK) * WEEK;
        for (uint256 i = 0; i < MAX_CHECKPOINT_ITERATIONS; ++i) {
            t_i += WEEK;
            int256 dSlope = 0;
            if (t_i > _t) {
                t_i = _t;
            } else {
                dSlope = _slopeChanges[t_i];
            }
            // Time difference in seconds, slope is in WAD format
            bias -= slope * int256(t_i - ts);
            if (t_i == _t) {
                break;
            }
            slope += dSlope;
            ts = t_i;
        }

        if (bias < 0) {
            bias = 0;
        }
        // Convert from WAD (18 decimals) back to token units with proper rounding
        return uint256(bias) / 1e18 + _point.permanentLockBalance;
    }
}
