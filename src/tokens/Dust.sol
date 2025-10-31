// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {
    ERC20PausableUpgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PausableUpgradeable.sol";
import {
    ERC20PermitUpgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";

import {CommonChecksLibrary} from "../libraries/CommonChecksLibrary.sol";

/**
 * @title Dust
 * @author Neverland
 * @notice ERC20 token with pausable transfers and permit
 */
contract Dust is
    Initializable,
    ERC20Upgradeable,
    ERC20PausableUpgradeable,
    Ownable2StepUpgradeable,
    ERC20PermitUpgradeable
{
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the contract
     * @param initialOwner The address that will own the contract after initialization
     * @param ts TotalSupply of the token (in wei w/o decimals)
     */
    function initialize(address initialOwner, uint256 ts) public initializer {
        CommonChecksLibrary.revertIfZeroAddress(initialOwner);

        __ERC20_init("Pixie Dust", "DUST");
        __ERC20Pausable_init();
        __Ownable2Step_init();
        __ERC20Permit_init("Pixie Dust");
        _transferOwnership(initialOwner);
        _mint(initialOwner, ts * 10 ** decimals());
    }

    /**
     * @notice Pauses all token transfers
     * @dev Can only be called by the contract owner
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpauses all token transfers
     * @dev Can only be called by the contract owner
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Hook that is called before any transfer of tokens
     * @dev Overrides both ERC20Upgradeable and ERC20PausableUpgradeable implementations
     *      This combined implementation ensures:
     *      1. The base ERC20 transfer logic is executed
     *      2. The pausable functionality is enforced (transfers fail when contract is paused)
     *      It's called in these scenarios:
     *      - Regular transfers between addresses (both from and to are non-zero)
     *      - Minting new tokens (from is zero)
     *      - Burning tokens (to is zero)
     * @param from Address tokens are transferred from (zero for minting)
     * @param to Address tokens are transferred to (zero for burning)
     * @param value Amount of tokens to transfer
     */
    function _beforeTokenTransfer(address from, address to, uint256 value)
        internal
        override(ERC20Upgradeable, ERC20PausableUpgradeable)
    {
        super._beforeTokenTransfer(from, to, value);
    }

    /// @notice Disabled to prevent accidental renouncement of ownership
    function renounceOwnership() public view override onlyOwner {
        revert();
    }

    /**
     * @dev Storage gap for upgrade-safe future upgrades.
     *      Add new state variables above this line and reduce the gap length.
     */
    uint256[50] private __gap;
}
