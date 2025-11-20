// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

/**
 * @title INFTPartnershipRegistry
 * @author Neverland
 * @notice Interface for managing NFT collection partnerships that provide point multipliers
 */
interface INFTPartnershipRegistry {
    /*//////////////////////////////////////////////////////////////
                               STRUCTS
    //////////////////////////////////////////////////////////////*/

    struct Partnership {
        address collection;
        bool active;
        uint256 startTimestamp;
        uint256 endTimestamp;
        string name;
    }

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Emitted when a new partnership is added
     * @param collection NFT collection address
     * @param name Display name of the collection
     * @param active Whether the partnership is active
     * @param startTimestamp When the boost becomes active
     * @param endTimestamp When the boost ends (0 = no end)
     * @param currentFirstBonus Current global first bonus at time of addition
     * @param currentDecayRatio Current global decay ratio at time of addition
     * @param totalPartnerships Total number of partnerships after this addition
     */
    event PartnershipAdded(
        address indexed collection,
        string name,
        bool active,
        uint256 startTimestamp,
        uint256 endTimestamp,
        uint256 currentFirstBonus,
        uint256 currentDecayRatio,
        uint256 totalPartnerships
    );

    /**
     * @notice Emitted when a partnership is updated
     * @param collection NFT collection address
     * @param name Display name of the collection
     * @param active Whether the partnership is active
     * @param startTimestamp When the boost becomes active
     * @param endTimestamp When the boost ends (0 = no end)
     */
    event PartnershipUpdated(
        address indexed collection, string name, bool active, uint256 startTimestamp, uint256 endTimestamp
    );

    /**
     * @notice Emitted when a partnership is removed
     * @param collection NFT collection address
     * @param name Display name of the removed collection
     * @param totalPartnerships Total number of partnerships after removal
     */
    event PartnershipRemoved(address indexed collection, string name, uint256 totalPartnerships);

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Thrown when a collection address is already registered
     * @param collection Collection address
     */
    error PartnershipAlreadyExists(address collection);

    /**
     * @notice Thrown when a partnership is not found
     * @param collection Collection address
     */
    error PartnershipNotFound(address collection);

    /**
     * @notice Emitted when global multiplier parameters are updated
     * @param oldFirstBonus Previous first bonus in basis points
     * @param newFirstBonus New first bonus in basis points
     * @param oldDecayRatio Previous decay ratio in basis points
     * @param newDecayRatio New decay ratio in basis points
     * @param timestamp Block timestamp of update
     * @param totalActivePartnerships Number of active partnerships at time of update
     */
    event MultiplierParamsUpdated(
        uint256 oldFirstBonus,
        uint256 newFirstBonus,
        uint256 oldDecayRatio,
        uint256 newDecayRatio,
        uint256 timestamp,
        uint256 totalActivePartnerships
    );

    /**
     * @notice Thrown when first bonus is out of valid range
     * @param firstBonus Invalid first bonus value
     */
    error InvalidFirstBonus(uint256 firstBonus);

    /**
     * @notice Thrown when decay ratio is out of valid range
     * @param decayRatio Invalid decay ratio value
     */
    error InvalidDecayRatio(uint256 decayRatio);

    /**
     * @notice Thrown when timestamps are invalid
     */
    error InvalidTimestamp();

    /*//////////////////////////////////////////////////////////////
                               ACTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Add a new NFT partnership
     * @param collection Address of the NFT collection
     * @param name Display name of the collection
     * @param startTimestamp When the boost becomes active
     * @param endTimestamp When the boost ends (0 = no end)
     */
    function addPartnership(address collection, string calldata name, uint256 startTimestamp, uint256 endTimestamp)
        external;

    /**
     * @notice Update an existing partnership
     * @param collection Address of the NFT collection
     * @param active Whether the partnership is active
     */
    function updatePartnership(address collection, bool active) external;

    /**
     * @notice Remove a partnership
     * @param collection Address of the NFT collection
     */
    function removePartnership(address collection) external;

    /**
     * @notice Update global multiplier parameters
     * @param newFirstBonus New first bonus in basis points (1000 = 0.1)
     * @param newDecayRatio New decay ratio in basis points (9000 = 0.9)
     */
    function setMultiplierParams(uint256 newFirstBonus, uint256 newDecayRatio) external;

    /*//////////////////////////////////////////////////////////////
                                 VIEWS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get all active partnerships
     * @return active Array of active partnership addresses
     */
    function getActivePartnerships() external view returns (address[] memory active);

    /**
     * @notice Get partnership details
     * @param collection Address of the NFT collection
     * @return partnership The partnership struct
     */
    function getPartnership(address collection) external view returns (Partnership memory partnership);

    /**
     * @notice Get total number of partnerships
     * @return count Total partnership count
     */
    function getPartnershipCount() external view returns (uint256 count);

    /**
     * @notice Get global first bonus parameter
     * @return First bonus in basis points
     */
    function firstBonus() external view returns (uint256);

    /**
     * @notice Get global decay ratio parameter
     * @return Decay ratio in basis points
     */
    function decayRatio() external view returns (uint256);
}
