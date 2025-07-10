// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IDustTransferStrategy} from './IDustTransferStrategy.sol';

/**
 * @title IDustLockTransferStrategy
 * @author Neverland
 * @notice Interface for the DustLock transfer strategy which manages reward distributions to veNFT holders
 * @dev Extends IDustTransferStrategy with specialized error handling for veNFT-related reward transfers
 */
interface IDustLockTransferStrategy is IDustTransferStrategy {
    /// @notice Error thrown when a zero address is provided where a valid address is required
    error AddressZero();
    
    /// @notice Error thrown when an invalid reward token address is provided
    error InvalidRewardAddress();
    
    /// @notice Error thrown when an invalid veNFT token ID is used
    error InvalidTokenId();
}