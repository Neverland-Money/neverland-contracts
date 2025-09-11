// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

import {IPoolAddressesProvider} from "@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol";

import {UserVault} from "../../src/self-repaying-loans/UserVault.sol";

// Exposes the internal functions as an external ones
contract UserVaultHarness is UserVault {
    constructor() UserVault() {}

    function exposed_getAssetsPrices(address token1, address token2, IPoolAddressesProvider poolAddressesProvider)
        external
        view
        returns (uint256[] memory)
    {
        return _getTokenPricesInUsd_8dec(token1, token2, poolAddressesProvider);
    }

    function exposed_verifySlippage(
        uint256 desiredSwapAmountInTokenA,
        uint256 tokenAUnitPriceInUSD_8dec,
        uint256 actualSwappedAmountInTokenB,
        uint256 tokenBUnitPriceInUSD_8dec,
        uint256 maxAllowedSlippageBps
    ) external pure {
        _verifySlippage(
            desiredSwapAmountInTokenA,
            tokenAUnitPriceInUSD_8dec,
            actualSwappedAmountInTokenB,
            tokenBUnitPriceInUSD_8dec,
            maxAllowedSlippageBps
        );
    }
}
