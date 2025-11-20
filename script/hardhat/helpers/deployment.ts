import fs from "fs";
import path from "path";
import { NetworkConfig } from "../types/deploy";

/**
 * Load deployment configuration from deployments/{network}/addresses.json
 */
export function loadDeploymentConfig(networkName: string): NetworkConfig {
  const configPath = path.join(
    __dirname,
    "../../../deployments",
    networkName,
    "addresses.json"
  );

  if (fs.existsSync(configPath)) {
    return JSON.parse(fs.readFileSync(configPath, "utf-8"));
  }
  return { addresses: {} };
}

/**
 * Get default value for a parameter from config hierarchy:
 * 1. Deployed addresses (from current session) - highest priority
 * 2. deployments/{network}/addresses.json - network-specific deployed contracts
 * 3. Fallback defaults - hardcoded for common params
 */
export function getDefaultValue(
  paramName: string,
  configKey: string | undefined,
  networkConfig: NetworkConfig,
  deployedAddresses: Record<string, string>
): string | undefined {
  // Check deployment config by configKey FIRST (handles contract dependencies)
  // configKey is the PascalCase contract name (e.g., "DustLock")
  if (configKey && deployedAddresses[configKey]) {
    return deployedAddresses[configKey];
  }

  // Check by parameter name (for newly deployed contracts in same session)
  if (deployedAddresses[paramName]) {
    return deployedAddresses[paramName];
  }

  // Check network config addresses
  if (
    configKey &&
    networkConfig.addresses &&
    networkConfig.addresses[configKey]
  ) {
    return networkConfig.addresses[configKey];
  }

  // Fallback hardcoded defaults for common params
  const FALLBACK_DEFAULTS: Record<string, Record<string, string>> = {
    "monad-testnet": {
      aavePoolAddressesProvider: "0x0bAe833178A7Ef0C5b47ca10D844736F65CBd499",
      dust: "0x8c30De5c41528494DEC99f77a410FB63817dC7E2",
      forwarder: "0x0000000000000000000000000000000000000001", // No forwarder by default
      emissionManager: "", // Must be set
      owner: "", // Will use deployer
      keeper: "", // Will use deployer
      // Leaderboard defaults
      depositRateBps: "100",
      borrowRateBps: "500",
      vpRateBps: "200",
      supplyDailyBonus: "10000000000000000000", // 10 DUST
      borrowDailyBonus: "20000000000000000000", // 20 DUST
      repayDailyBonus: "0",
      withdrawDailyBonus: "0",
      cooldownSeconds: "3600", // 1 hour
      minDailyBonusUsd: "0",
      firstBonus: "1000", // 10%
      decayRatio: "9000", // 90%
      minSettlementInterval: "3600", // 1 hour
    },
    monad: {
      aavePoolAddressesProvider: "",
      dust: "",
      forwarder: "0x0000000000000000000000000000000000000000",
      emissionManager: "",
      owner: "",
      keeper: "",
      depositRateBps: "100",
      borrowRateBps: "500",
      vpRateBps: "200",
      supplyDailyBonus: "10000000000000000000",
      borrowDailyBonus: "20000000000000000000",
      repayDailyBonus: "0",
      withdrawDailyBonus: "0",
      cooldownSeconds: "3600",
      minDailyBonusUsd: "0",
      firstBonus: "1000",
      decayRatio: "9000",
      minSettlementInterval: "3600",
    },
    hardhat: {
      aavePoolAddressesProvider: "",
      dust: "",
      forwarder: "0x0000000000000000000000000000000000000000",
      emissionManager: "",
      owner: "",
      keeper: "",
      depositRateBps: "100",
      borrowRateBps: "500",
      vpRateBps: "200",
      supplyDailyBonus: "10000000000000000000",
      borrowDailyBonus: "20000000000000000000",
      repayDailyBonus: "0",
      withdrawDailyBonus: "0",
      cooldownSeconds: "3600",
      minDailyBonusUsd: "0",
      firstBonus: "1000",
      decayRatio: "9000",
      minSettlementInterval: "3600",
    },
  };

  const networkDefaults =
    FALLBACK_DEFAULTS[networkConfig.networkName || ""] || {};
  return networkDefaults[paramName];
}

/**
 * Topological sort for contract dependencies
 * Returns contracts in deployment order
 * Only checks dependencies that are also being deployed
 */
export function sortContractsByDependencies(
  contractKeys: Set<string>,
  getConfig: (key: string) => { dependencies?: string[] }
): string[] {
  const sortedContracts: string[] = [];
  const remaining = new Set(contractKeys);

  while (remaining.size > 0) {
    let addedInRound = false;
    for (const contractKey of Array.from(remaining)) {
      const config = getConfig(contractKey);

      // Check if all dependencies that are ALSO being deployed are resolved
      // Dependencies not in contractKeys are assumed to be already deployed
      const depsResolved =
        !config.dependencies ||
        config.dependencies.every((dep) => {
          // If dependency is not being deployed, it's already available
          if (!contractKeys.has(dep)) {
            return true;
          }
          // If dependency is being deployed, check if it's already sorted
          return sortedContracts.includes(dep);
        });

      if (depsResolved) {
        sortedContracts.push(contractKey);
        remaining.delete(contractKey);
        addedInRound = true;
      }
    }
    if (!addedInRound && remaining.size > 0) {
      throw new Error("Circular dependency detected!");
    }
  }

  return sortedContracts;
}

/**
 * Resolve all dependencies for selected contracts
 * Returns set of all contracts needed including dependencies
 */
export function resolveDependencies(
  selectedContracts: string[],
  getConfig: (key: string) => { dependencies?: string[] }
): { allContracts: Set<string>; addedDeps: string[] } {
  const allContractsNeeded = new Set<string>(selectedContracts);
  const addedDeps: string[] = [];
  let added = true;

  while (added) {
    added = false;
    for (const contractKey of Array.from(allContractsNeeded)) {
      const config = getConfig(contractKey);
      if (config.dependencies) {
        for (const dep of config.dependencies) {
          if (!allContractsNeeded.has(dep)) {
            allContractsNeeded.add(dep);
            addedDeps.push(dep);
            added = true;
          }
        }
      }
    }
  }

  return { allContracts: allContractsNeeded, addedDeps };
}

/**
 * Generate deployment export data
 */
export function generateDeploymentExport(
  networkName: string,
  deployerAddress: string,
  deploymentResults: Array<{ name: string; address: string }>
): object {
  return {
    network: networkName,
    deployer: deployerAddress,
    timestamp: new Date().toISOString(),
    contracts: Object.fromEntries(
      deploymentResults.map((r) => [r.name, r.address])
    ),
  };
}

/**
 * Validate Ethereum address
 */
export function isValidAddress(address: string, ethers: any): boolean {
  try {
    return ethers.isAddress(address);
  } catch {
    return false;
  }
}
