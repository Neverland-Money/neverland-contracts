// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {UserVault} from "../../src/self-repaying-loans/UserVault.sol";

// Exposes the internal functions as an external ones
contract UserVaultHarness is UserVault {
    constructor() UserVault() {}

    function exposed_getAssetsPrices(address token1, address token2) external view returns (uint256[] memory) {
        return _getTokenPricesInUsd_8dec(token1, token2);
    }
}
