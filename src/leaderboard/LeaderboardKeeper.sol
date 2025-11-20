// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import {CommonChecksLibrary} from "../libraries/CommonChecksLibrary.sol";
import {ILeaderboardKeeper} from "../interfaces/ILeaderboardKeeper.sol";

interface IDustLock {
    function balanceOfNFT(uint256 tokenId) external view returns (uint256);

    function balanceOf(address owner) external view returns (uint256);

    function ownerToNFTokenIdList(address owner, uint256 index) external view returns (uint256);
}

interface INFTPartnershipRegistry {
    function getActivePartnerships() external view returns (address[] memory);
}

/**
 * @title LeaderboardKeeper
 * @author Neverland
 * @notice Handles automated user state verification and settlement
 * @dev Keeper bot submits verified on-chain state, triggers subgraph updates
 */
contract LeaderboardKeeper is ILeaderboardKeeper, Ownable {
    /*//////////////////////////////////////////////////////////////
                                         CONSTANTS
                //////////////////////////////////////////////////////////////*/

    /// @notice Maximum batch size for state corrections (gas limit protection)
    uint256 public constant MAX_CORRECTION_BATCH = 100;

    /// @notice Maximum batch size for accurate settlements (gas limit protection)
    uint256 public constant MAX_SETTLEMENT_BATCH = 200;

    /*//////////////////////////////////////////////////////////////
                                      STORAGE VARIABLES
                //////////////////////////////////////////////////////////////*/

    /// @notice Address authorized to submit state verifications
    address public keeper;

    /// @notice Minimum time between settlements for a user (prevents spam)
    uint256 public minSettlementInterval;

    /// @notice Last settlement timestamp for each user
    mapping(address => uint256) public lastSettlement;

    /// @notice DustLock contract for voting power
    IDustLock public immutable dustLock;

    /// @notice NFT Partnership Registry for partner collections
    INFTPartnershipRegistry public immutable nftRegistry;

    /// @notice Minimum time between self-syncs (default 1 hour)
    uint256 public selfSyncCooldown;

    /*//////////////////////////////////////////////////////////////
                                        CONSTRUCTOR
                //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initialize keeper contract
     * @param initialOwner Initial owner for Ownable
     * @param initialKeeper Initial keeper address
     * @param initialInterval Initial minimum settlement interval (3600 = 1 hour)
     * @param _dustLock DustLock contract address
     * @param _nftRegistry NFT Partnership Registry address
     */
    constructor(
        address initialOwner,
        address initialKeeper,
        uint256 initialInterval,
        address _dustLock,
        address _nftRegistry
    ) {
        _transferOwnership(initialOwner);
        CommonChecksLibrary.revertIfZeroAddress(initialOwner);
        CommonChecksLibrary.revertIfZeroAddress(initialKeeper);
        CommonChecksLibrary.revertIfZeroAddress(_dustLock);
        CommonChecksLibrary.revertIfZeroAddress(_nftRegistry);

        keeper = initialKeeper;
        minSettlementInterval = initialInterval;
        selfSyncCooldown = 1 hours; // Default 1 hour cooldown
        dustLock = IDustLock(_dustLock);
        nftRegistry = INFTPartnershipRegistry(_nftRegistry);

        emit KeeperUpdated(address(0), initialKeeper);
        emit MinSettlementIntervalUpdated(0, initialInterval);
    }

    /*//////////////////////////////////////////////////////////////
                                           MODIFIERS
                //////////////////////////////////////////////////////////////*/

    /// @dev Restrict access to keeper or owner
    modifier onlyKeeper() {
        if (msg.sender != keeper && msg.sender != owner()) {
            revert NotKeeper(msg.sender);
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                                           ACTIONS
                //////////////////////////////////////////////////////////////*/

    /// @inheritdoc ILeaderboardKeeper
    function batchSyncCollectionBalances(
        address[] calldata users,
        address[] calldata collections,
        uint256[] calldata balances
    ) external onlyKeeper {
        uint256 usersLength = users.length;
        uint256 collectionsLength = collections.length;
        uint256 expectedBalancesLength = usersLength * collectionsLength;

        if (balances.length != expectedBalancesLength) {
            revert ArrayLengthMismatch(balances.length, expectedBalancesLength);
        }

        for (uint256 i = 0; i < usersLength;) {
            address user = users[i];

            for (uint256 j = 0; j < collectionsLength;) {
                address collection = collections[j];
                uint256 balance = balances[i * collectionsLength + j];

                // Emit per-collection balance for subgraph to initialize UserNFTOwnership
                emit CollectionBalanceVerified(user, collection, balance, block.timestamp);

                unchecked {
                    ++j;
                }
            }

            unchecked {
                ++i;
            }
        }
    }

    /// @inheritdoc ILeaderboardKeeper
    function batchVerifyAndSettle(address[] calldata users, UserState[] calldata states) external onlyKeeper {
        uint256 usersLength = users.length;
        uint256 statesLength = states.length;

        if (usersLength != statesLength) {
            revert ArrayLengthMismatch(usersLength, statesLength);
        }
        if (usersLength > MAX_CORRECTION_BATCH) {
            revert BatchTooLarge(usersLength, MAX_CORRECTION_BATCH);
        }

        uint256 correctionCount = 0;

        for (uint256 i = 0; i < usersLength;) {
            address user = users[i];
            UserState memory state = states[i];

            // Emit state verification (subgraph will override its cache)
            emit StateVerified(
                user, state.votingPower, state.nftCollectionCount, block.timestamp, "Keeper verification"
            );

            // Emit settlement trigger
            emit UserSettled(user, block.timestamp, true);

            // Update last settlement time
            lastSettlement[user] = block.timestamp;

            unchecked {
                ++correctionCount;
                ++i;
            }
        }

        emit BatchSettlementComplete(usersLength, correctionCount, block.timestamp);
    }

    /// @inheritdoc ILeaderboardKeeper
    function batchSettleAccurate(address[] calldata users) external onlyKeeper {
        uint256 usersLength = users.length;

        if (usersLength > MAX_SETTLEMENT_BATCH) {
            revert BatchTooLarge(usersLength, MAX_SETTLEMENT_BATCH);
        }

        for (uint256 i = 0; i < usersLength;) {
            address user = users[i];

            // Skip if recently settled
            if (block.timestamp < lastSettlement[user] + minSettlementInterval) {
                unchecked {
                    ++i;
                }
                continue;
            }

            // Just trigger settlement, no state override
            emit UserSettled(user, block.timestamp, false);

            // Update last settlement time
            lastSettlement[user] = block.timestamp;

            unchecked {
                ++i;
            }
        }

        emit BatchSettlementComplete(usersLength, 0, block.timestamp);
    }

    /// @inheritdoc ILeaderboardKeeper
    function emergencySettle(address user) external onlyOwner {
        CommonChecksLibrary.revertIfZeroAddress(user);

        emit UserSettled(user, block.timestamp, false);
        lastSettlement[user] = block.timestamp;
    }

    /// @inheritdoc ILeaderboardKeeper
    function syncMyState() external {
        address user = msg.sender;

        // Check cooldown
        uint256 lastSync = lastSettlement[user];
        if (block.timestamp < lastSync + selfSyncCooldown) {
            revert SettlementTooSoon(user, block.timestamp - lastSync, selfSyncCooldown);
        }

        // Read voting power from DustLock
        uint256 totalVotingPower = 0;
        uint256 veNFTCount = dustLock.balanceOf(user);
        for (uint256 i = 0; i < veNFTCount; i++) {
            uint256 tokenId = dustLock.ownerToNFTokenIdList(user, i);
            totalVotingPower += dustLock.balanceOfNFT(tokenId);
        }

        // Read NFT balances from partner collections
        address[] memory collections = nftRegistry.getActivePartnerships();
        uint256 collectionCount = 0;

        for (uint256 i = 0; i < collections.length; i++) {
            address collection = collections[i];
            uint256 balance = IERC721(collection).balanceOf(user);

            // Emit per-collection balance
            emit CollectionBalanceVerified(user, collection, balance, block.timestamp);

            if (balance > 0) {
                collectionCount++;
            }
        }

        // Emit state verification
        emit StateVerified(user, totalVotingPower, collectionCount, block.timestamp, "User self-sync");

        // Emit settlement trigger
        emit UserSettled(user, block.timestamp, true);

        // Update last settlement time
        lastSettlement[user] = block.timestamp;
    }

    /*//////////////////////////////////////////////////////////////
                                     ADMIN FUNCTIONS
              //////////////////////////////////////////////////////////////*/

    /// @inheritdoc ILeaderboardKeeper
    function setKeeper(address newKeeper) external onlyOwner {
        CommonChecksLibrary.revertIfZeroAddress(newKeeper);

        address oldKeeper = keeper;
        keeper = newKeeper;

        emit KeeperUpdated(oldKeeper, newKeeper);
    }

    /// @inheritdoc ILeaderboardKeeper
    function setMinSettlementInterval(uint256 newInterval) external onlyOwner {
        uint256 oldInterval = minSettlementInterval;
        minSettlementInterval = newInterval;

        emit MinSettlementIntervalUpdated(oldInterval, newInterval);
    }

    /// @inheritdoc ILeaderboardKeeper
    function setSelfSyncCooldown(uint256 newCooldown) external onlyOwner {
        uint256 oldCooldown = selfSyncCooldown;
        selfSyncCooldown = newCooldown;

        emit SelfSyncCooldownUpdated(oldCooldown, newCooldown);
    }

    /// @notice Disabled to prevent accidental renouncement of ownership
    function renounceOwnership() public view override onlyOwner {
        revert();
    }
}
