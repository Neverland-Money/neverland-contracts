// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IDustTransferStrategy} from "./IDustTransferStrategy.sol";
import {IDustLock} from "./IDustLock.sol";

/**
 * @title IDustLockTransferStrategy
 * @author Neverland
 * @notice Interface for the DustLock transfer strategy which manages reward distributions to veNFT holders
 * @dev Extends IDustTransferStrategy with specialized functionality for veNFT integration and DUST token handling
 */
interface IDustLockTransferStrategy is IDustTransferStrategy {
    /// @notice Error thrown when reward token is not DUST
    error InvalidRewardAddress();

    /// @notice Error thrown when tokenId owner is not the recipient
    error NotTokenOwner();

    /*//////////////////////////////////////////////////////////////
                                 VIEWS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the DustLock contract that manages veNFTs
     * @return The DustLock contract interface
     */
    function DUST_LOCK() external view returns (IDustLock);

    /**
     * @notice Returns the vault address where DUST rewards are stored before distribution
     * @return The address of the DUST vault
     */
    function DUST_VAULT() external view returns (address);

    /**
     * @notice Returns the DUST token address
     * @return The address of the DUST token
     */
    function DUST() external view returns (address);
}
