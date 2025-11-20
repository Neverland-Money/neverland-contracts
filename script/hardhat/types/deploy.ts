// Deployment-related type definitions

export type DeployableContract =
  | "Dust"
  | "DustLock"
  | "RevenueReward"
  | "DustRewardsController"
  | "DustLockTransferStrategy"
  | "NeverlandDustHelper"
  | "NeverlandUiProvider"
  | "UserVaultRegistry"
  | "UserVaultImplementation"
  | "UserVaultBeacon"
  | "UserVaultFactory";

export type AddressBook = Partial<Record<DeployableContract, string>>;

export interface TaskArgs {
  configFile?: string;
  exclude?: string;
  dryRun?: boolean;
}

export interface DeployConfig {
  addresses?: Partial<Record<DeployableContract, string>>;
  dust?: {
    initialOwner?: string;
    totalSupply?: string;
  };
  dustLock?: {
    forwarder?: string;
    baseURI?: string;
    team?: string;
    earlyWithdrawTreasury?: string;
    minLockAmount?: string;
  };
  dustRewardsController?: {
    emissionManager?: string;
  };
  revenueReward?: {
    forwarder?: string;
    distributor?: string;
  };
  transferStrategy?: {
    incentivesControllerOverride?: string;
    rewardsAdmin?: string;
    dustVault?: string;
  };
  dustHelper?: {
    forwarder?: string;
    owner?: string;
    uniswapPair?: string;
  };
  uiProvider?: {
    forwarder?: string;
    aaveLendingPoolAddressProvider?: string;
  };
  selfRepaying?: {
    registry?: {
      owner?: string;
      executor?: string;
      maxSwapSlippageBps?: string;
      supportedAggregators?: string[];
    };
    beaconOwner?: string;
    poolAddressesProviderRegistry?: string;
  };
  proxyAdmin?: {
    owner?: string;
  };
}

export interface DeployNeverlandArgs {
  forwarder: string;
  dustlock?: string;
  usdc?: string;
  distributor?: string;
  dryrun?: boolean;
}

export interface DeployImplArgs {
  forwarder: string;
  dryrun?: boolean;
}

export interface UpgradeProxyArgs {
  proxyadmin: string;
  proxy: string;
  impl: string;
}

export interface EmergencyFixDistributorArgs {
  proxy: string;
  distributor: string;
}

export interface DeploymentConfig {
  forwarder: string;
  dustlock: string;
  usdc: string;
  distributor: string;
  dryrun: boolean;
}

export interface ContractAddresses {
  dustLock: string;
  revenueReward: string;
  dustRewardsController: string;
  userVaultFactory: string;
  proxyAdmin: string;
}

// Interactive deployment types
export interface ContractParam {
  name: string;
  type: string;
  description: string;
  configKey?: string; // Key to lookup in deployment config
}

export interface ContractConfig {
  name: string;
  displayName: string;
  description: string;
  constructorParams: ContractParam[];
  dependencies?: string[]; // Other contracts that must be deployed first
}

export interface NetworkConfig {
  networkName?: string;
  chainId?: number;
  addresses?: Record<string, string>;
}

export interface DeploymentResult {
  name: string;
  address: string;
  params: string[];
}
