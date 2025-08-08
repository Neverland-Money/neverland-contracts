// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IDustTransferStrategy} from "./IDustTransferStrategy.sol";
import {AddressZero, InvalidTokenId} from "../_shared/CommonErrors.sol";

/**
 * @title IDustLockTransferStrategy
 * @author Neverland
 * @notice Interface for the DustLock transfer strategy which manages reward distributions to veNFT holders
 * @dev Extends IDustTransferStrategy with specialized error handling for veNFT-related reward transfers
 */
interface IDustLockTransferStrategy is IDustTransferStrategy {
    /// Errors

    /// @notice Error thrown when an invalid reward token address is provided
    error InvalidRewardAddress();

    /// @notice Error thrown when the caller is not the owner of the veNFT token
    error NotTokenOwner();
}
