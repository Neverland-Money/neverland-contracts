// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

/// @notice Used when configuring an address with a zero address.
error AddressZero();

/// @notice Used when a zero amount is provided where not allowed.
error ZeroAmount();

/// @notice Used when an invalid range is provided.
error InvalidRange();

/// @notice Used when two addresses are the same but must differ.
error SameAddress();

/// @notice Used when an operation requires a non-zero balance.
error ZeroBalance();

/// @notice Used when a tokenId is invalid or does not exist.
error InvalidTokenId();
