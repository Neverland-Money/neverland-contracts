// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

interface IDustLock {
    enum DepositType {
        CREATE_LOCK_TYPE,
        INCREASE_LOCK_AMOUNT,
        INCREASE_UNLOCK_TIME
    }

    struct LockedBalance {
        int128 amount;
        uint256 end;
        bool isPermanent;
    }

    struct UserPoint {
        int128 bias;
        int128 slope; // # -dweight / dt
        uint256 ts;
        uint256 blk; // block
        uint256 permanent;
    }

    struct GlobalPoint {
        int128 bias;
        int128 slope; // # -dweight / dt
        uint256 ts;
        uint256 blk; // block
        uint256 permanentLockBalance;
    }

    /* ========== EXTERNAL VIEW FUNCTIONS ========== */

    /// @notice Total amount of erc20 token (DUST) deposited
    function supply() external view returns (uint256);

    /// @notice Total count of epochs witnessed since contract creation
    function epoch() external view returns (uint256);

    /// @notice Address of erc20 token (DUST) used to create a veNFT
    function token() external view returns (address);

    /// @notice time -> signed slope change
    function slopeChanges(uint256 _timestamp) external view returns (int128);

    /// @notice Returns the UserPoint for a tokenId and epoch
    /// @param _tokenId The tokenId
    /// @param _loc The epoch
    /// @return UserPoint The historical UserPoint token had at this epoch
    function userPointHistory(uint256 _tokenId, uint256 _loc) external view returns (UserPoint memory);

    /// @notice Aggregate permanent locked balances
    function permanentLockBalance() external view returns (uint256);

    /// @notice Get the LockedBalance (amount, end) of a _tokenId
    /// @param _tokenId .
    /// @return LockedBalance of _tokenId
    function locked(uint256 _tokenId) external view returns (LockedBalance memory);

    /// @notice Global point history at a given index
    function pointHistory(uint256 _loc) external view returns (GlobalPoint memory);

    /* ========== EXTERNAL MUTATIVE FUNCTIONS ========== */

    /// @notice Deposit `_value` tokens for `msg.sender` and lock for `_lockDuration`
    /// @param _value Amount to deposit
    /// @param _lockDuration Number of seconds to lock tokens for (rounded down to nearest week)
    /// @return TokenId of created veNFT
    function createLock(uint256 _value, uint256 _lockDuration) external returns (uint256);

    /* ========== ERRORS ========== */

    error ZeroAmount();
    error LockDurationNotInFuture();
    error LockDurationTooLong();

    /* ========== EVENTS ========== */

    event Deposit(
        address indexed provider,
        uint256 indexed tokenId,
        DepositType indexed depositType,
        uint256 value,
        uint256 locktime,
        uint256 ts
    );
    event Supply(uint256 prevSupply, uint256 supply);
}
