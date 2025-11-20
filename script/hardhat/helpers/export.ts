import fs from "fs";
import path from "path";
import { HardhatRuntimeEnvironment } from "hardhat/types";

/**
 * Standard deployment export interface
 */
export interface DeploymentExport {
  address: string;
  constructorArgs?: any[];
  metadata?: {
    txHash?: string;
    deployer?: string;
    timestamp?: number;
    blockNumber?: number;
    gasUsed?: string;
    chainId?: number;
    [key: string]: any;
  };
}

/**
 * Export a single contract deployment to the deployments folder
 * Creates addresses.json at root and timestamped contract file
 */
export async function exportDeployment(
  hre: HardhatRuntimeEnvironment,
  contractName: string,
  deployment: DeploymentExport,
  sessionTimestamp?: number
): Promise<void> {
  const network = hre.network.name;
  const deploymentsDir = path.join(__dirname, "../../../deployments", network);
  const timestamp =
    sessionTimestamp || deployment.metadata?.timestamp || Date.now();

  // Ensure deployments directory exists
  if (!fs.existsSync(deploymentsDir)) {
    fs.mkdirSync(deploymentsDir, { recursive: true });
  }

  // 1. Update addresses.json at root (always current addresses)
  const addressesFile = path.join(deploymentsDir, "addresses.json");
  let addresses: Record<string, string> = {};

  if (fs.existsSync(addressesFile)) {
    addresses = JSON.parse(fs.readFileSync(addressesFile, "utf-8"));
  }

  addresses[contractName] = deployment.address;
  fs.writeFileSync(addressesFile, JSON.stringify(addresses, null, 2));

  // 2. Create timestamped session folder
  const sessionDir = path.join(deploymentsDir, timestamp.toString());
  if (!fs.existsSync(sessionDir)) {
    fs.mkdirSync(sessionDir, { recursive: true });
  }

  // 3. Create contract file in session folder
  const contractFile = path.join(sessionDir, `${contractName}.json`);
  const contractData = {
    address: deployment.address,
    constructorArgs: deployment.constructorArgs || [],
    metadata: deployment.metadata || {},
  };

  fs.writeFileSync(contractFile, JSON.stringify(contractData, null, 2));

  console.log(
    `✅ Exported ${contractName} to deployments/${network}/${timestamp}/`
  );
}

/**
 * Export multiple contract deployments at once (same session)
 */
export async function exportDeployments(
  hre: HardhatRuntimeEnvironment,
  deployments: Record<string, DeploymentExport>
): Promise<void> {
  const network = hre.network.name;
  const deploymentsDir = path.join(__dirname, "../../../deployments", network);

  // Use same timestamp for all contracts in this session
  const sessionTimestamp = Date.now();

  // Ensure deployments directory exists
  if (!fs.existsSync(deploymentsDir)) {
    fs.mkdirSync(deploymentsDir, { recursive: true });
  }

  // 1. Update addresses.json at root with all contracts
  const addressesFile = path.join(deploymentsDir, "addresses.json");
  let addresses: Record<string, string> = {};

  if (fs.existsSync(addressesFile)) {
    addresses = JSON.parse(fs.readFileSync(addressesFile, "utf-8"));
  }

  // Update addresses
  for (const [contractName, deployment] of Object.entries(deployments)) {
    addresses[contractName] = deployment.address;
  }

  fs.writeFileSync(addressesFile, JSON.stringify(addresses, null, 2));

  // 2. Create timestamped session folder
  const sessionDir = path.join(deploymentsDir, sessionTimestamp.toString());
  if (!fs.existsSync(sessionDir)) {
    fs.mkdirSync(sessionDir, { recursive: true });
  }

  // 3. Create individual contract JSON files in session folder
  for (const [contractName, deployment] of Object.entries(deployments)) {
    const contractFile = path.join(sessionDir, `${contractName}.json`);
    const contractData = {
      address: deployment.address,
      constructorArgs: deployment.constructorArgs || [],
      metadata: deployment.metadata || {},
    };

    fs.writeFileSync(contractFile, JSON.stringify(contractData, null, 2));
  }

  console.log(
    `✅ Exported ${Object.keys(deployments).length} contract(s) to deployments/${network}/${sessionTimestamp}/`
  );
}

/**
 * Read existing deployment addresses for a network
 */
export function loadDeploymentAddresses(
  network: string
): Record<string, string> {
  const deploymentsDir = path.join(__dirname, "../../../deployments", network);
  const addressesFile = path.join(deploymentsDir, "addresses.json");

  if (!fs.existsSync(addressesFile)) {
    return {};
  }

  return JSON.parse(fs.readFileSync(addressesFile, "utf-8"));
}

/**
 * Read a specific contract deployment
 */
export function loadDeployment(
  network: string,
  contractName: string
): DeploymentExport | null {
  const deploymentsDir = path.join(__dirname, "../../../deployments", network);
  const contractFile = path.join(deploymentsDir, `${contractName}.json`);

  if (!fs.existsSync(contractFile)) {
    return null;
  }

  return JSON.parse(fs.readFileSync(contractFile, "utf-8"));
}
