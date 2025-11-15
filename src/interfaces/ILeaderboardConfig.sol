// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

/**
 * @title ILeaderboardConfig
 * @author Neverland
 * @notice Interface for dynamic leaderboard configuration
 */
interface ILeaderboardConfig {
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Emitted when deposit rate is updated
     * @param oldRate Previous rate in basis points
     * @param newRate New rate in basis points
     * @param timestamp Block timestamp of update
     */
    event DepositRateUpdated(uint256 oldRate, uint256 newRate, uint256 timestamp);

    /**
     * @notice Emitted when borrow rate is updated
     * @param oldRate Previous rate in basis points
     * @param newRate New rate in basis points
     * @param timestamp Block timestamp of update
     */
    event BorrowRateUpdated(uint256 oldRate, uint256 newRate, uint256 timestamp);

    /**
     * @notice Emitted when VP rate is updated
     * @param oldRate Previous rate in basis points
     * @param newRate New rate in basis points
     * @param timestamp Block timestamp of update
     */
    event VpRateUpdated(uint256 oldRate, uint256 newRate, uint256 timestamp);

    /**
     * @notice Emitted when daily bonuses are updated
     * @param oldSupplyBonus Previous supply daily bonus
     * @param newSupplyBonus New supply daily bonus
     * @param oldBorrowBonus Previous borrow daily bonus
     * @param newBorrowBonus New borrow daily bonus
     * @param oldRepayBonus Previous repay daily bonus
     * @param newRepayBonus New repay daily bonus
     * @param oldWithdrawBonus Previous withdraw daily bonus
     * @param newWithdrawBonus New withdraw daily bonus
     * @param timestamp Block timestamp of update
     */
    event DailyBonusUpdated(
        uint256 oldSupplyBonus,
        uint256 newSupplyBonus,
        uint256 oldBorrowBonus,
        uint256 newBorrowBonus,
        uint256 oldRepayBonus,
        uint256 newRepayBonus,
        uint256 oldWithdrawBonus,
        uint256 newWithdrawBonus,
        uint256 timestamp
    );

    /**
     * @notice Emitted when cooldown is updated
     * @param oldSeconds Previous cooldown in seconds
     * @param newSeconds New cooldown in seconds
     * @param timestamp Block timestamp of update
     */
    event CooldownUpdated(uint256 oldSeconds, uint256 newSeconds, uint256 timestamp);

    /**
     * @notice Emitted when minimum daily bonus USD is updated
     * @param oldMin Previous minimum USD value
     * @param newMin New minimum USD value
     * @param timestamp Block timestamp of update
     */
    event MinDailyBonusUsdUpdated(uint256 oldMin, uint256 newMin, uint256 timestamp);

    /**
     * @notice Emitted with complete config snapshot whenever any parameter changes
     * @param depositRateBps Current deposit rate in basis points
     * @param borrowRateBps Current borrow rate in basis points
     * @param vpRateBps Current VP rate in basis points (per 1e18 VP)
     * @param supplyDailyBonus Current supply daily bonus
     * @param borrowDailyBonus Current borrow daily bonus
     * @param repayDailyBonus Current repay daily bonus
     * @param withdrawDailyBonus Current withdraw daily bonus
     * @param cooldownSeconds Current cooldown period
     * @param minDailyBonusUsd Current minimum USD for daily bonus
     * @param timestamp Block timestamp of update
     */
    event ConfigSnapshot(
        uint256 depositRateBps,
        uint256 borrowRateBps,
        uint256 vpRateBps,
        uint256 supplyDailyBonus,
        uint256 borrowDailyBonus,
        uint256 repayDailyBonus,
        uint256 withdrawDailyBonus,
        uint256 cooldownSeconds,
        uint256 minDailyBonusUsd,
        uint256 timestamp
    );

    /**
     * @notice Emitted when points are manually awarded to a user
     * @param user Wallet address receiving points
     * @param points Amount of points awarded (18 decimals)
     * @param reason Optional description for the award
     * @param timestamp Block timestamp of award
     */
    event PointsAwarded(address indexed user, uint256 points, string reason, uint256 timestamp);

    /**
     * @notice Emitted when points are manually removed from a user
     * @param user Wallet address losing points
     * @param points Amount of points removed (18 decimals)
     * @param reason Optional description for the removal
     * @param timestamp Block timestamp of removal
     */
    event PointsRemoved(address indexed user, uint256 points, string reason, uint256 timestamp);

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Thrown when rate exceeds maximum
     * @param rate Invalid rate value
     */
    error RateTooHigh(uint256 rate);

    /**
     * @notice Thrown when bonus exceeds maximum
     * @param bonus Invalid bonus value
     */
    error BonusTooHigh(uint256 bonus);

    /**
     * @notice Thrown when cooldown exceeds maximum
     * @param cooldown Invalid cooldown value
     */
    error CooldownTooLong(uint256 cooldown);

    /*//////////////////////////////////////////////////////////////
                               ACTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Update deposit point rate
     * @param newRateBps New rate in basis points per day per USD
     */
    function setDepositRate(uint256 newRateBps) external;

    /**
     * @notice Update borrow point rate
     * @param newRateBps New rate in basis points per day per USD
     */
    function setBorrowRate(uint256 newRateBps) external;

    /**
     * @notice Update VP point rate
     * @param newRateBps New rate in basis points per day per 1e18 VP
     */
    function setVpRate(uint256 newRateBps) external;

    /**
     * @notice Update daily bonuses
     * @param supply New supply daily bonus (18 decimals)
     * @param borrow New borrow daily bonus (18 decimals)
     * @param repay New repay daily bonus (18 decimals)
     * @param withdraw New withdraw daily bonus (18 decimals)
     */
    function setDailyBonuses(uint256 supply, uint256 borrow, uint256 repay, uint256 withdraw) external;

    /**
     * @notice Update cooldown period
     * @param newSeconds New cooldown in seconds
     */
    function setCooldown(uint256 newSeconds) external;

    /**
     * @notice Update minimum daily bonus USD threshold
     * @param newMin New minimum USD value (18 decimals)
     */
    function setMinDailyBonusUsd(uint256 newMin) external;

    /**
     * @notice Batch update all rates (gas efficient)
     * @param _depositRate New deposit rate
     * @param _borrowRate New borrow rate
     * @param _vpRate New VP rate
     * @param _supplyBonus New supply bonus
     * @param _borrowBonus New borrow bonus
     */
    function updateAllRates(
        uint256 _depositRate,
        uint256 _borrowRate,
        uint256 _vpRate,
        uint256 _supplyBonus,
        uint256 _borrowBonus
    ) external;

    /**
     * @notice Manually award points to a user (e.g., for special events)
     * @param user Wallet address to receive points
     * @param points Amount of points to award (18 decimals)
     * @param reason Optional description for the award
     */
    function awardPoints(address user, uint256 points, string calldata reason) external;

    /**
     * @notice Batch award points to multiple users (gas efficient)
     * @param users Array of wallet addresses to receive points
     * @param points Array of points amounts to award (18 decimals)
     * @param reason Optional description for the batch award
     */
    function batchAwardPoints(address[] calldata users, uint256[] calldata points, string calldata reason) external;

    /**
     * @notice Manually remove points from a user (e.g., for penalties)
     * @param user Wallet address to remove points from
     * @param points Amount of points to remove (18 decimals)
     * @param reason Optional description for the removal
     */
    function removePoints(address user, uint256 points, string calldata reason) external;

    /**
     * @notice Batch remove points from multiple users (gas efficient)
     * @param users Array of wallet addresses to remove points from
     * @param points Array of points amounts to remove (18 decimals)
     * @param reason Optional description for the batch removal
     */
    function batchRemovePoints(address[] calldata users, uint256[] calldata points, string calldata reason) external;

    /*//////////////////////////////////////////////////////////////
                                 VIEWS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get deposit rate per day
     * @return rate Rate in basis points
     */
    function getDepositRatePerDay() external view returns (uint256 rate);

    /**
     * @notice Get borrow rate per day
     * @return rate Rate in basis points
     */
    function getBorrowRatePerDay() external view returns (uint256 rate);

    /**
     * @notice Get VP rate per day
     * @return rate Rate in basis points per 1e18 VP
     */
    function getVpRatePerDay() external view returns (uint256 rate);

    /**
     * @notice Get daily bonuses
     * @return supply Supply daily bonus
     * @return borrow Borrow daily bonus
     * @return repay Repay daily bonus
     * @return withdraw Withdraw daily bonus
     */
    function getDailyBonuses() external view returns (uint256 supply, uint256 borrow, uint256 repay, uint256 withdraw);

    /**
     * @notice Get all configuration values
     * @return depositRate Deposit rate in basis points
     * @return borrowRate Borrow rate in basis points
     * @return vpRate VP rate in basis points (per 1e18 VP)
     * @return supplyBonus Supply daily bonus
     * @return borrowBonus Borrow daily bonus
     * @return repayBonus Repay daily bonus
     * @return withdrawBonus Withdraw daily bonus
     * @return cooldown Cooldown period in seconds
     * @return minUsd Minimum USD for daily bonus
     */
    function getAllConfig()
        external
        view
        returns (
            uint256 depositRate,
            uint256 borrowRate,
            uint256 vpRate,
            uint256 supplyBonus,
            uint256 borrowBonus,
            uint256 repayBonus,
            uint256 withdrawBonus,
            uint256 cooldown,
            uint256 minUsd
        );

    /**
     * @notice Get deposit rate in basis points
     * @return Deposit rate per day per USD
     */
    function depositRateBps() external view returns (uint256);

    /**
     * @notice Get borrow rate in basis points
     * @return Borrow rate per day per USD
     */
    function borrowRateBps() external view returns (uint256);

    /**
     * @notice Get VP rate in basis points
     * @return VP rate per day per 1e18 VP
     */
    function vpRateBps() external view returns (uint256);

    /**
     * @notice Get supply daily bonus
     * @return Supply daily bonus (18 decimals)
     */
    function supplyDailyBonus() external view returns (uint256);

    /**
     * @notice Get borrow daily bonus
     * @return Borrow daily bonus (18 decimals)
     */
    function borrowDailyBonus() external view returns (uint256);

    /**
     * @notice Get cooldown period
     * @return Cooldown in seconds
     */
    function cooldownSeconds() external view returns (uint256);

    /**
     * @notice Get minimum daily bonus USD
     * @return Minimum USD value (18 decimals)
     */
    function minDailyBonusUsd() external view returns (uint256);

    /**
     * @notice Get repay daily bonus
     * @return Repay daily bonus (18 decimals)
     */
    function repayDailyBonus() external view returns (uint256);

    /**
     * @notice Get withdraw daily bonus
     * @return Withdraw daily bonus (18 decimals)
     */
    function withdrawDailyBonus() external view returns (uint256);
}
