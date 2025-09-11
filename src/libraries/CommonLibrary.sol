// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

/**
 * @title CommonLibrary
 * @author Neverland
 * @notice Miscellaneous shared helpers used across the codebase
 */
library CommonLibrary {
    /**
     * @notice Returns true if `account` is a contract.
     * @dev This uses extcodesize/code.length which returns 0 for contracts in construction.
     * @param account The address to check.
     * @return True if code length > 0.
     */
    function isContract(address account) internal view returns (bool) {
        return account.code.length > 0;
    }
}
