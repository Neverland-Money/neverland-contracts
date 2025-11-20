import { ContractConfig } from "../types/deploy";

/**
 * Contract deployment configurations
 * Defines all deployable contracts, their parameters, and dependencies
 */
export const CONTRACTS: Record<string, ContractConfig> = {
  DustLock: {
    name: "DustLock",
    displayName: "DustLock",
    description:
      "Lock DUST tokens and get veDUST voting power (Upgradeable - uses initialize)",
    constructorParams: [
      {
        name: "forwarder",
        type: "address",
        description: "Trusted forwarder address for ERC2771",
        configKey: "forwarder",
      },
    ],
  },
  RevenueReward: {
    name: "RevenueReward",
    displayName: "RevenueReward",
    description:
      "Distribute revenue rewards to veDUST holders (Upgradeable - uses initialize)",
    constructorParams: [
      {
        name: "forwarder",
        type: "address",
        description: "Trusted forwarder address for ERC2771",
        configKey: "forwarder",
      },
    ],
  },
  DustRewardsController: {
    name: "DustRewardsController",
    displayName: "DustRewardsController",
    description:
      "Control DUST emissions to lending markets (Upgradeable - uses initialize)",
    constructorParams: [
      {
        name: "emissionManager",
        type: "address",
        description: "Emission manager address",
        configKey: "emissionManager",
      },
    ],
  },
  NeverlandDustHelper: {
    name: "NeverlandDustHelper",
    displayName: "NeverlandDustHelper",
    description: "Helper contract for DUST price oracle and team operations",
    constructorParams: [
      {
        name: "dustToken",
        type: "address",
        description: "DUST token address (ERC20)",
        configKey: "Dust",
      },
      {
        name: "initialOwner",
        type: "address",
        description: "Initial owner address",
        configKey: "owner",
      },
    ],
  },
  NeverlandUiProvider: {
    name: "NeverlandUiProvider",
    displayName: "NeverlandUiProvider",
    description: "UI data aggregator for frontend",
    constructorParams: [
      {
        name: "dustLock",
        type: "address",
        description: "DustLock contract address",
        configKey: "DustLock",
      },
      {
        name: "revenueReward",
        type: "address",
        description: "RevenueReward contract address",
        configKey: "RevenueReward",
      },
      {
        name: "dustRewardsController",
        type: "address",
        description: "DustRewardsController contract address",
        configKey: "DustRewardsController",
      },
      {
        name: "dustOracle",
        type: "address",
        description: "DUST price oracle (NeverlandDustHelper)",
        configKey: "NeverlandDustHelper",
      },
      {
        name: "aaveLendingPoolAddressProvider",
        type: "address",
        description: "Aave Lending Pool Address Provider",
        configKey: "aavePoolAddressesProvider",
      },
    ],
    dependencies: [
      "DustLock",
      "RevenueReward",
      "DustRewardsController",
      "NeverlandDustHelper",
    ],
  },
  EpochManager: {
    name: "EpochManager",
    displayName: "EpochManager",
    description: "Manage leaderboard epochs (manual start/end)",
    constructorParams: [
      {
        name: "initialOwner",
        type: "address",
        description: "Initial owner address",
        configKey: "owner",
      },
    ],
  },
  LeaderboardConfig: {
    name: "LeaderboardConfig",
    displayName: "LeaderboardConfig",
    description: "Leaderboard scoring rates and bonuses",
    constructorParams: [
      {
        name: "initialOwner",
        type: "address",
        description: "Initial owner address",
        configKey: "owner",
      },
      {
        name: "depositRateBps",
        type: "uint256",
        description: "Deposit rate in basis points (100 = 0.01)",
        configKey: "depositRateBps",
      },
      {
        name: "borrowRateBps",
        type: "uint256",
        description: "Borrow rate in basis points (500 = 0.05)",
        configKey: "borrowRateBps",
      },
      {
        name: "vpRateBps",
        type: "uint256",
        description: "Voting power rate per 1e18 VP",
        configKey: "vpRateBps",
      },
      {
        name: "supplyDailyBonus",
        type: "uint256",
        description: "Daily supply bonus points (10e18 = 10 points)",
        configKey: "supplyDailyBonus",
      },
      {
        name: "borrowDailyBonus",
        type: "uint256",
        description: "Daily borrow bonus points (20e18 = 20 points)",
        configKey: "borrowDailyBonus",
      },
      {
        name: "repayDailyBonus",
        type: "uint256",
        description: "Daily repay bonus points (0 = disabled)",
        configKey: "repayDailyBonus",
      },
      {
        name: "withdrawDailyBonus",
        type: "uint256",
        description: "Daily withdraw bonus points (0 = disabled)",
        configKey: "withdrawDailyBonus",
      },
      {
        name: "cooldownSeconds",
        type: "uint256",
        description: "Cooldown period in seconds (3600 = 1 hour)",
        configKey: "cooldownSeconds",
      },
      {
        name: "minDailyBonusUsd",
        type: "uint256",
        description: "Minimum USD value for daily bonus (0 = disabled)",
        configKey: "minDailyBonusUsd",
      },
    ],
  },
  NFTPartnershipRegistry: {
    name: "NFTPartnershipRegistry",
    displayName: "NFTPartnershipRegistry",
    description: "Registry for NFT partnership multipliers",
    constructorParams: [
      {
        name: "initialOwner",
        type: "address",
        description: "Initial owner address",
        configKey: "owner",
      },
      {
        name: "firstBonus",
        type: "uint256",
        description: "First NFT bonus in basis points (1000 = 0.1 = 10%)",
        configKey: "firstBonus",
      },
      {
        name: "decayRatio",
        type: "uint256",
        description: "Decay ratio per additional NFT (9000 = 0.9 = 90%)",
        configKey: "decayRatio",
      },
    ],
  },
  VotingPowerMultiplier: {
    name: "VotingPowerMultiplier",
    displayName: "VotingPowerMultiplier",
    description: "Calculate voting power with tier-based multipliers",
    constructorParams: [
      {
        name: "initialOwner",
        type: "address",
        description: "Initial owner address",
        configKey: "owner",
      },
      {
        name: "dustLock",
        type: "address",
        description: "DustLock contract address",
        configKey: "DustLock",
      },
    ],
    dependencies: ["DustLock"],
  },
  LeaderboardKeeper: {
    name: "LeaderboardKeeper",
    displayName: "LeaderboardKeeper",
    description: "Leaderboard user data tracking and settlement",
    constructorParams: [
      {
        name: "initialOwner",
        type: "address",
        description: "Initial owner address",
        configKey: "owner",
      },
      {
        name: "initialKeeper",
        type: "address",
        description: "Initial keeper address (can settle)",
        configKey: "keeper",
      },
      {
        name: "initialInterval",
        type: "uint256",
        description: "Minimum settlement interval in seconds (3600 = 1 hour)",
        configKey: "minSettlementInterval",
      },
      {
        name: "dustLock",
        type: "address",
        description: "DustLock contract address",
        configKey: "DustLock",
      },
      {
        name: "nftRegistry",
        type: "address",
        description: "NFT Partnership Registry address",
        configKey: "NFTPartnershipRegistry",
      },
    ],
    dependencies: ["DustLock", "NFTPartnershipRegistry"],
  },
  UserVaultRegistry: {
    name: "UserVaultRegistry",
    displayName: "UserVaultRegistry",
    description:
      "Registry for user self-repaying vaults (No constructor - use transferOwnership after)",
    constructorParams: [],
  },
  UserVaultFactory: {
    name: "UserVaultFactory",
    displayName: "UserVaultFactory",
    description:
      "Factory for creating user self-repaying vaults (Upgradeable - uses initialize)",
    constructorParams: [],
  },
};
