import fs from "fs";
import path from "path";
import { task } from "hardhat/config";
import type { HardhatRuntimeEnvironment } from "hardhat/types";
import type { Signer } from "ethers";
import {
  DeployableContract,
  AddressBook,
  TaskArgs,
  DeployConfig,
} from "./types";

/*//////////////////////////////////////////////////////////////
                              CONSTANTS
//////////////////////////////////////////////////////////////*/

const ALL_CONTRACTS: DeployableContract[] = [
  "Dust",
  "DustLock",
  "DustRewardsController",
  "UserVaultRegistry",
  "UserVaultImplementation",
  "UserVaultBeacon",
  "UserVaultFactory",
  "RevenueReward",
  "DustLockTransferStrategy",
  "NeverlandDustHelper",
  "NeverlandUiProvider",
];

/*//////////////////////////////////////////////////////////////
                        CONFIGURATION / PATHS
//////////////////////////////////////////////////////////////*/
const DEFAULT_CONFIG_PATH = path.resolve(__dirname, "config", "deploy.json");

/*//////////////////////////////////////////////////////////////
                             HELPERS
//////////////////////////////////////////////////////////////*/
const resolvePath = (maybePath: string): string =>
  path.isAbsolute(maybePath) ? maybePath : path.join(process.cwd(), maybePath);

const loadConfig = (configPath: string): DeployConfig => {
  if (!fs.existsSync(configPath)) {
    throw new Error(`Config file not found at ${configPath}`);
  }
  const raw = fs.readFileSync(configPath, "utf8");
  try {
    return JSON.parse(raw) as DeployConfig;
  } catch (error) {
    throw new Error(`Unable to parse config JSON: ${(error as Error).message}`);
  }
};

const requireConfigValue = (
  value: string | undefined,
  label: string
): string => {
  if (!value || value.trim() === "") {
    throw new Error(`Missing required config value for ${label}`);
  }
  return value;
};

const isValidAddress = (value?: string): value is string =>
  !!value && value.length === 42 && value.startsWith("0x");

const tryGetSigner = async (
  hre: HardhatRuntimeEnvironment,
  address: string,
  opts?: { dryRun?: boolean }
): Promise<Signer | null> => {
  try {
    return await hre.ethers.getSigner(address);
  } catch {}
  if (opts?.dryRun) {
    try {
      await hre.network.provider.request({
        method: "hardhat_impersonateAccount",
        params: [address],
      });
      return await hre.ethers.getSigner(address);
    } catch (impErr) {
      console.warn(
        `⚠️  Unable to impersonate signer for ${address}: ${
          (impErr as Error).message
        }`
      );
    }
  }
  console.warn(`⚠️  Unable to get signer for ${address}`);
  return null;
};

const getEnvWallet = (
  hre: HardhatRuntimeEnvironment,
  envVar: string
): Signer | null => {
  const pk = process.env[envVar];
  if (!pk || pk.trim() === "") return null;
  try {
    return new hre.ethers.Wallet(pk, hre.ethers.provider);
  } catch (e) {
    console.warn(`⚠️  Invalid private key in ${envVar}`);
    return null;
  }
};

/*//////////////////////////////////////////////////////////////
                       GAS REPORTING HELPERS
//////////////////////////////////////////////////////////////*/
type GasEntry = {
  label: string;
  from: string;
  gasUsed: bigint;
  gasPrice: bigint;
  costWei: bigint;
};

const formatEther = (hre: HardhatRuntimeEnvironment, wei: bigint): string =>
  hre.ethers.formatEther(wei);
const formatGwei = (hre: HardhatRuntimeEnvironment, wei: bigint): string =>
  hre.ethers.formatUnits(wei, "gwei");

const reportTx = async (
  hre: HardhatRuntimeEnvironment,
  tx: any,
  label: string,
  gasLog: GasEntry[]
): Promise<void> => {
  if (!tx) return;
  const receipt = await tx.wait();
  const gasUsed: bigint = receipt.gasUsed ?? BigInt(0);
  const gasPrice: bigint =
    receipt.effectiveGasPrice ?? receipt.gasPrice ?? BigInt(0);
  const costWei = gasUsed * gasPrice;
  const from: string = (receipt.from ?? tx.from ?? "").toString();
  gasLog.push({ label, from, gasUsed, gasPrice, costWei });
  console.log(
    `   ⛽ ${label}: gas=${gasUsed.toString()} price=${formatGwei(
      hre,
      gasPrice
    )} gwei cost=${formatEther(hre, costWei)} MON`
  );
};

const reportDeployment = async (
  hre: HardhatRuntimeEnvironment,
  contract: any,
  label: string,
  gasLog: GasEntry[]
): Promise<void> => {
  try {
    const depTx =
      typeof contract.deploymentTransaction === "function"
        ? contract.deploymentTransaction()
        : null;
    if (depTx) {
      await reportTx(hre, depTx, label, gasLog);
    }
  } catch (_) {
    // best-effort only
  }
};

const verifyContract = async (
  hre: HardhatRuntimeEnvironment,
  address: string,
  constructorArgs: any[] = [],
  contractName?: string,
  dryRun: boolean = false
): Promise<void> => {
  if (dryRun) {
    console.log(`   🔍 Skipping verification in dry-run mode for ${address}`);
    return;
  }

  try {
    console.log(`   🔍 Verifying contract at ${address}...`);
    const verifyArgs: any = {
      address,
      constructorArguments: constructorArgs,
    };

    if (contractName) {
      verifyArgs.contract = contractName;
    }

    await hre.run("verify:verify", verifyArgs);
    console.log(`   ✅ Contract verified successfully!`);
  } catch (error: any) {
    if (error.message?.includes("already verified")) {
      console.log(`   ✅ Contract already verified`);
    } else {
      console.log(`   ⚠️  Verification failed: ${error.message}`);
    }
  }
};

/*//////////////////////////////////////////////////////////////
                       MAIN DEPLOYMENT LOGIC
//////////////////////////////////////////////////////////////*/
const deployNeverland = async (
  hre: HardhatRuntimeEnvironment,
  configPath: string,
  exclude: Set<DeployableContract>,
  dryRun: boolean
): Promise<void> => {
  console.log(`📄 Using config: ${configPath}`);

  // Ensure clean compilation for consistent bytecode
  if (!dryRun) {
    console.log(
      "🔧 Ensuring clean compilation for verification compatibility..."
    );
    await hre.run("compile", { force: true });
  }

  // Validate dry-run mode requirements
  if (dryRun) {
    if (hre.network.name !== "hardhat") {
      throw new Error(
        `🚨 DRY-RUN SAFETY ERROR: Dry-run mode can only be used with --network hardhat (forked local network).\n` +
          `You specified --network ${hre.network.name} which would deploy to the real network!\n` +
          `Use: npx hardhat deploy:neverland --dry-run (without --network flag)\n` +
          `Or: npx hardhat deploy:neverland --dry-run --network hardhat`
      );
    }
    console.log(
      "🚧 Dry-run mode: deploying to forked state under snapshot; will revert"
    );
  }

  // Take snapshot for dry-run to deploy on fork and revert
  let snapshotId: string | undefined;
  if (dryRun) {
    try {
      snapshotId = await hre.network.provider.send("evm_snapshot", []);
      console.log("📸 Network snapshot taken");
    } catch (error) {
      throw new Error(
        "🚨 DRY-RUN SAFETY ERROR: Could not take snapshot. Dry-run requires a local forked network."
      );
    }
  }

  const config = loadConfig(configPath);
  const configAddresses = config.addresses ?? {};

  const addresses: AddressBook = {};
  const implementations: Partial<Record<DeployableContract, string>> = {};
  let proxyAdminAddress: string | undefined;
  const pendingActions: string[] = [];
  const gasLog: GasEntry[] = [];

  const requireExistingAddress = (
    name: DeployableContract,
    reason: string
  ): string => {
    const value = configAddresses[name];
    if (!isValidAddress(value)) {
      throw new Error(
        `Missing or invalid address for ${name} ${reason}. Please provide it in config.addresses.${name}`
      );
    }
    return value;
  };

  const recordAddress = (name: DeployableContract, address: string): void => {
    addresses[name] = address;
  };

  const recordProxyInfo = async (
    name: DeployableContract,
    proxyAddr: string
  ): Promise<void> => {
    try {
      const impl = await hre.upgrades.erc1967.getImplementationAddress(
        proxyAddr
      );
      implementations[name] = impl;
    } catch (e) {
      console.warn(
        `⚠️  Could not fetch implementation for ${name} at ${proxyAddr}`
      );
    }
    try {
      const admin = await hre.upgrades.erc1967.getAdminAddress(proxyAddr);
      if (!proxyAdminAddress) proxyAdminAddress = admin;
      else if (proxyAdminAddress.toLowerCase() !== admin.toLowerCase()) {
        console.warn(
          `⚠️  Multiple ProxyAdmin addresses detected: ${proxyAdminAddress} vs ${admin}`
        );
      }
    } catch (e) {
      console.warn(`⚠️  Could not fetch admin for ${name} at ${proxyAddr}`);
    }
  };

  const getRecordedAddress = (name: DeployableContract): string => {
    const addr = addresses[name] ?? configAddresses[name];
    if (!addr) {
      throw new Error(
        `Address for ${name} unavailable. Provide it under config.addresses.${name} or deploy it in this run.`
      );
    }
    return addr;
  };

  // Ensure excluded contracts have addresses supplied and record them up-front.
  for (const name of exclude) {
    const addr = requireExistingAddress(
      name,
      "because it is excluded via --exclude."
    );
    recordAddress(name, addr);
  }

  const [deployer] = await hre.ethers.getSigners();
  const deployerAddress = await deployer.getAddress();
  console.log(`👤 Deployer: ${deployerAddress}`);

  // 1. Deploy Dust (proxy)
  if (!exclude.has("Dust")) {
    const dustOwner = deployerAddress;
    const totalSupplyRaw = requireConfigValue(
      config.dust?.totalSupply,
      "dust.totalSupply"
    );
    const totalSupply = BigInt(totalSupplyRaw);

    console.log("\n⛏️  Deploying Dust (proxy)...");
    const dustFactory = await hre.ethers.getContractFactory("Dust");
    const dust = await hre.upgrades.deployProxy(
      dustFactory,
      [dustOwner, totalSupply],
      {
        initializer: "initialize",
        kind: "transparent",
      }
    );
    await dust.waitForDeployment();
    const dustAddress = await dust.getAddress();
    recordAddress("Dust", dustAddress);
    console.log(`✅ Dust deployed at ${dustAddress}`);
    await reportDeployment(hre, dust, "Deploy Dust (proxy)", gasLog);
    await recordProxyInfo("Dust", dustAddress);

    // Verify Dust implementation
    const dustImpl = await hre.upgrades.erc1967.getImplementationAddress(
      dustAddress
    );
    await verifyContract(hre, dustImpl, [], "src/tokens/Dust.sol:Dust", dryRun);
  } else {
    const existingDust = getRecordedAddress("Dust");
    console.log(
      `\n⏭️  Skipping Dust deployment (excluded). Using provided Dust at ${existingDust}.`
    );
  }

  // 2. Deploy DustLock (proxy + library)
  if (!exclude.has("DustLock")) {
    const forwarder = requireConfigValue(
      config.dustLock?.forwarder,
      "dustLock.forwarder"
    );
    const baseURI = requireConfigValue(
      config.dustLock?.baseURI,
      "dustLock.baseURI"
    );
    const dustAddress = getRecordedAddress("Dust");

    console.log("\n⛏️  Deploying BalanceLogicLibrary...");
    const balanceLibFactory = await hre.ethers.getContractFactory(
      "BalanceLogicLibrary"
    );
    const balanceLib = await balanceLibFactory.deploy();
    await balanceLib.waitForDeployment();
    const balanceLibAddress = await balanceLib.getAddress();
    console.log(`✅ BalanceLogicLibrary deployed at ${balanceLibAddress}`);
    await reportDeployment(
      hre,
      balanceLib,
      "Deploy BalanceLogicLibrary",
      gasLog
    );

    console.log("⛏️  Deploying DustLock (proxy)...");
    const dustLockFactory = await hre.ethers.getContractFactory("DustLock", {
      libraries: { BalanceLogicLibrary: balanceLibAddress },
    });
    const dustLock = await hre.upgrades.deployProxy(
      dustLockFactory,
      [forwarder, dustAddress, baseURI],
      {
        initializer: "initialize",
        kind: "transparent",
        unsafeAllowLinkedLibraries: true,
        constructorArgs: [forwarder],
        unsafeAllow: ["constructor"],
      }
    );
    await dustLock.waitForDeployment();
    const dustLockAddress = await dustLock.getAddress();
    recordAddress("DustLock", dustLockAddress);
    console.log(`✅ DustLock deployed at ${dustLockAddress}`);
    await reportDeployment(hre, dustLock, "Deploy DustLock (proxy)", gasLog);
    await recordProxyInfo("DustLock", dustLockAddress);

    // Verify DustLock implementation
    const dustLockImpl = await hre.upgrades.erc1967.getImplementationAddress(
      dustLockAddress
    );
    await verifyContract(
      hre,
      dustLockImpl,
      [forwarder],
      "src/tokens/DustLock.sol:DustLock",
      dryRun
    );

    // Configuration steps
    if (config.dustLock?.earlyWithdrawTreasury) {
      const treasuryAddress = config.dustLock.earlyWithdrawTreasury;
      const currentTreasury = await dustLock.earlyWithdrawTreasury();
      if (treasuryAddress.toLowerCase() !== currentTreasury.toLowerCase()) {
        console.log(
          `⚙️  Setting early withdraw treasury to ${treasuryAddress}...`
        );
        const tx = await dustLock.setEarlyWithdrawTreasury(treasuryAddress);
        await reportTx(hre, tx, "DustLock.setEarlyWithdrawTreasury", gasLog);
        console.log("✅ Early withdraw treasury updated.");
      }
    }

    if (config.dustLock?.minLockAmount) {
      const desiredMinLock = BigInt(config.dustLock.minLockAmount);
      const currentMinLock = await dustLock.minLockAmount();
      if (currentMinLock !== desiredMinLock) {
        console.log(
          `⚙️  Updating min lock amount to ${desiredMinLock.toString()}...`
        );
        const tx = await dustLock.setMinLockAmount(desiredMinLock);
        await reportTx(hre, tx, "DustLock.setMinLockAmount", gasLog);
        console.log("✅ Min lock amount updated.");
      }
    }
  } else {
    const existingDustLock = getRecordedAddress("DustLock");
    console.log(
      `\n⏭️  Skipping DustLock deployment (excluded). Using provided DustLock at ${existingDustLock}.`
    );
  }

  // 3. Deploy DustRewardsController (proxy)
  if (!exclude.has("DustRewardsController")) {
    const emissionManager = deployerAddress;

    console.log("\n⛏️  Deploying DustRewardsController (proxy)...");
    const controllerFactory = await hre.ethers.getContractFactory(
      "DustRewardsController"
    );
    const controller = await hre.upgrades.deployProxy(controllerFactory, [], {
      initializer: false,
      kind: "transparent",
      constructorArgs: [emissionManager],
      unsafeAllow: [
        "constructor",
        "state-variable-immutable",
        "state-variable-assignment",
        "missing-initializer",
      ],
    });
    await controller.waitForDeployment();
    const controllerAddress = await controller.getAddress();
    recordAddress("DustRewardsController", controllerAddress);
    console.log(`✅ DustRewardsController deployed at ${controllerAddress}`);
    await reportDeployment(
      hre,
      controller,
      "Deploy DustRewardsController (proxy)",
      gasLog
    );
    await recordProxyInfo("DustRewardsController", controllerAddress);

    // Verify DustRewardsController implementation
    const controllerImpl = await hre.upgrades.erc1967.getImplementationAddress(
      controllerAddress
    );
    await verifyContract(
      hre,
      controllerImpl,
      [emissionManager],
      "src/emissions/DustRewardsController.sol:DustRewardsController",
      dryRun
    );
  } else {
    const existingController = getRecordedAddress("DustRewardsController");
    console.log(
      `\n⏭️  Skipping DustRewardsController deployment (excluded). Using provided controller at ${existingController}.`
    );
  }

  // 4. Deploy UserVaultRegistry
  if (!exclude.has("UserVaultRegistry")) {
    const registryConfig = config.selfRepaying?.registry;
    if (!registryConfig) {
      throw new Error("Missing selfRepaying.registry configuration block.");
    }

    const executorAddress = requireConfigValue(
      registryConfig.executor,
      "selfRepaying.registry.executor"
    );
    if (!isValidAddress(executorAddress)) {
      throw new Error(`Invalid executor address provided: ${executorAddress}`);
    }

    const maxSlippageRaw = requireConfigValue(
      registryConfig.maxSwapSlippageBps,
      "selfRepaying.registry.maxSwapSlippageBps"
    );
    const maxSlippage = BigInt(maxSlippageRaw);

    const supportedAggregators = registryConfig.supportedAggregators ?? [];
    for (const aggregator of supportedAggregators) {
      if (!isValidAddress(aggregator)) {
        throw new Error(`Invalid aggregator address provided: ${aggregator}`);
      }
    }

    {
      console.log("\n⛏️  Deploying UserVaultRegistry...");
      const registryFactory = await hre.ethers.getContractFactory(
        "UserVaultRegistry"
      );
      const registry = await registryFactory.deploy();
      await registry.waitForDeployment();
      const registryAddress = await registry.getAddress();
      recordAddress("UserVaultRegistry", registryAddress);
      console.log(`✅ UserVaultRegistry deployed at ${registryAddress}`);
      await reportDeployment(hre, registry, "Deploy UserVaultRegistry", gasLog);

      const currentExecutor = await registry.executor();
      if (currentExecutor.toLowerCase() !== executorAddress.toLowerCase()) {
        console.log(
          `⚙️  Setting UserVaultRegistry executor to ${executorAddress}...`
        );
        const tx = await registry.setExecutor(executorAddress);
        await reportTx(hre, tx, "UserVaultRegistry.setExecutor", gasLog);
        console.log("✅ Executor updated.");
      }

      const currentMaxSlippage = await registry.maxSwapSlippageBps();
      if (currentMaxSlippage !== maxSlippage) {
        console.log(
          `⚙️  Updating max swap slippage to ${maxSlippageRaw} bps...`
        );
        const tx = await registry.setMaxSwapSlippageBps(maxSlippage);
        await reportTx(
          hre,
          tx,
          "UserVaultRegistry.setMaxSwapSlippageBps",
          gasLog
        );
        console.log("✅ Max swap slippage updated.");
      }

      for (const aggregator of supportedAggregators) {
        const active = await registry.isSupportedAggregator(aggregator);
        if (!active) {
          console.log(`⚙️  Enabling aggregator ${aggregator}...`);
          const tx = await registry.setSupportedAggregators(aggregator, true);
          await reportTx(
            hre,
            tx,
            `UserVaultRegistry.setSupportedAggregators(${aggregator})`,
            gasLog
          );
          console.log("✅ Aggregator enabled.");
        }
      }
    }
  } else {
    const existingRegistry = getRecordedAddress("UserVaultRegistry");
    console.log(
      `\n⏭️  Skipping UserVaultRegistry deployment (excluded). Using provided registry at ${existingRegistry}.`
    );
  }

  // 5. Deploy UserVault implementation
  if (!exclude.has("UserVaultImplementation")) {
    console.log("\n⛏️  Deploying UserVault implementation...");
    const userVaultImplFactory = await hre.ethers.getContractFactory(
      "UserVault"
    );
    const userVaultImpl = await userVaultImplFactory.deploy();
    await userVaultImpl.waitForDeployment();
    const userVaultImplAddress = await userVaultImpl.getAddress();
    recordAddress("UserVaultImplementation", userVaultImplAddress);
    console.log(
      `✅ UserVault implementation deployed at ${userVaultImplAddress}`
    );
    await reportDeployment(
      hre,
      userVaultImpl,
      "Deploy UserVault Implementation",
      gasLog
    );
  } else {
    const existingImplementation = getRecordedAddress(
      "UserVaultImplementation"
    );
    console.log(
      `\n⏭️  Skipping UserVault implementation deployment (excluded). Using provided implementation at ${existingImplementation}.`
    );
  }

  // 6. Deploy UserVault UpgradeableBeacon
  if (!exclude.has("UserVaultBeacon")) {
    const beaconOwner = deployerAddress;
    const userVaultImplementationAddress = getRecordedAddress(
      "UserVaultImplementation"
    );

    console.log("\n⛏️  Deploying UserVault UpgradeableBeacon...");
    const beaconFactory = await hre.ethers.getContractFactory(
      "UpgradeableBeacon"
    );
    const beacon = await beaconFactory.deploy(userVaultImplementationAddress);
    await beacon.waitForDeployment();
    const beaconAddress = await beacon.getAddress();
    recordAddress("UserVaultBeacon", beaconAddress);
    console.log(`✅ UserVault beacon deployed at ${beaconAddress}`);
    await reportDeployment(
      hre,
      beacon,
      "Deploy UserVault UpgradeableBeacon",
      gasLog
    );

    if (
      beaconOwner.toLowerCase() !== (await deployer.getAddress()).toLowerCase()
    ) {
      console.log(`⚙️  Transferring beacon ownership to ${beaconOwner}...`);
      const beaconContract = await hre.ethers.getContractAt(
        "UpgradeableBeacon",
        beaconAddress,
        deployer
      );
      const tx = await beaconContract.transferOwnership(beaconOwner);
      await reportTx(hre, tx, "UserVaultBeacon.transferOwnership", gasLog);
      console.log("✅ Beacon ownership transferred.");
    }
  } else {
    const existingBeacon = getRecordedAddress("UserVaultBeacon");
    console.log(
      `\n⏭️  Skipping UserVault beacon deployment (excluded). Using provided beacon at ${existingBeacon}.`
    );
  }

  // 7. Deploy UserVaultFactory (proxy, uninitialized)
  if (!exclude.has("UserVaultFactory")) {
    const poolAddressesProviderRegistry = requireConfigValue(
      config.selfRepaying?.poolAddressesProviderRegistry,
      "selfRepaying.poolAddressesProviderRegistry"
    );
    if (!isValidAddress(poolAddressesProviderRegistry)) {
      throw new Error(
        `Invalid poolAddressesProviderRegistry address provided: ${poolAddressesProviderRegistry}`
      );
    }

    console.log("\n⛏️  Deploying UserVaultFactory (proxy, uninitialized)...");
    const factoryFactory = await hre.ethers.getContractFactory(
      "UserVaultFactory"
    );
    const userVaultFactory = await hre.upgrades.deployProxy(
      factoryFactory,
      [],
      {
        initializer: false,
        kind: "transparent",
        unsafeAllow: ["missing-initializer"],
      }
    );
    await userVaultFactory.waitForDeployment();
    const userVaultFactoryAddress = await userVaultFactory.getAddress();
    recordAddress("UserVaultFactory", userVaultFactoryAddress);
    console.log(
      `✅ UserVaultFactory (proxy) deployed at ${userVaultFactoryAddress}`
    );
    await reportDeployment(
      hre,
      userVaultFactory,
      "Deploy UserVaultFactory (proxy)",
      gasLog
    );
    await recordProxyInfo("UserVaultFactory", userVaultFactoryAddress);
  } else {
    const existingFactory = getRecordedAddress("UserVaultFactory");
    console.log(
      `\n⏭️  Skipping UserVaultFactory deployment (excluded). Using provided factory at ${existingFactory}.`
    );
  }

  // 8. Deploy RevenueReward (proxy)
  if (!exclude.has("RevenueReward")) {
    const forwarder = requireConfigValue(
      config.revenueReward?.forwarder,
      "revenueReward.forwarder"
    );
    const distributor = requireConfigValue(
      config.revenueReward?.distributor,
      "revenueReward.distributor"
    );
    const dustLockAddress = getRecordedAddress("DustLock");
    const userVaultFactoryAddress = getRecordedAddress("UserVaultFactory");
    const userVaultBeaconAddress = getRecordedAddress("UserVaultBeacon");
    const userVaultRegistryAddress = getRecordedAddress("UserVaultRegistry");
    const poolAddressesProviderRegistry =
      config.selfRepaying?.poolAddressesProviderRegistry;

    if (!exclude.has("UserVaultFactory")) {
      requireConfigValue(
        poolAddressesProviderRegistry,
        "selfRepaying.poolAddressesProviderRegistry"
      );
    }

    console.log("\n⛏️  Deploying RevenueReward (proxy)...");
    const revenueRewardFactory = await hre.ethers.getContractFactory(
      "RevenueReward"
    );
    const revenueReward = await hre.upgrades.deployProxy(
      revenueRewardFactory,
      [forwarder, dustLockAddress, distributor, userVaultFactoryAddress],
      {
        initializer: "initialize",
        kind: "transparent",
        constructorArgs: [forwarder],
        unsafeAllow: ["constructor"],
      }
    );
    await revenueReward.waitForDeployment();
    const revenueRewardAddress = await revenueReward.getAddress();
    recordAddress("RevenueReward", revenueRewardAddress);
    console.log(`✅ RevenueReward deployed at ${revenueRewardAddress}`);
    await reportDeployment(
      hre,
      revenueReward,
      "Deploy RevenueReward (proxy)",
      gasLog
    );
    await recordProxyInfo("RevenueReward", revenueRewardAddress);

    // Verify RevenueReward implementation
    const revenueRewardImpl =
      await hre.upgrades.erc1967.getImplementationAddress(revenueRewardAddress);
    await verifyContract(
      hre,
      revenueRewardImpl,
      [forwarder],
      "src/rewards/RevenueReward.sol:RevenueReward",
      dryRun
    );

    console.log("⚙️  Linking DustLock -> RevenueReward...");
    const dustLock = await hre.ethers.getContractAt(
      "DustLock",
      dustLockAddress,
      deployer
    );
    const tx = await dustLock.setRevenueReward(revenueRewardAddress);
    await reportTx(hre, tx, "DustLock.setRevenueReward", gasLog);
    console.log("✅ DustLock revenue reward configured.");

    if (!exclude.has("UserVaultFactory")) {
      const poolRegistryAddress = requireConfigValue(
        poolAddressesProviderRegistry,
        "selfRepaying.poolAddressesProviderRegistry"
      );
      if (!isValidAddress(poolRegistryAddress)) {
        throw new Error(
          `Invalid poolAddressesProviderRegistry address provided: ${poolRegistryAddress}`
        );
      }
      const userVaultFactory = await hre.ethers.getContractAt(
        "UserVaultFactory",
        userVaultFactoryAddress,
        deployer
      );
      const currentRegistry = await userVaultFactory.userVaultRegistry();
      if (currentRegistry === hre.ethers.ZeroAddress) {
        console.log("⚙️  Initializing UserVaultFactory...");
        const initTx = await userVaultFactory.initialize(
          userVaultBeaconAddress,
          userVaultRegistryAddress,
          poolRegistryAddress,
          revenueRewardAddress
        );
        await reportTx(hre, initTx, "UserVaultFactory.initialize", gasLog);
        console.log("✅ UserVaultFactory initialized.");
      } else {
        console.log(
          "ℹ️  UserVaultFactory already initialized; skipping initialization."
        );
      }
    }
  } else {
    const existingRevenueReward = getRecordedAddress("RevenueReward");
    console.log(
      `\n⏭️  Skipping RevenueReward deployment (excluded). Using provided contract at ${existingRevenueReward}.`
    );
  }

  // 9. Deploy DustLockTransferStrategy
  if (!exclude.has("DustLockTransferStrategy")) {
    const rewardsAdmin = requireConfigValue(
      config.transferStrategy?.rewardsAdmin,
      "transferStrategy.rewardsAdmin"
    );
    const dustVaultWallet = getEnvWallet(hre, "DUST_VAULT_PRIVATE_KEY");
    const dustVault = dustVaultWallet
      ? await dustVaultWallet.getAddress()
      : requireConfigValue(
          config.transferStrategy?.dustVault,
          "transferStrategy.dustVault"
        );
    const dustLockAddress = getRecordedAddress("DustLock");
    const controllerAddress = getRecordedAddress("DustRewardsController");
    const incentivesController =
      config.transferStrategy?.incentivesControllerOverride ??
      controllerAddress;
    const emissionManager = deployerAddress;
    const dustAddress = getRecordedAddress("Dust");
    console.log("\n⛏️  Deploying DustLockTransferStrategy...");
    const strategyFactory = await hre.ethers.getContractFactory(
      "DustLockTransferStrategy"
    );
    const strategy = await strategyFactory.deploy(
      incentivesController,
      rewardsAdmin,
      dustVault,
      dustLockAddress
    );
    await strategy.waitForDeployment();
    const strategyAddress = await strategy.getAddress();
    recordAddress("DustLockTransferStrategy", strategyAddress);
    console.log(`✅ DustLockTransferStrategy deployed at ${strategyAddress}`);
    await reportDeployment(
      hre,
      strategy,
      "Deploy DustLockTransferStrategy",
      gasLog
    );

    const rewardsController = await hre.ethers.getContractAt(
      "DustRewardsController",
      controllerAddress,
      deployer
    );
    const emissionManagerSigner =
      emissionManager.toLowerCase() ===
      (await deployer.getAddress()).toLowerCase()
        ? deployer
        : await tryGetSigner(hre, emissionManager, { dryRun });

    if (emissionManagerSigner) {
      console.log(
        "⚙️  Registering transfer strategy with DustRewardsController..."
      );
      try {
        const tx = await (rewardsController as any)
          .connect(emissionManagerSigner)
          .setTransferStrategy(dustAddress, strategyAddress);
        await reportTx(
          hre,
          tx,
          "DustRewardsController.setTransferStrategy",
          gasLog
        );
        console.log("✅ Transfer strategy registered.");
      } catch (err) {
        console.warn(
          "⚠️  Could not register transfer strategy now. Deferring as a pending action."
        );
        pendingActions.push(
          `Call DustRewardsController.setTransferStrategy(${dustAddress}, ${strategyAddress}) from emission manager ${emissionManager}.`
        );
      }
    } else {
      pendingActions.push(
        `Call DustRewardsController.setTransferStrategy(${dustAddress}, ${strategyAddress}) from emission manager ${emissionManager}.`
      );
    }

    const dust = await hre.ethers.getContractAt("Dust", dustAddress, deployer);
    const currentAllowance = await dust.allowance(dustVault, strategyAddress);
    if (currentAllowance === hre.ethers.MaxUint256) {
      console.log(
        "✅ DUST vault already approved strategy with MaxUint allowance."
      );
    } else {
      const vaultSigner = dustVaultWallet
        ? dustVaultWallet
        : dustVault.toLowerCase() ===
          (await deployer.getAddress()).toLowerCase()
        ? deployer
        : await tryGetSigner(hre, dustVault, { dryRun });
      if (vaultSigner) {
        console.log("⚙️  Approving DUST vault allowance for strategy...");
        try {
          const approveTx = await (dust.connect(vaultSigner) as any).approve(
            strategyAddress,
            hre.ethers.MaxUint256
          );
          await reportTx(hre, approveTx, "DUST.approve(MaxUint256)", gasLog);
          const updatedAllowance = await dust.allowance(
            dustVault,
            strategyAddress
          );
          if (updatedAllowance === hre.ethers.MaxUint256) {
            console.log("✅ DUST vault approval set to MaxUint256.");
          } else {
            pendingActions.push(
              `Verify DUST allowance: expected MaxUint256 for vault ${dustVault} -> strategy ${strategyAddress}.`
            );
          }
        } catch (err) {
          console.warn(
            "⚠️  Could not set DUST vault approval now. Deferring as a pending action."
          );
          pendingActions.push(
            `Approve DUST vault allowance manually: Dust(${dustAddress}).approve(${strategyAddress}, MaxUint256) from vault ${dustVault}.`
          );
        }
      } else {
        pendingActions.push(
          `Approve DUST vault allowance manually: Dust(${dustAddress}).approve(${strategyAddress}, MaxUint256) from vault ${dustVault}.`
        );
      }
    }
  } else {
    const existingStrategy = getRecordedAddress("DustLockTransferStrategy");
    console.log(
      `\n⏭️  Skipping DustLockTransferStrategy deployment (excluded). Using provided strategy at ${existingStrategy}.`
    );
  }

  // 10. Deploy NeverlandDustHelper
  if (!exclude.has("NeverlandDustHelper")) {
    const dustAddress = getRecordedAddress("Dust");
    const owner = deployerAddress;
    const uniswapPair = config.dustHelper?.uniswapPair;
    if (uniswapPair && !isValidAddress(uniswapPair)) {
      throw new Error(
        `Invalid dustHelper.uniswapPair address provided: ${uniswapPair}`
      );
    }

    console.log("\n⛏️  Deploying NeverlandDustHelper...");
    const helperFactory = await hre.ethers.getContractFactory(
      "NeverlandDustHelper"
    );
    const helper = await helperFactory.deploy(dustAddress, owner);
    await helper.waitForDeployment();
    const helperAddress = await helper.getAddress();
    recordAddress("NeverlandDustHelper", helperAddress);
    console.log(`✅ NeverlandDustHelper deployed at ${helperAddress}`);
    await reportDeployment(hre, helper, "Deploy NeverlandDustHelper", gasLog);

    // Verify NeverlandDustHelper
    await verifyContract(
      hre,
      helperAddress,
      [dustAddress, owner],
      "src/helpers/NeverlandDustHelper.sol:NeverlandDustHelper",
      dryRun
    );

    if (uniswapPair) {
      const currentOwner = await helper.owner();
      const desiredPair = uniswapPair;
      const ownerSigner =
        currentOwner.toLowerCase() ===
        (await deployer.getAddress()).toLowerCase()
          ? deployer
          : await tryGetSigner(hre, currentOwner, { dryRun });

      if (ownerSigner) {
        const helperWithOwner = helper.connect(ownerSigner);
        console.log(
          `⚙️  Setting NeverlandDustHelper Uniswap pair to ${desiredPair}...`
        );
        try {
          const tx = await (helperWithOwner as any).setUniswapPair(desiredPair);
          await reportTx(hre, tx, "NeverlandDustHelper.setUniswapPair", gasLog);
          console.log("✅ Uniswap pair configured.");
        } catch (err) {
          console.warn(
            "⚠️  Could not set Uniswap pair now. Deferring as a pending action."
          );
          pendingActions.push(
            `Call NeverlandDustHelper.setUniswapPair(${desiredPair}) from owner ${currentOwner}.`
          );
        }
      } else {
        pendingActions.push(
          `Call NeverlandDustHelper.setUniswapPair(${desiredPair}) from owner ${currentOwner}.`
        );
      }
    }
  } else {
    const existingHelper = getRecordedAddress("NeverlandDustHelper");
    console.log(
      `\n⏭️  Skipping NeverlandDustHelper deployment (excluded). Using provided helper at ${existingHelper}.`
    );
  }

  // 11. Deploy NeverlandUiProvider
  if (!exclude.has("NeverlandUiProvider")) {
    const dustLockAddress = getRecordedAddress("DustLock");
    const revenueRewardAddress = getRecordedAddress("RevenueReward");
    const controllerAddress = getRecordedAddress("DustRewardsController");
    const dustOracleAddress = getRecordedAddress("NeverlandDustHelper");
    const aaveProvider = requireConfigValue(
      config.uiProvider?.aaveLendingPoolAddressProvider,
      "uiProvider.aaveLendingPoolAddressProvider"
    );
    console.log("\n⛏️  Deploying NeverlandUiProvider...");
    const uiFactory = await hre.ethers.getContractFactory(
      "NeverlandUiProvider"
    );
    const uiProvider = await uiFactory.deploy(
      dustLockAddress,
      revenueRewardAddress,
      controllerAddress,
      dustOracleAddress,
      aaveProvider
    );
    await uiProvider.waitForDeployment();
    const uiAddress = await uiProvider.getAddress();
    recordAddress("NeverlandUiProvider", uiAddress);
    console.log(`✅ NeverlandUiProvider deployed at ${uiAddress}`);
    await reportDeployment(
      hre,
      uiProvider,
      "Deploy NeverlandUiProvider",
      gasLog
    );

    // Verify NeverlandUiProvider
    await verifyContract(
      hre,
      uiAddress,
      [
        dustLockAddress,
        revenueRewardAddress,
        controllerAddress,
        dustOracleAddress,
        aaveProvider,
      ],
      "src/ui/NeverlandUiProvider.sol:NeverlandUiProvider",
      dryRun
    );
  } else {
    const existingUi = getRecordedAddress("NeverlandUiProvider");
    console.log(
      `\n⏭️  Skipping NeverlandUiProvider deployment (excluded). Using provided UI provider at ${existingUi}.`
    );
  }

  // Summary and cleanup
  console.log("\n================ Deployment Summary ================");
  const summaryRows = ALL_CONTRACTS.map((name) => ({
    contract: name,
    address: (addresses[name] ??
      configAddresses[name] ??
      "(not deployed / not provided)") as string,
  }));
  console.table(summaryRows);

  // Write deployments folder with metadata for deployed contracts
  try {
    const net = await hre.ethers.provider.getNetwork();
    const networkName = hre.network.name;
    const chainId = Number(net.chainId || 0);
    const deploymentsRoot = path.resolve(
      process.cwd(),
      "deployments",
      networkName
    );
    fs.mkdirSync(deploymentsRoot, { recursive: true });

    // addresses.json mapping
    const addressBook: Record<string, string> = {};
    for (const name of ALL_CONTRACTS) {
      const addr = addresses[name] ?? configAddresses[name];
      if (addr) addressBook[name] = addr;
    }
    const implBook: Record<string, string> = {};
    for (const [name, impl] of Object.entries(implementations)) {
      if (impl) implBook[name] = impl as string;
    }
    const addressesJson = {
      networkName,
      chainId,
      addresses: addressBook,
      implementations: implBook,
      proxyAdmin: proxyAdminAddress ?? null,
    };
    fs.writeFileSync(
      path.join(deploymentsRoot, "addresses.json"),
      JSON.stringify(addressesJson, null, 2)
    );

    const writtenRows: Array<{ contract: string; file: string }> = [];

    // Helper: resolve Hardhat metadata JSON for a contract by name
    const getHardhatMetadata = async (
      contractName: string
    ): Promise<any | null> => {
      try {
        // Try via artifacts to learn the sourceName then fetch build info
        const artifact = await hre.artifacts.readArtifact(
          contractName as string
        );
        const fqName = `${artifact.sourceName}:${artifact.contractName}`;
        const buildInfo = await hre.artifacts.getBuildInfo(fqName);
        if (buildInfo) {
          const metaStr = (buildInfo as any).output?.contracts?.[
            artifact.sourceName
          ]?.[artifact.contractName]?.metadata;
          if (metaStr) return JSON.parse(metaStr);
        }
      } catch (_) {
        // Fallback: exhaustive scan
        try {
          const biDir = path.resolve(process.cwd(), "artifacts", "build-info");
          const files = fs
            .readdirSync(biDir)
            .filter((f) => f.endsWith(".json"));
          for (const f of files) {
            const bi = JSON.parse(fs.readFileSync(path.join(biDir, f), "utf8"));
            const contracts = bi.output?.contracts || {};
            for (const [src, table] of Object.entries(contracts) as Array<
              [string, any]
            >) {
              if (
                table &&
                table[contractName] &&
                table[contractName].metadata
              ) {
                return JSON.parse(table[contractName].metadata);
              }
              // Some compilers key by contract within the source
              const inner = table && table[contractName as any];
              if (inner?.metadata) return JSON.parse(inner.metadata);
            }
          }
        } catch (_) {}
      }
      return null;
    };
    for (const [name, addr] of Object.entries(addresses)) {
      if (!addr) continue;
      // Resolve Hardhat metadata used for deployment from build-info
      const metaObj = await getHardhatMetadata(name);
      if (!metaObj) {
        console.warn(
          `⚠️  Metadata not found for ${name} in artifacts/build-info`
        );
      }
      const isProxied =
        implementations[name as DeployableContract] !== undefined;
      const content: any = {
        networkName,
        chainId,
        contract: name,
        ...(metaObj ? { metadata: metaObj } : {}),
      };
      if (isProxied) {
        content.proxy = addr;
        content.implementation = implementations[name as DeployableContract];
        if (proxyAdminAddress) content.proxyAdmin = proxyAdminAddress;
      } else {
        content.address = addr;
      }
      const outFile = path.join(deploymentsRoot, `${name}.json`);
      fs.writeFileSync(outFile, JSON.stringify(content, null, 2));
      writtenRows.push({
        contract: name,
        file: `deployments/${networkName}/${name}.json`,
      });
    }
    // Write proxy admin info if available (with metadata)
    if (proxyAdminAddress) {
      const adminFile = path.join(deploymentsRoot, `ProxyAdmin.json`);
      let adminMeta: any = null;
      try {
        // Try to get ProxyAdmin metadata from build-info
        const biDir = path.resolve(process.cwd(), "artifacts", "build-info");
        const files = fs.existsSync(biDir)
          ? fs.readdirSync(biDir).filter((f) => f.endsWith(".json"))
          : [];
        for (const f of files) {
          const bi = JSON.parse(fs.readFileSync(path.join(biDir, f), "utf8"));
          const entry =
            bi.output?.contracts?.[
              "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol"
            ]?.ProxyAdmin;
          if (entry?.metadata) {
            adminMeta = JSON.parse(entry.metadata);
            break;
          }
        }
      } catch (_) {}
      const adminContent: any = {
        networkName,
        chainId,
        contract: "ProxyAdmin",
        proxyAdmin: proxyAdminAddress,
      };
      if (adminMeta) adminContent.metadata = adminMeta;
      fs.writeFileSync(adminFile, JSON.stringify(adminContent, null, 2));
      writtenRows.push({
        contract: "ProxyAdmin",
        file: `deployments/${networkName}/ProxyAdmin.json`,
      });
    }
    if (writtenRows.length > 0) {
      console.log("\n================ Deployments Folder =================");
      console.table(writtenRows);
    }
  } catch (e) {
    console.warn(
      "⚠️  Could not write deployments folder:",
      (e as Error).message
    );
  }

  console.log("\n================ Pending Actions ==================");
  if (pendingActions.length === 0) {
    console.log("None ✅");
  } else {
    for (const [index, action] of pendingActions.entries()) {
      console.log(`${index + 1}. ${action}`);
    }
  }

  // Gas summary (useful to estimate costs before real deploys)
  if (gasLog.length > 0) {
    console.log("\n================ Gas Summary ======================");
    let totalGas = 0n;
    let totalCostWei = 0n;
    const gasRows = gasLog.map((e) => {
      totalGas += e.gasUsed;
      totalCostWei += e.costWei;
      return {
        step: e.label,
        from: e.from,
        gasUsed: e.gasUsed.toString(),
        gasPriceGwei: formatGwei(hre, e.gasPrice),
        costMON: formatEther(hre, e.costWei),
      };
    });
    // Add totals at variable gas
    gasRows.push({
      step: "TOTAL",
      from: "",
      gasUsed: totalGas.toString(),
      gasPriceGwei: "",
      costMON: formatEther(hre, totalCostWei),
    });
    // Add projected totals at baseline gas (first tx gas price) and optional env override
    const firstGasPrice: bigint = gasLog[0]?.gasPrice ?? 0n;
    if (firstGasPrice > 0n) {
      const projectedFirstWei = totalGas * firstGasPrice;
      gasRows.push({
        step: `TOTAL@FIRST(${formatGwei(hre, firstGasPrice)} gwei)`,
        from: "",
        gasUsed: totalGas.toString(),
        gasPriceGwei: formatGwei(hre, firstGasPrice),
        costMON: formatEther(hre, projectedFirstWei),
      });
    }
    const budgetGwei = process.env.BUDGET_GAS_GWEI
      ? BigInt(Math.floor(parseFloat(process.env.BUDGET_GAS_GWEI) * 1e9))
      : 0n;
    if (budgetGwei > 0n) {
      const projectedEnvWei = totalGas * budgetGwei;
      gasRows.push({
        step: `TOTAL@ENV(${process.env.BUDGET_GAS_GWEI} gwei)`,
        from: "",
        gasUsed: totalGas.toString(),
        gasPriceGwei: process.env.BUDGET_GAS_GWEI!,
        costMON: formatEther(hre, projectedEnvWei),
      });
    }
    console.table(gasRows);
  }

  console.log("\n================ Operational Reminders =============");
  const reminders = [
    "Upgrade the IncentivesController (Aave) implementation for all AToken, VariableDebtToken, and StableDebtToken.",
    "Configure DUST rewards emission.",
  ];
  console.table(
    reminders.map((text, idx) => ({ item: idx + 1, reminder: text }))
  );

  if (dryRun) {
    console.log("\n================ DRY RUN COMPLETE ==================");
    console.log("✅ Deployed on forked snapshot");
    console.log("🔄 Run without --dry-run to execute actual deployment");

    // Revert snapshot if taken
    if (snapshotId) {
      try {
        await hre.network.provider.send("evm_revert", [snapshotId]);
        console.log("🔄 Network state reverted to snapshot");
      } catch (error) {
        console.log("⚠️  Could not revert snapshot");
      }
    }
  }
};

/*//////////////////////////////////////////////////////////////
                        TASK: DEPLOY NEVERLAND
//////////////////////////////////////////////////////////////*/
task("deploy:neverland", "Deploy the complete Neverland protocol")
  .addOptionalParam(
    "configFile",
    "Path to deployment config JSON file",
    DEFAULT_CONFIG_PATH
  )
  .addOptionalParam(
    "exclude",
    "Comma-separated list of contracts to exclude from deployment",
    ""
  )
  .addFlag(
    "dryRun",
    "Execute a dry run to preview deployment without making changes"
  )
  .setAction(async (taskArgs: TaskArgs, hre: HardhatRuntimeEnvironment) => {
    const configPath = resolvePath(taskArgs.configFile || DEFAULT_CONFIG_PATH);

    // Parse exclude list
    const exclude = new Set<DeployableContract>();
    if (taskArgs.exclude) {
      const items = taskArgs.exclude
        .split(",")
        .map((item) => item.trim())
        .filter(Boolean);
      for (const item of items) {
        if ((ALL_CONTRACTS as string[]).includes(item)) {
          exclude.add(item as DeployableContract);
        } else {
          console.warn(`Unknown contract in exclude list: ${item}`);
        }
      }
    }

    const dryRun = !!taskArgs.dryRun;

    try {
      await deployNeverland(hre, configPath, exclude, dryRun);
      console.log("\n🎉 Deployment task completed successfully!");
    } catch (error) {
      console.error("\n❌ Deployment failed:", error);
      throw error;
    }
  });

/*//////////////////////////////////////////////////////////////
                 TASK: VALIDATE DEPLOY CONFIG (EXCLUDE-AWARE)
//////////////////////////////////////////////////////////////*/
task("deploy:validate-config", "Validate deployment configuration file")
  .addOptionalParam(
    "configFile",
    "Path to deployment config JSON file",
    DEFAULT_CONFIG_PATH
  )
  .addOptionalParam(
    "exclude",
    "Comma-separated list of contracts to exclude from deployment",
    ""
  )
  .setAction(async (taskArgs: TaskArgs) => {
    const configPath = resolvePath(taskArgs.configFile || DEFAULT_CONFIG_PATH);

    // Parse exclude list
    const exclude = new Set<DeployableContract>();
    if (taskArgs.exclude) {
      const items = taskArgs.exclude
        .split(",")
        .map((item) => item.trim())
        .filter(Boolean);
      for (const item of items) {
        if ((ALL_CONTRACTS as string[]).includes(item)) {
          exclude.add(item as DeployableContract);
        } else {
          console.warn(`Unknown contract in exclude list: ${item}`);
        }
      }
    }

    try {
      console.log(`📄 Validating config: ${configPath}`);
      const config = loadConfig(configPath);
      const configAddresses = config.addresses ?? {};

      // Define required fields per contract
      const requiredByContract: Record<DeployableContract, string[]> = {
        Dust: ["dust.totalSupply"],
        DustLock: ["dustLock.forwarder", "dustLock.baseURI"],
        DustRewardsController: [],
        UserVaultRegistry: [
          "selfRepaying.registry.executor",
          "selfRepaying.registry.maxSwapSlippageBps",
        ],
        UserVaultImplementation: [],
        UserVaultBeacon: [],
        UserVaultFactory: ["selfRepaying.poolAddressesProviderRegistry"],
        RevenueReward: ["revenueReward.forwarder"],
        DustLockTransferStrategy: ["transferStrategy.rewardsAdmin"],
        NeverlandDustHelper: [],
        NeverlandUiProvider: ["uiProvider.aaveLendingPoolAddressProvider"],
      };

      console.log("✅ Config file loaded successfully");
      console.log("🔍 Checking required fields (respecting --exclude)...");

      const missing: string[] = [];
      for (const name of ALL_CONTRACTS) {
        if (exclude.has(name)) continue;
        for (const field of requiredByContract[name]) {
          const keys = field.split(".");
          let value: any = config;
          for (const key of keys) value = value?.[key];
          if (value === undefined || value === null || value === "")
            missing.push(field);
        }
      }

      if (missing.length > 0) {
        console.log("❌ Missing required fields:");
        missing.forEach((field) => console.log(`  • ${field}`));
      } else {
        console.log(
          "✅ All required fields present for non-excluded contracts"
        );
      }

      // Additional conditional validation:
      // If DustLockTransferStrategy is not excluded and DUST_VAULT_PRIVATE_KEY is not provided,
      // ensure transferStrategy.dustVault is present in config.
      if (!exclude.has("DustLockTransferStrategy")) {
        const hasVaultKey =
          !!process.env.DUST_VAULT_PRIVATE_KEY &&
          process.env.DUST_VAULT_PRIVATE_KEY.trim() !== "";
        const cfgVault = config.transferStrategy?.dustVault;
        if (!hasVaultKey && (!cfgVault || cfgVault.trim() === "")) {
          console.log(
            "❌ Missing DUST vault: provide DUST_VAULT_PRIVATE_KEY env or transferStrategy.dustVault in config."
          );
        }
      }

      // Ensure excluded contracts have provided addresses
      const invalidExcluded: string[] = [];
      const isValid = (value?: string) =>
        !!value && value.length === 42 && value.startsWith("0x");
      for (const name of exclude) {
        const addr = configAddresses[name];
        if (!isValid(addr)) invalidExcluded.push(name);
      }

      if (invalidExcluded.length > 0) {
        console.log(
          "❌ Excluded contracts missing addresses in config.addresses:"
        );
        invalidExcluded.forEach((n) => console.log(`  • ${n}`));
      } else if (exclude.size > 0) {
        console.log("✅ Excluded contracts have valid provided addresses");
      }

      console.log("🎉 Config validation completed");
    } catch (error) {
      console.error("❌ Config validation failed:", error);
      throw error;
    }
  });
