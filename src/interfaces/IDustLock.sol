// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IRevenueReward} from "./IRevenueReward.sol";
import {IERC165, IERC721} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import {IERC4906} from "@openzeppelin/contracts/interfaces/IERC4906.sol";
import {IERC6372} from "@openzeppelin/contracts/interfaces/IERC6372.sol";
import {IERC721Metadata} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";

/**
 * @title IDustLock Interface
 * @notice Interface for the DustLock contract that manages voting escrow NFTs (veNFTs)
 * @dev Combines ERC721 with vote-escrow functionality for governance and reward distribution
 */
interface IDustLock is IERC4906, IERC6372, IERC721Metadata {
    /**
     * @notice Structure representing a locked token position
     * @dev Used to track the amount of tokens locked, when they unlock, and if they're permanently locked
     * @param amount Amount of tokens locked in int128 format
     * @param end Timestamp when tokens unlock (0 for permanent locks)
     * @param isPermanent Whether this is a permanent lock that cannot be withdrawn normally
     */
    struct LockedBalance {
        int128 amount;
        uint256 end;
        bool isPermanent;
    }

    /**
     * @notice Checkpoint for tracking user voting power at a specific point in time
     * @dev Used in the vote-escrow system to track decay of voting power over time
     * @param bias Voting power at time ts
     * @param slope Rate of voting power decrease per second (-dweight/dt)
     * @param ts Timestamp of the checkpoint
     * @param blk Block number at which the checkpoint was created
     * @param permanent Amount of permanent (non-decaying) voting power
     */
    struct UserPoint {
        int128 bias;
        int128 slope; // # -dweight / dt
        uint256 ts;
        uint256 blk; // block
        uint256 permanent;
    }

    /**
     * @notice Global checkpoint for tracking total voting power at a specific point in time
     * @dev Similar to UserPoint but tracks system-wide totals
     * @param bias Total voting power at time ts
     * @param slope Total rate of voting power decrease per second (-dweight/dt)
     * @param ts Timestamp of the checkpoint
     * @param blk Block number at which the checkpoint was created
     * @param permanentLockBalance Total amount of permanently locked tokens
     */
    struct GlobalPoint {
        int128 bias;
        int128 slope; // # -dweight / dt
        uint256 ts;
        uint256 blk; // block
        uint256 permanentLockBalance;
    }

    /**
     * @notice Types of deposit operations supported by the veNFT system
     * @param DEPOSIT_FOR_TYPE Adding tokens to an existing lock owned by someone else
     * @param CREATE_LOCK_TYPE Creating a new lock position
     * @param INCREASE_LOCK_AMOUNT Adding more tokens to an existing lock
     * @param INCREASE_UNLOCK_TIME Extending the lock duration of an existing lock
     */
    enum DepositType {
        DEPOSIT_FOR_TYPE,
        CREATE_LOCK_TYPE,
        INCREASE_LOCK_AMOUNT,
        INCREASE_UNLOCK_TIME
    }

    /// @notice Error thrown when a user tries to vote multiple times in the same period
    error AlreadyVoted();
    /// @notice Error thrown when the requested amount exceeds available balance
    error AmountTooBig();
    /// @notice Error thrown when an ERC721 receiver contract rejects the tokens
    error ERC721ReceiverRejectedTokens();
    /// @notice Error thrown when transferring to an address that doesn't implement ERC721Receiver
    error ERC721TransferToNonERC721ReceiverImplementer();
    /// @notice Error thrown when a signature uses an invalid nonce
    error InvalidNonce();
    /// @notice Error thrown when a provided signature is invalid
    error InvalidSignature();
    /// @notice Error thrown when a signature's S value is invalid per EIP-2
    error InvalidSignatureS();
    /// @notice Error thrown when an early withdraw penalty value is invalid (>=10000)
    error InvalidWithdrawPenalty();
    /// @notice Error thrown when a zero address is provided where not allowed
    error InvalidAddress();
    /// @notice Error thrown when the lock duration doesn't extend beyond the current time
    error LockDurationNotInFuture();
    /// @notice Error thrown when the lock duration exceeds the maximum allowed time
    error LockDurationTooLong();
    /// @notice Error thrown when the lock duration is less than the minimum required time
    error LockDurationTooShort();
    /// @notice Error thrown when trying to perform an operation on an expired lock
    error LockExpired();
    /// @notice Error thrown when trying to withdraw from a lock that hasn't expired yet
    error LockNotExpired();
    /// @notice Error thrown when no lock is found for the specified token ID
    error NoLockFound();
    /// @notice Error thrown when attempting to operate on a token that doesn't exist
    error NonExistentToken();
    /// @notice Error thrown when the caller is neither the owner nor approved for the token
    error NotApprovedOrOwner();
    /// @notice Error thrown when a non-distributor address attempts a distributor action
    error NotDistributor();
    /// @notice Error thrown when a restricted function is called by someone other than the emergency council or governor
    error NotEmergencyCouncilOrGovernor();
    /// @notice Error thrown when a governor-only function is called by a non-governor address
    error NotGovernor();
    /// @notice Error thrown when trying to perform a locked NFT operation on a normal NFT
    error NotLockedNFT();
    /// @notice Error thrown when trying to perform a normal NFT operation on a locked NFT
    error NotNormalNFT();
    /// @notice Error thrown when trying to unlock a non-permanent lock using unlockPermanent
    error NotPermanentLock();
    /// @notice Error thrown when the caller is not the owner of the token
    error NotOwner();
    /// @notice Error thrown when a team-only function is called by a non-team address
    error NotTeam();
    /// @notice Error thrown when a voter-only function is called by a non-voter address
    error NotVoter();
    /// @notice Error thrown when ownership changes during an operation
    error OwnershipChange();
    /// @notice Error thrown when trying to withdraw or modify a permanent lock
    error PermanentLock();
    /// @notice Error thrown when source and destination addresses are the same
    error SameAddress();
    /// @notice Error thrown when attempting to merge a veNFT with itself
    error SameNFT();
    /// @notice Error thrown when attempting to change state to the same value
    error SameState();
    /// @notice Error thrown when trying to split a veNFT with no owner
    error SplitNoOwner();
    /// @notice Error thrown when splitting is not allowed for the user
    error SplitNotAllowed();
    /// @notice Error thrown when a signature has expired (beyond the deadline)
    error SignatureExpired();
    /// @notice Error thrown when too many token IDs are provided in a batch operation
    error TooManyTokenIDs();
    /// @notice Error thrown when a zero address is provided where not allowed
    error ZeroAddress();
    /// @notice Error thrown when a zero amount is provided where not allowed
    error ZeroAmount();
    /// @notice Error thrown when an operation requires a non-zero balance
    error ZeroBalance();

    /**
     * @notice Emitted when tokens are deposited into the veNFT system
     * @param provider Address depositing the tokens
     * @param tokenId ID of the veNFT being created or modified
     * @param depositType Type of deposit operation (create, increase amount, etc.)
     * @param value Amount of tokens deposited
     * @param locktime Timestamp when the lock expires
     * @param ts Timestamp when the deposit occurred
     */
    event Deposit(
        address indexed provider,
        uint256 indexed tokenId,
        DepositType indexed depositType,
        uint256 value,
        uint256 locktime,
        uint256 ts
    );
    /**
     * @notice Emitted when tokens are withdrawn before the lock expiry with a penalty
     * @param provider Address receiving the withdrawn tokens
     * @param tokenId ID of the veNFT being withdrawn
     * @param value Original locked amount
     * @param amountReturned Amount returned to the user after penalty
     * @param ts Timestamp when the early withdrawal occurred
     */
    event EarlyWithdraw(
        address indexed provider, uint256 indexed tokenId, uint256 value, uint256 amountReturned, uint256 ts
    );
    /**
     * @notice Emitted when tokens are withdrawn after the lock expiry
     * @param provider Address receiving the withdrawn tokens
     * @param tokenId ID of the veNFT being withdrawn
     * @param value Amount of tokens withdrawn
     * @param ts Timestamp when the withdrawal occurred
     */
    event Withdraw(address indexed provider, uint256 indexed tokenId, uint256 value, uint256 ts);
    /**
     * @notice Emitted when a lock is converted to a permanent lock
     * @param _owner Address that owns the veNFT
     * @param _tokenId ID of the veNFT being locked permanently
     * @param amount Amount of tokens in the lock
     * @param _ts Timestamp when the permanent lock was created
     */
    event LockPermanent(address indexed _owner, uint256 indexed _tokenId, uint256 amount, uint256 _ts);
    /**
     * @notice Emitted when a permanent lock is unlocked by governance
     * @param _owner Address that owns the veNFT
     * @param _tokenId ID of the veNFT being unlocked
     * @param amount Amount of tokens in the lock
     * @param _ts Timestamp when the permanent lock was unlocked
     */
    event UnlockPermanent(address indexed _owner, uint256 indexed _tokenId, uint256 amount, uint256 _ts);
    /**
     * @notice Emitted when the total supply of locked tokens changes
     * @param prevSupply Previous total locked supply
     * @param supply New total locked supply
     */
    event Supply(uint256 prevSupply, uint256 supply);
    /**
     * @notice Emitted when two veNFTs are merged
     * @param _sender Address initiating the merge
     * @param _from Source veNFT ID (burned in the process)
     * @param _to Destination veNFT ID (receives combined balance)
     * @param _amountFrom Amount of tokens in the source veNFT
     * @param _amountTo Amount of tokens in the destination veNFT before merge
     * @param _amountFinal Final amount of tokens in the destination veNFT after merge
     * @param _locktime New lock expiry time for the merged veNFT
     * @param _ts Timestamp when the merge occurred
     */
    event Merge(
        address indexed _sender,
        uint256 indexed _from,
        uint256 indexed _to,
        uint256 _amountFrom,
        uint256 _amountTo,
        uint256 _amountFinal,
        uint256 _locktime,
        uint256 _ts
    );
    /**
     * @notice Emitted when a veNFT is split into two separate veNFTs
     * @param _from Original veNFT ID being split (burned in the process)
     * @param _tokenId1 First new veNFT ID created from the split
     * @param _tokenId2 Second new veNFT ID created from the split
     * @param _sender Address initiating the split
     * @param _splitAmount1 Amount of tokens allocated to the first veNFT
     * @param _splitAmount2 Amount of tokens allocated to the second veNFT
     * @param _locktime Lock expiry time for both new veNFTs
     * @param _ts Timestamp when the split occurred
     */
    event Split(
        uint256 indexed _from,
        uint256 indexed _tokenId1,
        uint256 indexed _tokenId2,
        address _sender,
        uint256 _splitAmount1,
        uint256 _splitAmount2,
        uint256 _locktime,
        uint256 _ts
    );

    // State variables
    /// @notice Address of Meta-tx Forwarder
    function forwarder() external view returns (address);

    /// @notice Address of token (DUST) used to create a veNFT
    function token() external view returns (address);

    /**
     * @notice Address of Neverland Team multisig
     * @return The address of the current team multisig with administrative privileges
     */
    function team() external view returns (address);

    /**
     * @notice Current total count of veNFT tokens
     * @dev Used as a counter for minting new tokens and assigning IDs
     * @return The current highest token ID value
     */
    function tokenId() external view returns (uint256);

    /**
     * @notice Updates the team multisig address
     * @dev Can only be called by the current team address
     * @param _team New team multisig address to set
     */
    function setTeam(address _team) external;

    /*///////////////////////////////////////////////////////////////
                             METADATA STORAGE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the name of the token
     * @return The name of the veNFT token
     */
    function name() external view returns (string memory);

    /**
     * @notice Returns the symbol of the token
     * @return The symbol of the veNFT token
     */
    function symbol() external view returns (string memory);

    /**
     * @notice Returns the version of the contract
     * @return The current version string of the contract
     */
    function version() external view returns (string memory);

    /**
     * @notice Returns the number of decimals used for user representation
     * @return The number of decimals (typically 18)
     */
    function decimals() external view returns (uint8);

    /**
     * @notice Updates the base URI for computing tokenURI
     * @dev Can only be called by the team address
     * @param newBaseURI The new base URI to set for all tokens
     */
    function setBaseURI(string memory newBaseURI) external;

    /*//////////////////////////////////////////////////////////////
                      ERC721 BALANCE/OWNER STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @dev Mapping from owner address to mapping of index to tokenId
    function ownerToNFTokenIdList(address _owner, uint256 _index) external view returns (uint256 _tokenId);

    /// @inheritdoc IERC721
    function ownerOf(uint256 tokenId) external view returns (address owner);

    /// @inheritdoc IERC721
    function balanceOf(address owner) external view returns (uint256 balance);

    /*//////////////////////////////////////////////////////////////
                         ERC721 APPROVAL STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IERC721
    function getApproved(uint256 _tokenId) external view returns (address operator);

    /// @inheritdoc IERC721
    function isApprovedForAll(address owner, address operator) external view returns (bool);

    /**
     * @notice Check whether spender is owner or an approved user for a given veNFT
     * @param _spender The address to approve for the tokenId
     * @param _tokenId The ID of the veNFT to be approved
     */
    function isApprovedOrOwner(address _spender, uint256 _tokenId) external returns (bool);

    /*//////////////////////////////////////////////////////////////
                              ERC721 LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IERC721
    function approve(address to, uint256 tokenId) external;

    /// @inheritdoc IERC721
    function setApprovalForAll(address operator, bool approved) external;

    /// @inheritdoc IERC721
    function transferFrom(address from, address to, uint256 tokenId) external;

    /// @inheritdoc IERC721
    function safeTransferFrom(address from, address to, uint256 tokenId) external;

    /// @inheritdoc IERC721
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes calldata data) external;

    /*//////////////////////////////////////////////////////////////
                              ERC165 LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 _interfaceID) external view returns (bool);

    /*//////////////////////////////////////////////////////////////
                             ESCROW STORAGE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Total count of epochs witnessed since contract creation
     * @return The current epoch number
     */
    function epoch() external view returns (uint256);

    /**
     * @notice Total amount of tokens currently locked in the contract
     * @return The total supply of locked tokens (excluding permanently locked tokens)
     */
    function supply() external view returns (uint256);

    /**
     * @notice Aggregate balance of permanently locked tokens
     * @dev These tokens cannot be withdrawn through normal means
     * @return The total amount of permanently locked tokens
     */
    function permanentLockBalance() external view returns (uint256);

    /**
     * @notice Percentage of penalty applied to early withdrawals (in basis points)
     * @dev Value is between 0 and 10000 (0% to 100%)
     * @return The current penalty percentage in basis points
     */
    function earlyWithdrawPenalty() external view returns (uint256);

    /**
     * @notice Address that receives penalty fees from early withdrawals
     * @return The address of the treasury that collects early withdrawal penalties
     */
    function earlyWithdrawTreasury() external view returns (address);

    /**
     * @notice Get the current epoch number for a specific veNFT
     * @param _tokenId The ID of the veNFT to check
     * @return _epoch The current epoch number for the specified veNFT
     */
    function userPointEpoch(uint256 _tokenId) external view returns (uint256 _epoch);

    /**
     * @notice Retrieve the scheduled slope change at a given timestamp
     * @dev Used to calculate future voting power changes due to lock expirations
     * @param _timestamp The timestamp to check for slope changes
     * @return The net change in slope (negative value means decrease in voting power)
     */
    function slopeChanges(uint256 _timestamp) external view returns (int128);

    /**
     * @notice Check if an account has permission to split veNFTs
     * @dev Used to control which addresses can perform veNFT splitting operations
     * @param _account The address to check for split permission
     * @return True if the account can split veNFTs, false otherwise
     */
    function canSplit(address _account) external view returns (bool);

    /**
     * @notice Retrieve a global checkpoint at a specific index
     * @dev Used to track historical voting power across all tokens at different points in time
     * @param _loc The index of the checkpoint to retrieve
     * @return The GlobalPoint data at the specified index
     */
    function pointHistory(uint256 _loc) external view returns (GlobalPoint memory);

    /**
     * @notice Get the lock details for a specific veNFT
     * @dev Returns information about lock amount, end time, and permanent status
     * @param _tokenId The ID of the veNFT to query
     * @return The LockedBalance struct containing lock information
     */
    function locked(uint256 _tokenId) external view returns (LockedBalance memory);

    /**
     * @notice Retrieve a user checkpoint for a specific veNFT at a given index
     * @dev Used to track historical voting power for individual tokens
     * @param _tokenId The ID of the veNFT to query
     * @param _loc The index of the user checkpoint to retrieve
     * @return The UserPoint data at the specified index for the given token
     */
    function userPointHistory(uint256 _tokenId, uint256 _loc) external view returns (UserPoint memory);

    /*//////////////////////////////////////////////////////////////
                              ESCROW LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Create a global checkpoint to record the current state of voting power
     * @dev Updates the global point history with current voting power data
     *      This is called automatically by most state-changing functions
     *      but can be called manually to ensure up-to-date on-chain data
     */
    function checkpoint() external;

    /**
     * @notice Deposit additional tokens for an existing veNFT lock
     * @dev Anyone (even a smart contract) can deposit tokens for someone else's lock
     *      The deposit increases the lock amount but does not extend the lock time
     *      Cannot be used for locks that have already expired
     * @param _tokenId The ID of the veNFT to deposit for
     * @param _value Amount of tokens to add to the existing lock
     */
    function depositFor(uint256 _tokenId, uint256 _value) external;

    /**
     * @notice Create a new lock by depositing tokens for the caller
     * @dev Creates a new veNFT representing the locked tokens
     *      Lock duration is rounded down to the nearest week
     * @param _value Amount of tokens to deposit and lock
     * @param _lockDuration Number of seconds to lock tokens for (rounded down to nearest week)
     * @return The ID of the newly created veNFT
     */
    function createLock(uint256 _value, uint256 _lockDuration) external returns (uint256);

    /**
     * @notice Create a new lock by depositing tokens for another address
     * @dev Creates a new veNFT representing the locked tokens and assigns it to the specified recipient
     *      This is useful for protocols that want to create locks on behalf of their users
     *      Lock duration is rounded down to the nearest week
     * @param _value Amount of tokens to deposit and lock
     * @param _lockDuration Number of seconds to lock tokens for (rounded down to nearest week)
     * @param _to The address that will own the newly created veNFT
     * @return The ID of the newly created veNFT
     */
    function createLockFor(uint256 _value, uint256 _lockDuration, address _to) external returns (uint256);

    /**
     * @notice Deposit additional tokens for an existing veNFT without modifying the unlock time
     * @dev Increases the amount of tokens in a lock while keeping the same unlock date
     *      Can only be called by the owner of the veNFT or an approved address
     * @param _tokenId The ID of the veNFT to increase the amount for
     * @param _value Additional amount of tokens to add to the lock
     */
    function increaseAmount(uint256 _tokenId, uint256 _value) external;

    /**
     * @notice Extend the unlock time for an existing veNFT lock
     * @dev Increases the lock duration without changing the token amount
     *      Cannot extend lock time of permanent locks
     *      New lock time is rounded down to the nearest week
     *      Can only be called by the owner of the veNFT or an approved address
     * @param _tokenId The ID of the veNFT to extend the lock duration for
     * @param _lockDuration New number of seconds until tokens unlock (from current time)
     */
    function increaseUnlockTime(uint256 _tokenId, uint256 _lockDuration) external;

    /**
     * @notice Withdraw all tokens from an expired lock for `_tokenId`
     * @dev Only possible if the lock has expired and is not a permanent lock
     *      This function burns the veNFT and returns the locked tokens to the owner
     *      IMPORTANT: Any unclaimed rebases or rewards will no longer be claimable after calling this
     *      Users should claim all rebases and rewards prior to withdrawing
     *      Can only be called by the owner of the veNFT or an approved address
     * @param _tokenId The ID of the veNFT to withdraw tokens from
     */
    function withdraw(uint256 _tokenId) external;

    /**
     * @notice Withdraw tokens from a lock before it expires, with a time-proportional penalty
     * @dev Allows users to exit a lock early but with a penalty fee applied
     *      The penalty is proportional to both earlyWithdrawPenalty and remaining time until unlock
     *      Penalty fees are sent to the earlyWithdrawTreasury address
     *      This function burns the veNFT and returns the non-penalized portion of tokens to the owner
     *      Cannot be used on permanent locks
     *      Can only be called by the owner of the veNFT or an approved address
     * @param _tokenId The ID of the veNFT to withdraw early from
     */
    function earlyWithdraw(uint256 _tokenId) external;

    /**
     * @notice Sets the early withdrawal penalty percentage
     * @dev Can only be called by the team address
     *      Value is in basis points (0-10000), where 10000 = 100%
     * @param _earlyWithdrawPenalty The new penalty percentage in basis points
     */
    function setEarlyWithdrawPenalty(uint256 _earlyWithdrawPenalty) external;

    /**
     * @notice Sets the treasury address that will receive penalty fees from early withdrawals
     * @dev Can only be called by the team address
     *      The treasury address receives the penalty portion of tokens from early withdrawals
     * @param _account The address of the new treasury that will receive penalty fees
     */
    function setEarlyWithdrawTreasury(address _account) external;

    /**
     * @notice Merges two veNFTs by combining their locked tokens into a single veNFT
     * @dev The source veNFT is burned and its tokens are added to the destination veNFT
     *      The lock duration of the destination veNFT is preserved
     *      Cannot merge source veNFTs that are permanent or have voted in the current epoch
     *      Cannot merge into destination veNFTs that have already expired
     *      Can only be called by an address that owns or is approved for both veNFTs
     * @param _from The ID of the source veNFT to merge from (will be burned)
     * @param _to The ID of the destination veNFT to merge into (will receive the combined tokens)
     */
    function merge(uint256 _from, uint256 _to) external;

    /**
     * @notice Splits a veNFT into two new veNFTs with divided token balances
     * @dev This operation burns the original veNFT and creates two new ones
     *      Both new veNFTs maintain the same lock end time as the original
     *      Can only be called by an address that has split permission, and owns or is approved for the veNFT
     *      If called by an approved address, that address will NOT have approval on the new veNFTs
     *      Requires that the caller is either the owner or specifically has been granted split permission
     *      Cannot split permanent locks or locks that have already voted in the current epoch
     * @param _from The ID of the veNFT to split (will be burned)
     * @param _amount The precise token amount to allocate to the second new veNFT
     * @return _tokenId1 ID of the first new veNFT with (original amount - _amount) tokens
     * @return _tokenId2 ID of the second new veNFT with exactly _amount tokens
     */
    function split(uint256 _from, uint256 _amount) external returns (uint256 _tokenId1, uint256 _tokenId2);

    /**
     * @notice Grant or revoke permission for an address to split veNFTs
     * @dev Can only be called by the team address
     *      Setting permissions for address(0) acts as a global switch for all addresses
     *      If address(0) is set to false, no address can split regardless of individual permissions
     *      If address(0) is set to true, individual permissions apply normally
     * @param _account The address to modify split permissions for, or address(0) for global setting
     * @param _bool True to grant permission, false to revoke permission
     */
    function toggleSplit(address _account, bool _bool) external;

    /**
     * @notice Permanently lock a veNFT to give it non-decaying voting power
     * @dev Converts a standard time-locked veNFT to a permanent lock
     *      Once permanent, the veNFT cannot be withdrawn normally (even after the original lock time)
     *      Permanent locks have constant voting power equal to the locked token amount with no time decay
     *      Can only be called by the owner of the veNFT or an approved address
     *      Cannot be called on a lock that is already permanent
     * @param _tokenId The ID of the veNFT to permanently lock
     */
    function lockPermanent(uint256 _tokenId) external;

    /**
     * @notice Revert a veNFT from permanent lock status back to a standard time-lock
     * @dev Converts a permanent lock back to a standard time-based lock
     *      After unlocking, the veNFT's voting power will decay based on the remaining lock time
     *      The lock time will be the original lock end time from before it was made permanent
     *      If the original lock time has already passed, the lock will be immediately withdrawable
     *      Can only be called by authorized addresses (typically controlled by governance)
     *      Only callable on veNFTs that are currently permanently locked
     * @param _tokenId The ID of the veNFT to revert from permanent to standard lock
     */
    function unlockPermanent(uint256 _tokenId) external;

    /*///////////////////////////////////////////////////////////////
                           VOTING POWER STORAGE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get the current voting power for a specific veNFT
     * @dev Calculates voting power based on lock amount, remaining time, and permanent status
     *      For standard locks: voting power = amount * (time_left / MAXTIME)
     *      For permanent locks: voting power = amount (no time decay)
     *      Returns 0 if called in the same block as a transfer due to checkpoint timing
     *      This is the core function used for governance voting power determination
     * @param _tokenId The ID of the veNFT to query voting power for
     * @return The current voting power of the specified veNFT
     */
    function balanceOfNFT(uint256 _tokenId) external view returns (uint256);

    /**
     * @notice Get the historical voting power for a veNFT at a specific timestamp
     * @dev Uses checkpoints to determine voting power at any point in the past
     *      Crucial for governance systems that need to determine past voting power
     *      For timestamps between checkpoints, calculates the interpolated value
     *      Returns 0 for timestamps before the veNFT was created
     * @param _tokenId The ID of the veNFT to query historical voting power for
     * @param _t The timestamp at which to query the voting power
     * @return The voting power of the specified veNFT at the requested timestamp
     */
    function balanceOfNFTAt(uint256 _tokenId, uint256 _t) external view returns (uint256);

    /**
     * @notice Calculate the total voting power across all veNFTs at the current timestamp
     * @dev Sums up all individual veNFT voting powers including both time-based and permanent locks
     *      This represents the total governance voting power in the system right now
     * @return The aggregate voting power of all veNFTs at the current timestamp
     */
    function totalSupply() external view returns (uint256);

    /**
     * @notice Calculate the total historical voting power across all veNFTs at a specific timestamp
     * @dev Uses global checkpoints to determine total voting power at any point in the past
     *      Critical for governance votes that need to determine the total voting power at a past block
     *      For timestamps between checkpoints, calculates the interpolated value
     * @param _t The timestamp at which to query the total voting power
     * @return The aggregate voting power of all veNFTs at the requested timestamp
     */
    function totalSupplyAt(uint256 _t) external view returns (uint256);

    /*//////////////////////////////////////////////////////////////
                              ERC6372 LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IERC6372
    function clock() external view returns (uint48);

    /// @inheritdoc IERC6372
    function CLOCK_MODE() external view returns (string memory);

    /*//////////////////////////////////////////////////////////////
                      NOTIFY CONTRACTS
    //////////////////////////////////////////////////////////////*/

    function revenueReward() external returns (IRevenueReward);

    function setRevenueReward(IRevenueReward _revenueReward) external;
}
