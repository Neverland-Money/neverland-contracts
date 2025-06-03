// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {BalanceLogicLibrary} from "./BalanceLogicLibrary.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IDustLock} from "../interfaces/IDustLock.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeCastLibrary} from "../_utils/SafeCastLibrary.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract DustLock is IDustLock, ERC721, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using SafeCastLibrary for uint256;
    using SafeCastLibrary for int128;

    /* ========== CONSTANTS ========== */

    uint256 internal constant WEEK = 1 weeks;
    uint256 internal constant MAXTIME = 4 * 365 * 86400;
    int128 internal constant iMAXTIME = 4 * 365 * 86400;
    uint256 internal constant MULTIPLIER = 1 ether;
    /// @inheritdoc IDustLock
    address public immutable token;

    /* ========== STATE ========== */

    // @notice next veDUST token id
    uint256 private _nextTokenId;
    /// @inheritdoc IDustLock
    uint256 public supply;
    /// @inheritdoc IDustLock
    uint256 public epoch;

    // @inheritdoc IDustLock
    mapping(uint256 => int128) public slopeChanges;
    // @notice tokenId => latest epoch
    mapping(uint256 => uint256) public userPointEpoch;
    // TODO: not needed
    /// @inheritdoc IDustLock
    uint256 public permanentLockBalance;

    // @notice tokenId => LockedBalance
    mapping(uint256 => LockedBalance) internal _locked;
    // @notice tokenId -> UserPoint[epoch]
    mapping(uint256 => UserPoint[1000000000]) internal _userPointHistory;
    // @notice epoch -> GlobalPoint
    mapping(uint256 => GlobalPoint) internal _pointHistory;


    /* ========== CONSTRUCTOR ========== */

    constructor(address _initialOwner, address _token)
        ERC721("veDust", "veDUST")
        Ownable(_initialOwner)
    {
        token = _token;
    }

    /* ========== EXTERNAL VIEW FUNCTIONS ========== */

    /// @inheritdoc IDustLock
    function locked(uint256 _tokenId) external view returns (LockedBalance memory) {
        return _locked[_tokenId];
    }

    /// @inheritdoc IDustLock
    function userPointHistory(uint256 _tokenId, uint256 _loc) external view returns (UserPoint memory) {
        return _userPointHistory[_tokenId][_loc];
    }

    /// @inheritdoc IDustLock
    function pointHistory(uint256 _loc) external view returns (GlobalPoint memory) {
        return _pointHistory[_loc];
    }

    /// @inheritdoc IDustLock
    function balanceOfNFT(uint256 _tokenId) public view returns (uint256) {
        // TODO: this is removed
        // if (ownershipChange[_tokenId] == block.number) return 0;
        return _balanceOfNFTAt(_tokenId, block.timestamp);
    }

    /// @inheritdoc IDustLock
    function balanceOfNFTAt(uint256 _tokenId, uint256 _t) external view returns (uint256) {
        return _balanceOfNFTAt(_tokenId, _t);
    }

    /* ========== INTERNAL VIEW FUNCTIONS ========== */

    /// @notice Get the voting power for _tokenId at a given timestamp
    /// @param _tokenId .
    /// @param _t Timestamp to query voting power
    /// @return Voting power
    function _balanceOfNFTAt(uint256 _tokenId, uint256 _t) internal view returns (uint256) {
        return BalanceLogicLibrary.balanceOfNFTAt(userPointEpoch, _userPointHistory, _tokenId, _t);
    }

    /* ========== EXTERNAL MUTATIVE FUNCTIONS ========== */

    // @inheritdoc IDustLock
    function createLock(uint256 _value, uint256 _lockDuration) external nonReentrant returns (uint256) {
        return _createLock(_value, _lockDuration, _msgSender());
    }

    /// @inheritdoc IDustLock
    function increaseAmount(uint256 _tokenId, uint256 _value) external isTokenOwner(_tokenId) nonReentrant {
        _increaseAmountFor(_tokenId, _value, DepositType.INCREASE_LOCK_AMOUNT);
    }

    /* ========== INTERNAL MUTATIVE FUNCTIONS ========== */

    /// @dev Deposit `_value` tokens for `_to` and lock for `_lockDuration`
    /// @param _value Amount to deposit
    /// @param _lockDuration Number of seconds to lock tokens for (rounded down to nearest week)
    /// @param _to Address to deposit
    function _createLock(uint256 _value, uint256 _lockDuration, address _to) internal returns (uint256) {
        uint256 unlockTime = ((block.timestamp + _lockDuration) / WEEK) * WEEK; // Locktime is rounded down to weeks

        if (_value == 0) revert ZeroAmount();
        if (unlockTime <= block.timestamp) revert LockDurationNotInFuture();
        if (unlockTime > block.timestamp + MAXTIME) revert LockDurationTooLong();

        uint256 _tokenId = ++_nextTokenId;
        _mint(_to, _tokenId);

        _depositFor(_tokenId, _value, unlockTime, _locked[_tokenId], DepositType.CREATE_LOCK_TYPE);
        return _tokenId;
    }

    /// @notice Deposit and lock tokens for a user
    /// @param _tokenId NFT that holds lock
    /// @param _value Amount to deposit
    /// @param _unlockTime New time when to unlock the tokens, or 0 if unchanged
    /// @param _oldLocked Previous locked amount / timestamp
    /// @param _depositType The type of deposit
    function _depositFor(
        uint256 _tokenId,
        uint256 _value,
        uint256 _unlockTime,
        LockedBalance memory _oldLocked,
        DepositType _depositType
    ) internal {
        uint256 supplyBefore = supply;
        supply = supplyBefore + _value;

        // Set newLocked to _oldLocked without mangling memory
        LockedBalance memory newLocked;
        (newLocked.amount, newLocked.end, newLocked.isPermanent) = (
            _oldLocked.amount,
            _oldLocked.end,
            _oldLocked.isPermanent
        );

        // Adding to existing lock, or if a lock is expired - creating a new one
        newLocked.amount += _value.toInt128();
        if (_unlockTime != 0) {
            newLocked.end = _unlockTime;
        }
        _locked[_tokenId] = newLocked;

        // Possibilities:
        // Both _oldLocked.end could be current or expired (>/< block.timestamp)
        // or if the lock is a permanent lock, then _oldLocked.end == 0
        // value == 0 (extend lock) or value > 0 (add to lock or extend lock)
        // newLocked.end > block.timestamp (always)
        _checkpoint(_tokenId, _oldLocked, newLocked);

        address from = _msgSender();
        if (_value != 0) {
            IERC20(token).safeTransferFrom(from, address(this), _value);
        }

        emit Deposit(from, _tokenId, _depositType, _value, newLocked.end, block.timestamp);
        emit Supply(supplyBefore, supplyBefore + _value);
    }

    /// @notice Record global and per-user data to checkpoints. Used by DustLock system.
    /// @param _tokenId NFT token ID. No user checkpoint if 0
    /// @param _oldLocked Previous locked amount / end lock time for the user
    /// @param _newLocked New locked amount / end lock time for the user
    function _checkpoint(uint256 _tokenId, LockedBalance memory _oldLocked, LockedBalance memory _newLocked) internal {
        UserPoint memory uOld;
        UserPoint memory uNew;
        int128 oldDslope = 0;
        int128 newDslope = 0;
        uint256 _epoch = epoch;

        if (_tokenId != 0) {
            uNew.permanent = _newLocked.isPermanent ? _newLocked.amount.toUint256() : 0;
            // Calculate slopes and biases
            // Kept at zero when they have to
            if (_oldLocked.end > block.timestamp && _oldLocked.amount > 0) {
                uOld.slope = _oldLocked.amount / iMAXTIME;
                uOld.bias = uOld.slope * (_oldLocked.end - block.timestamp).toInt128();
            }
            if (_newLocked.end > block.timestamp && _newLocked.amount > 0) {
                uNew.slope = _newLocked.amount / iMAXTIME;
                uNew.bias = uNew.slope * (_newLocked.end - block.timestamp).toInt128();
            }

            // Read values of scheduled changes in the slope
            // _oldLocked.end can be in the past and in the future
            // _newLocked.end can ONLY by in the FUTURE unless everything expired: than zeros
            oldDslope = slopeChanges[_oldLocked.end];
            if (_newLocked.end != 0) {
                if (_newLocked.end == _oldLocked.end) {
                    newDslope = oldDslope;
                } else {
                    newDslope = slopeChanges[_newLocked.end];
                }
            }
        }

        GlobalPoint memory lastPoint = GlobalPoint({
            bias: 0,
            slope: 0,
            ts: block.timestamp,
            blk: block.number,
            permanentLockBalance: 0
        });
        if (_epoch > 0) {
            lastPoint = _pointHistory[_epoch];
        }
        uint256 lastCheckpoint = lastPoint.ts;
        // initialLastPoint is used for extrapolation to calculate block number
        // (approximately, for *At methods) and save them
        // as we cannot figure that out exactly from inside the contract
        GlobalPoint memory initialLastPoint = GlobalPoint({
            bias: lastPoint.bias,
            slope: lastPoint.slope,
            ts: lastPoint.ts,
            blk: lastPoint.blk,
            permanentLockBalance: lastPoint.permanentLockBalance
        });
        uint256 blockSlope = 0; // dblock/dt
        if (block.timestamp > lastPoint.ts) {
            blockSlope = (MULTIPLIER * (block.number - lastPoint.blk)) / (block.timestamp - lastPoint.ts);
        }
        // If last point is already recorded in this block, slope=0
        // But that's ok b/c we know the block in such case

        // Go over weeks to fill history and calculate what the current point is
        {
            uint256 t_i = (lastCheckpoint / WEEK) * WEEK;
            for (uint256 i = 0; i < 255; ++i) {
                // Hopefully it won't happen that this won't get used in 5 years!
                // If it does, users will be able to withdraw but vote weight will be broken
                t_i += WEEK; // Initial value of t_i is always larger than the ts of the last point
                int128 d_slope = 0;
                if (t_i > block.timestamp) {
                    t_i = block.timestamp;
                } else {
                    d_slope = slopeChanges[t_i];
                }
                lastPoint.bias -= lastPoint.slope * (t_i - lastCheckpoint).toInt128();
                lastPoint.slope += d_slope;
                if (lastPoint.bias < 0) {
                    // This can happen
                    lastPoint.bias = 0;
                }
                if (lastPoint.slope < 0) {
                    // This cannot happen - just in case
                    lastPoint.slope = 0;
                }
                lastCheckpoint = t_i;
                lastPoint.ts = t_i;
                lastPoint.blk = initialLastPoint.blk + (blockSlope * (t_i - initialLastPoint.ts)) / MULTIPLIER;
                _epoch += 1;
                if (t_i == block.timestamp) {
                    lastPoint.blk = block.number;
                    break;
                } else {
                    _pointHistory[_epoch] = lastPoint;
                }
            }
        }

        if (_tokenId != 0) {
            // If last point was in this block, the slope change has been applied already
            // But in such case we have 0 slope(s)
            lastPoint.slope += (uNew.slope - uOld.slope);
            lastPoint.bias += (uNew.bias - uOld.bias);
            if (lastPoint.slope < 0) {
                lastPoint.slope = 0;
            }
            if (lastPoint.bias < 0) {
                lastPoint.bias = 0;
            }
            lastPoint.permanentLockBalance = permanentLockBalance;
        }

        // If timestamp of last global point is the same, overwrite the last global point
        // Else record the new global point into history
        // Exclude epoch 0 (note: _epoch is always >= 1, see above)
        // Two possible outcomes:
        // Missing global checkpoints in prior weeks. In this case, _epoch = epoch + x, where x > 1
        // No missing global checkpoints, but timestamp != block.timestamp. Create new checkpoint.
        // No missing global checkpoints, but timestamp == block.timestamp. Overwrite last checkpoint.
        if (_epoch != 1 && _pointHistory[_epoch - 1].ts == block.timestamp) {
            // _epoch = epoch + 1, so we do not increment epoch
            _pointHistory[_epoch - 1] = lastPoint;
        } else {
            // more than one global point may have been written, so we update epoch
            epoch = _epoch;
            _pointHistory[_epoch] = lastPoint;
        }

        if (_tokenId != 0) {
            // Schedule the slope changes (slope is going down)
            // We subtract new_user_slope from [_newLocked.end]
            // and add old_user_slope to [_oldLocked.end]
            if (_oldLocked.end > block.timestamp) {
                // oldDslope was <something> - uOld.slope, so we cancel that
                oldDslope += uOld.slope;
                if (_newLocked.end == _oldLocked.end) {
                    oldDslope -= uNew.slope; // It was a new deposit, not extension
                }
                slopeChanges[_oldLocked.end] = oldDslope;
            }

            if (_newLocked.end > block.timestamp) {
                // update slope if new lock is greater than old lock and is not permanent or if old lock is permanent
                if ((_newLocked.end > _oldLocked.end)) {
                    newDslope -= uNew.slope; // old slope disappeared at this point
                    slopeChanges[_newLocked.end] = newDslope;
                }
                // else: we recorded it already in oldDslope
            }
            // If timestamp of last user point is the same, overwrite the last user point
            // Else record the new user point into history
            // Exclude epoch 0
            uNew.ts = block.timestamp;
            uNew.blk = block.number;
            uint256 userEpoch = userPointEpoch[_tokenId];
            if (userEpoch != 0 && _userPointHistory[_tokenId][userEpoch].ts == block.timestamp) {
                _userPointHistory[_tokenId][userEpoch] = uNew;
            } else {
                userPointEpoch[_tokenId] = ++userEpoch;
                _userPointHistory[_tokenId][userEpoch] = uNew;
            }
        }
    }

    function _increaseAmountFor(uint256 _tokenId, uint256 _value, DepositType _depositType) internal {
        LockedBalance memory oldLocked = _locked[_tokenId];

        if (_value == 0) revert ZeroAmount();
        if (oldLocked.amount <= 0) revert NoLockFound();
        if (oldLocked.end <= block.timestamp && !oldLocked.isPermanent) revert LockExpired();

        if (oldLocked.isPermanent) permanentLockBalance += _value;
        _depositFor(_tokenId, _value, 0, oldLocked, _depositType);

        emit MetadataUpdate(_tokenId);
    }

    /* ========== MODIFIERS ========== */

    modifier isTokenOwner(uint256 tokenId) {
        if (_ownerOf(tokenId) != _msgSender()) {
            revert NotTokenOwner(tokenId, _msgSender());
        }
        _;
    }
}