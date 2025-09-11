// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

library CommonChecksLibrary {
    /// @notice Used when a zero address is provided where not allowed.
    error AddressZero();
    /// @notice Used when a zero amount is provided where not allowed.
    error ZeroAmount();
    /// @notice Used when a range is invalid.
    error InvalidRange();
    /// @notice Used when two addresses are the same but must differ.
    error SameAddress();
    /// @notice Used when a balance is zero.
    error ZeroBalance();
    /// @notice Used when a tokenId is invalid.
    error InvalidTokenId();
    /// @notice Used when a from address is invalid.
    error InvalidFromAddress();
    /// @notice Used when a to address is invalid.
    error InvalidToAddress();
    /// @notice Used when a user address is invalid.
    error InvalidUserAddress();
    /// @notice Used a function is called by an account that is not permitted.
    error UnauthorizedAccess();

    /**
     * @dev Reverts if the address is zero.
     * @param addressToCheck The address to check.
     */
    function revertIfZeroAddress(address addressToCheck) internal pure {
        if (addressToCheck == address(0)) revert AddressZero();
    }

    /**
     * @dev Reverts if the amount is zero.
     * @param amount The amount to check.
     */
    function revertIfZeroAmount(uint256 amount) internal pure {
        if (amount == 0) revert ZeroAmount();
    }

    /**
     * @dev Reverts if the range is invalid.
     * @param from The start of the range.
     * @param to The end of the range.
     */
    function revertIfInvalidRange(uint256 from, uint256 to) internal pure {
        if (from > to) revert InvalidRange();
    }

    /**
     * @dev Reverts if the addresses are the same.
     * @param first The first address to check.
     * @param second The second address to check.
     */
    function revertIfSameAddress(address first, address second) internal pure {
        if (first == second) revert SameAddress();
    }

    /**
     * @dev Reverts if the balance is zero.
     * @param balance The balance to check.
     */
    function revertIfZeroBalance(uint256 balance) internal pure {
        if (balance == 0) revert ZeroBalance();
    }

    /**
     * @dev Reverts if the tokenId is invalid.
     * @param owner The owner of the tokenId.
     */
    function revertIfInvalidTokenId(address owner) internal pure {
        if (owner == address(0)) revert InvalidTokenId();
    }

    /**
     * @dev Reverts if the from address is invalid.
     * @param from The from address to check.
     */
    function revertIfInvalidFromAddress(address from) internal pure {
        if (from == address(0)) revert InvalidFromAddress();
    }

    /**
     * @dev Reverts if the to address is invalid.
     * @param to The to address to check.
     */
    function revertIfInvalidToAddress(address to) internal pure {
        if (to == address(0)) revert InvalidToAddress();
    }

    /**
     * @dev Reverts if the user address is invalid.
     * @param user The user address to check.
     */
    function revertIfInvalidUserAddress(address user) internal pure {
        if (user == address(0)) revert InvalidUserAddress();
    }
}
