// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IDustTransferStrategy} from './IDustTransferStrategy.sol';

/**
 * @title IDustLockTransferStrategy
 * @author Neverland
 */
interface IDustLockTransferStrategy is IDustTransferStrategy {
    error AddressZero();
    error InvalidRewardAddress();
    error InvalidTokenId();
}