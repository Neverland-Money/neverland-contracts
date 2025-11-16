// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

/**
 * @title ILeaderboardKeeper
 * @author Neverland
 * @notice Interface for automated user state verification and settlement
 */
interface ILeaderboardKeeper {
    /*//////////////////////////////////////////////////////////////
                                        STRUCTS
            //////////////////////////////////////////////////////////////*/

    /**
     * @notice Verified on-chain state for a user
     * @param votingPower Total voting power from all veNFTs
     * @param nftCollectionCount Number of partner NFT collections owned
     * @param timestamp Timestamp when state was verified
     */
    struct UserState {
        uint256 votingPower;
        uint256 nftCollectionCount;
        uint256 timestamp;
    }

    /**
     * @notice Partner NFT collection info
     * @param collection NFT contract address
     * @param active Whether partnership is currently active
     */
    struct PartnerCollection {
        address collection;
        bool active;
    }

    /*//////////////////////////////////////////////////////////////
                                        EVENTS
            //////////////////////////////////////////////////////////////*/

    /**
     * @notice Emitted when keeper submits verified on-chain state
     * @param user User address
     * @param votingPower Verified voting power
     * @param nftCollectionCount Verified NFT collection count
     * @param timestamp Block timestamp
     * @param reason Description of verification
     */
    event StateVerified(
        address indexed user, uint256 votingPower, uint256 nftCollectionCount, uint256 timestamp, string reason
    );

    /**
     * @notice Emitted when keeper verifies per-collection NFT balance
     * @param user User address
     * @param collection NFT collection address
     * @param balance Number of NFTs from this collection
     * @param timestamp Block timestamp
     */
    event CollectionBalanceVerified(
        address indexed user, address indexed collection, uint256 balance, uint256 timestamp
    );

    /**
     * @notice Emitted to trigger point settlement for a user
     * @param user User address
     * @param timestamp Block timestamp
     * @param hadStateCorrection Whether state was corrected
     */
    event UserSettled(address indexed user, uint256 timestamp, bool hadStateCorrection);

    /**
     * @notice Emitted when batch settlement completes
     * @param userCount Number of users processed
     * @param correctionCount Number of state corrections
     * @param timestamp Block timestamp
     */
    event BatchSettlementComplete(uint256 userCount, uint256 correctionCount, uint256 timestamp);

    /**
     * @notice Emitted when keeper address changes
     * @param oldKeeper Previous keeper address
     * @param newKeeper New keeper address
     */
    event KeeperUpdated(address indexed oldKeeper, address indexed newKeeper);

    /**
     * @notice Emitted when minimum settlement interval changes
     * @param oldInterval Previous interval in seconds
     * @param newInterval New interval in seconds
     */
    event MinSettlementIntervalUpdated(uint256 oldInterval, uint256 newInterval);

    /**
     * @notice Emitted when self-sync cooldown changes
     * @param oldCooldown Previous cooldown in seconds
     * @param newCooldown New cooldown in seconds
     */
    event SelfSyncCooldownUpdated(uint256 oldCooldown, uint256 newCooldown);

    /*//////////////////////////////////////////////////////////////
                                        ERRORS
            //////////////////////////////////////////////////////////////*/

    /**
     * @notice Thrown when arrays have mismatched lengths
     * @param usersLength Length of users array
     * @param statesLength Length of states array
     */
    error ArrayLengthMismatch(uint256 usersLength, uint256 statesLength);

    /**
     * @notice Thrown when batch size exceeds maximum
     * @param batchSize Attempted batch size
     * @param maxBatchSize Maximum allowed batch size
     */
    error BatchTooLarge(uint256 batchSize, uint256 maxBatchSize);

    /**
     * @notice Thrown when caller is not keeper or owner
     * @param caller Address of caller
     */
    error NotKeeper(address caller);

    /**
     * @notice Thrown when trying to settle user too soon
     * @param user User address
     * @param timeSinceLastSettlement Time since last settlement
     * @param minInterval Required minimum interval
     */
    error SettlementTooSoon(address user, uint256 timeSinceLastSettlement, uint256 minInterval);

    /*//////////////////////////////////////////////////////////////
                                       ACTIONS
            //////////////////////////////////////////////////////////////*/

    /**
     * @notice Submit verified state for users with discrepancies
     * @param users Array of user addresses
     * @param states Array of verified states
     */
    function batchVerifyAndSettle(address[] calldata users, UserState[] calldata states) external;

    /**
     * @notice Sync per-collection NFT balances for users
     * @param users Array of user addresses
     * @param collections Array of NFT collection addresses
     * @param balances Array of balances (indexed as [userIndex * collectionsLength + collectionIndex])
     * @dev Call before batchVerifyAndSettle to initialize UserNFTOwnership balances
     */
    function batchSyncCollectionBalances(
        address[] calldata users,
        address[] calldata collections,
        uint256[] calldata balances
    ) external;

    /**
     * @notice Settle users whose state is already accurate
     * @param users Array of user addresses to settle
     */
    function batchSettleAccurate(address[] calldata users) external;

    /**
     * @notice Emergency function to settle a single user
     * @param user User address to settle
     */
    function emergencySettle(address user) external;

    /**
     * @notice User-callable function to sync their own state
     * @dev Reads on-chain state (VP, NFT balances) and emits verification events
     * @dev Subject to cooldown to prevent spam
     */
    function syncMyState() external;

    /**
     * @notice Update keeper address
     * @param newKeeper New keeper address
     */
    function setKeeper(address newKeeper) external;

    /**
     * @notice Update minimum settlement interval
     * @param newInterval New interval in seconds
     */
    function setMinSettlementInterval(uint256 newInterval) external;

    /**
     * @notice Update self-sync cooldown
     * @param newCooldown New cooldown in seconds
     */
    function setSelfSyncCooldown(uint256 newCooldown) external;

    /*//////////////////////////////////////////////////////////////
                                         VIEWS
            //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get keeper address
     * @return Keeper address
     */
    function keeper() external view returns (address);

    /**
     * @notice Get minimum settlement interval
     * @return Minimum interval in seconds
     */
    function minSettlementInterval() external view returns (uint256);

    /**
     * @notice Get last settlement timestamp for a user
     * @param user User address
     * @return Last settlement timestamp
     */
    function lastSettlement(address user) external view returns (uint256);

    /**
     * @notice Get maximum batch size for corrections
     * @return Maximum batch size
     */
    function MAX_CORRECTION_BATCH() external view returns (uint256);

    /**
     * @notice Get maximum batch size for settlements
     * @return Maximum batch size
     */
    function MAX_SETTLEMENT_BATCH() external view returns (uint256);
}
