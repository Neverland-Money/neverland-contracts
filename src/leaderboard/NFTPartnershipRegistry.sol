// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {CommonChecksLibrary} from "../libraries/CommonChecksLibrary.sol";
import {INFTPartnershipRegistry} from "../interfaces/INFTPartnershipRegistry.sol";

/**
 * @title NFTPartnershipRegistry
 * @author Neverland
 * @notice Registry for NFT collections that provide point multipliers
 * @dev Emits events that the subgraph listens to for tracking NFT boosts
 */
contract NFTPartnershipRegistry is INFTPartnershipRegistry, Ownable {
    /*//////////////////////////////////////////////////////////////
                             CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Minimum first bonus (0%)
    uint256 public constant MIN_FIRST_BONUS = 0;

    /// @notice Maximum first bonus (100% = 1.0)
    uint256 public constant MAX_FIRST_BONUS = 10_000;

    /// @notice Minimum decay ratio (0%)
    uint256 public constant MIN_DECAY_RATIO = 0;

    /// @notice Maximum decay ratio (99.99% to avoid division by zero)
    uint256 public constant MAX_DECAY_RATIO = 9_999;

    /*//////////////////////////////////////////////////////////////
                          STORAGE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Global first bonus in basis points (e.g., 1000 = 0.1)
    uint256 public firstBonus;

    /// @notice Global decay ratio in basis points (e.g., 9000 = 0.9)
    uint256 public decayRatio;

    /// @notice All registered partnerships by collection address
    mapping(address => Partnership) private partnerships;

    /// @notice Array of all partnership addresses for iteration
    address[] public allPartnerships;

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initialize the registry
     * @param _initialOwner Initial owner for Ownable
     * @param _firstBonus Initial first bonus in basis points (1000 = 0.1)
     * @param _decayRatio Initial decay ratio in basis points (9000 = 0.9)
     */
    constructor(address _initialOwner, uint256 _firstBonus, uint256 _decayRatio) {
        _transferOwnership(_initialOwner);
        CommonChecksLibrary.revertIfZeroAddress(_initialOwner);

        if (_firstBonus < MIN_FIRST_BONUS || _firstBonus > MAX_FIRST_BONUS) {
            revert InvalidFirstBonus(_firstBonus);
        }
        if (_decayRatio < MIN_DECAY_RATIO || _decayRatio > MAX_DECAY_RATIO) {
            revert InvalidDecayRatio(_decayRatio);
        }

        firstBonus = _firstBonus;
        decayRatio = _decayRatio;

        emit MultiplierParamsUpdated(0, _firstBonus, 0, _decayRatio, block.timestamp, 0);
    }

    /*//////////////////////////////////////////////////////////////
                               ACTIONS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc INFTPartnershipRegistry
    function addPartnership(address collection, string calldata name, uint256 startTimestamp, uint256 endTimestamp)
        external
        onlyOwner
    {
        CommonChecksLibrary.revertIfZeroAddress(collection);

        if (partnerships[collection].collection != address(0)) {
            revert PartnershipAlreadyExists(collection);
        }
        if (startTimestamp == 0 || (endTimestamp != 0 && endTimestamp <= startTimestamp)) {
            revert InvalidTimestamp();
        }

        partnerships[collection] = Partnership({
            collection: collection, active: true, startTimestamp: startTimestamp, endTimestamp: endTimestamp, name: name
        });

        allPartnerships.push(collection);

        emit PartnershipAdded(
            collection, name, true, startTimestamp, endTimestamp, firstBonus, decayRatio, allPartnerships.length
        );
    }

    /// @inheritdoc INFTPartnershipRegistry
    function updatePartnership(address collection, bool active) external onlyOwner {
        if (partnerships[collection].collection == address(0)) {
            revert PartnershipNotFound(collection);
        }

        Partnership memory p = partnerships[collection];
        partnerships[collection].active = active;

        emit PartnershipUpdated(collection, p.name, active, p.startTimestamp, p.endTimestamp);
    }

    /// @inheritdoc INFTPartnershipRegistry
    function removePartnership(address collection) external onlyOwner {
        if (partnerships[collection].collection == address(0)) {
            revert PartnershipNotFound(collection);
        }

        string memory partnershipName = partnerships[collection].name;
        delete partnerships[collection];

        // Remove from array
        uint256 len = allPartnerships.length;
        for (uint256 i = 0; i < len; ++i) {
            if (allPartnerships[i] == collection) {
                allPartnerships[i] = allPartnerships[allPartnerships.length - 1];
                allPartnerships.pop();
                break;
            }
        }

        emit PartnershipRemoved(collection, partnershipName, allPartnerships.length);
    }

    /// @inheritdoc INFTPartnershipRegistry
    function setMultiplierParams(uint256 newFirstBonus, uint256 newDecayRatio) external onlyOwner {
        if (newFirstBonus < MIN_FIRST_BONUS || newFirstBonus > MAX_FIRST_BONUS) {
            revert InvalidFirstBonus(newFirstBonus);
        }
        if (newDecayRatio < MIN_DECAY_RATIO || newDecayRatio > MAX_DECAY_RATIO) {
            revert InvalidDecayRatio(newDecayRatio);
        }

        uint256 oldFirstBonus = firstBonus;
        uint256 oldDecayRatio = decayRatio;

        firstBonus = newFirstBonus;
        decayRatio = newDecayRatio;

        // Count active partnerships
        uint256 activeCount = 0;
        uint256 len = allPartnerships.length;
        for (uint256 i = 0; i < len; ++i) {
            if (partnerships[allPartnerships[i]].active) {
                ++activeCount;
            }
        }

        emit MultiplierParamsUpdated(
            oldFirstBonus, newFirstBonus, oldDecayRatio, newDecayRatio, block.timestamp, activeCount
        );
    }

    /*//////////////////////////////////////////////////////////////
                                  VIEWS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc INFTPartnershipRegistry
    function getActivePartnerships() external view returns (address[] memory active) {
        uint256 activeCount = 0;

        // Count active partnerships
        uint256 len = allPartnerships.length;
        for (uint256 i = 0; i < len; ++i) {
            if (partnerships[allPartnerships[i]].active) {
                ++activeCount;
            }
        }

        // Build active array
        active = new address[](activeCount);
        uint256 index = 0;
        for (uint256 i = 0; i < len; ++i) {
            if (partnerships[allPartnerships[i]].active) {
                active[index] = allPartnerships[i];
                ++index;
            }
        }

        return active;
    }

    /// @inheritdoc INFTPartnershipRegistry
    function getPartnership(address collection) external view returns (Partnership memory) {
        if (partnerships[collection].collection == address(0)) {
            revert PartnershipNotFound(collection);
        }
        return partnerships[collection];
    }

    /// @inheritdoc INFTPartnershipRegistry
    function getPartnershipCount() external view returns (uint256) {
        return allPartnerships.length;
    }
}
