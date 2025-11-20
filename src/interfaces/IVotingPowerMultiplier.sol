// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

/**
 * @title IVotingPowerMultiplier
 * @author Neverland
 * @notice Interface for configuring voting power (veNFT) based multipliers
 */
interface IVotingPowerMultiplier {
    /*//////////////////////////////////////////////////////////////
                               STRUCTS
    //////////////////////////////////////////////////////////////*/

    struct VotingPowerTier {
        uint256 minVotingPower; // Minimum voting power for this tier (18 decimals)
        uint256 multiplierBps; // Multiplier in basis points (11000 = 1.1x)
    }

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Emitted when a tier is added
     * @param tierIndex Index of the added tier
     * @param minVotingPower Minimum voting power for this tier
     * @param multiplierBps Multiplier in basis points
     * @param totalTiers Total number of tiers after addition
     */
    event TierAdded(uint256 indexed tierIndex, uint256 minVotingPower, uint256 multiplierBps, uint256 totalTiers);

    /**
     * @notice Emitted when a tier is updated
     * @param tierIndex Index of the updated tier
     * @param oldMinVotingPower Previous minimum voting power
     * @param newMinVotingPower New minimum voting power
     * @param oldMultiplierBps Previous multiplier
     * @param newMultiplierBps New multiplier
     */
    event TierUpdated(
        uint256 indexed tierIndex,
        uint256 oldMinVotingPower,
        uint256 newMinVotingPower,
        uint256 oldMultiplierBps,
        uint256 newMultiplierBps
    );

    /**
     * @notice Emitted when a tier is removed
     * @param tierIndex Index of the removed tier
     * @param totalTiers Total number of tiers after removal
     */
    event TierRemoved(uint256 indexed tierIndex, uint256 totalTiers);

    /**
     * @notice Emitted when DustLock address is updated
     * @param oldDustLock Previous DustLock address
     * @param newDustLock New DustLock address
     */
    event DustLockUpdated(address oldDustLock, address newDustLock);

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Thrown when multiplier exceeds maximum
     * @param multiplier Invalid multiplier value
     */
    error MultiplierTooHigh(uint256 multiplier);

    /**
     * @notice Thrown when tier index is invalid
     * @param tierIndex Invalid tier index
     */
    error InvalidTierIndex(uint256 tierIndex);

    /**
     * @notice Thrown when tiers are not in ascending order
     */
    error TiersNotAscending();

    /*//////////////////////////////////////////////////////////////
                               ACTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Add a new voting power tier
     * @param minVotingPower Minimum voting power for this tier (18 decimals)
     * @param multiplierBps Multiplier in basis points (11000 = 1.1x)
     */
    function addTier(uint256 minVotingPower, uint256 multiplierBps) external;

    /**
     * @notice Update an existing tier
     * @param tierIndex Index of the tier to update
     * @param minVotingPower New minimum voting power
     * @param multiplierBps New multiplier in basis points
     */
    function updateTier(uint256 tierIndex, uint256 minVotingPower, uint256 multiplierBps) external;

    /**
     * @notice Remove a tier
     * @param tierIndex Index of the tier to remove
     */
    function removeTier(uint256 tierIndex) external;

    /**
     * @notice Update the DustLock contract address
     * @param newDustLock New DustLock contract address
     */
    function setDustLock(address newDustLock) external;

    /*//////////////////////////////////////////////////////////////
                                 VIEWS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get multiplier for a specific voting power amount
     * @param votingPower The voting power to check (18 decimals)
     * @return multiplierBps The multiplier in basis points
     */
    function getMultiplierForVotingPower(uint256 votingPower) external view returns (uint256 multiplierBps);

    /**
     * @notice Get multiplier for a specific user's highest veNFT
     * @param user User address
     * @return multiplierBps The multiplier in basis points
     * @return votingPower The user's highest voting power
     * @return tokenId The tokenId with highest voting power (0 if none)
     */
    function getUserMultiplier(address user)
        external
        view
        returns (uint256 multiplierBps, uint256 votingPower, uint256 tokenId);

    /**
     * @notice Get all tiers
     * @return Array of all voting power tiers
     */
    function getAllTiers() external view returns (VotingPowerTier[] memory);

    /**
     * @notice Get tier count
     * @return Number of tiers
     */
    function getTierCount() external view returns (uint256);

    /**
     * @notice Get tier by index
     * @param tierIndex Index of the tier
     * @return Tier data
     */
    function getTier(uint256 tierIndex) external view returns (VotingPowerTier memory);
}
