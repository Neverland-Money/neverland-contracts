// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IRevenueReward} from "../interfaces/IRevenueReward.sol";
import {IUserVaultRegistry} from "../interfaces/IUserVaultRegistry.sol";
import {IUserVault} from "../interfaces/IUserVault.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {IPool} from "@aave/core-v3/contracts/interfaces/IPool.sol";
import {IAaveOracle} from "@aave/core-v3/contracts/interfaces/IAaveOracle.sol";

contract UserVault is IUserVault, Initializable {
    IUserVaultRegistry immutable userVaultRegistry;
    IAaveOracle immutable aaveOracle;
    address user;

    /// @dev these properties are set to implementation contract
    constructor(IUserVaultRegistry _userVaultRegistry, IAaveOracle _aaveOracle) {
        userVaultRegistry = _userVaultRegistry;
        aaveOracle = _aaveOracle;
        _disableInitializers();
    }

    /// @dev these properties are set to proxy contract
    function initialize(address _user) external initializer {
        user = _user;
    }

    function repayUserDebt(
        address debtToken,
        address poolAddress,
        uint256[] calldata tokenIds,
        address[] calldata rewardTokens,
        address[] calldata aggregatorAddress,
        bytes[] calldata aggregatorData
    ) public onlyExecutor {
        // TODO: implement
        // TODO: get user tokens on-chain, check which ones are self repaying
        // getReward(tokenIds, rewardTokens);
        // swappedAmount = 9;
        // loop: swappedAmount += swap(debtToken, address, aggregatorData, 1_000)
        // repayDebt(poolAddress, debtToken, swappedAmount)
    }

    function swap(address token, address aggregator, bytes calldata aggregatorData, uint256 slippage)
        public
        onlyExecutor
    {
        if (userVaultRegistry.isSupportedAggregator(aggregator)) {
            revert AggregatorNotSupported();
        }
        IERC20(token).approve(aggregator, IERC20(token).balanceOf(address(this)));
        (bool success,) = aggregator.call(aggregatorData);
        // TODO: implement
        // check amount (slippage) using AAVE oracle
        // IAaveOracle.getAssetsPrices()
        require(success, "Swap failed");
    }

    function repayDebt(address poolAddress, address debtToken, uint256 amount) public onlyExecutor {
        IERC20(debtToken).approve(poolAddress, amount);
        IPool(poolAddress).repay(debtToken, amount, 2, user);
    }

    function depositCollateral(address poolAddress, address debtToken, uint256 amount) public onlyExecutor {
        IERC20(debtToken).approve(poolAddress, amount);
        IPool(poolAddress).supply(debtToken, amount, user, 0);
    }

    function recoverERC20(address token, uint256 amount) public onlyExecutor {
        IERC20(token).transfer(user, amount);
    }

    function recoverETH(uint256 amount) public onlyExecutor {
        payable(user).transfer(amount);
    }

    // MODIFIERS

    modifier onlyExecutor() {
        if (!isExecutor(msg.sender)) {
            revert NotExecutor();
        }
        _;
    }

    function isExecutor(address account) private view returns (bool) {
        return userVaultRegistry.executor() == account;
    }
}
