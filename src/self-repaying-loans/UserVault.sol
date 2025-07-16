// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IRevenueReward} from "../interfaces/IRevenueReward.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {UserVaultRegistry} from "./UserVaultRegistry.sol";
import {IUserVault} from "../interfaces/IUserVault.sol";

contract UserVault is IUserVault, Initializable {
    UserVaultRegistry userVaultRegistry;
    address user;

    constructor(UserVaultRegistry _userVaultRegistry) {
        userVaultRegistry = _userVaultRegistry;
        _disableInitializers();
    }

    function initialize(address _user) external initializer {
        user = _user;
    }

    function repayUserDebt(
        address tokenB,
        address poolAddress,
        address aggregatorAddress,
        bytes calldata aggregatorData
    ) public onlyExecutor {
        // TODO: placeholder
    }

    function swap(address tokenB, address aggregator, bytes calldata aggregatorData) public onlyExecutor {
        if (userVaultRegistry.isSupportedAggregator(aggregator)) {
            revert AggregatorNotSupported();
        }
        // TODO: placeholder
    }

    function repayDebt(address poolAddress, address token, uint256 amount) public onlyExecutor {
        // TODO: continue
    }

    function depositCollateral(address poolAddress, address token, uint256 amount) public onlyExecutor {
        // TODO: continue
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
