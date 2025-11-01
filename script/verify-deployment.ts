import fs from "fs";
import path from "path";

interface DeploymentAddresses {
  Dust: string;
  DustLock: string;
  RevenueReward: string;
  DustRewardsController: string;
  DustLockTransferStrategy: string;
  NeverlandDustHelper: string;
  NeverlandUiProvider: string;
  UserVaultRegistry: string;
  UserVaultImplementation: string;
  UserVaultBeacon: string;
  UserVaultFactory: string;
  ProxyAdmin: string;
}

interface ExpectedConfig {
  dust: {
    initialOwner: string;
    totalSupply: string;
  };
  dustLock: {
    team: string;
    earlyWithdrawTreasury: string;
    minLockAmount: string;
    baseURI: string;
  };
  dustRewardsController: {
    emissionManager: string;
  };
  revenueReward: {
    distributor: string;
  };
  transferStrategy: {
    rewardsAdmin: string;
    dustVault: string;
  };
  selfRepaying: {
    registry: {
      owner: string;
      executor: string;
      maxSwapSlippageBps: string;
    };
    beaconOwner: string;
    poolAddressesProviderRegistry: string;
  };
  proxyAdmin: {
    owner: string;
  };
}

async function loadDeployment(network: string): Promise<DeploymentAddresses> {
  const deployPath = path.join(__dirname, "..", "deployments", network);
  const addressesFilePath = path.join(deployPath, "addresses.json");

  if (!fs.existsSync(addressesFilePath)) {
    throw new Error(`Addresses file not found at ${addressesFilePath}`);
  }

  const data = JSON.parse(fs.readFileSync(addressesFilePath, "utf8"));
  const addresses = data.addresses || {};

  // Add ProxyAdmin if available
  if (data.proxyAdmin) {
    addresses.ProxyAdmin = data.proxyAdmin;
  }

  return addresses as DeploymentAddresses;
}

async function loadExpectedConfig(configFile: string): Promise<ExpectedConfig> {
  const configPath = path.resolve(configFile);
  const raw = fs.readFileSync(configPath, "utf8");
  return JSON.parse(raw);
}

async function verifyDeployment(
  network: string,
  configFile: string
): Promise<void> {
  console.log("\n🔍 ============= DEPLOYMENT VERIFICATION =============\n");
  console.log(`📍 Network: ${network}`);
  console.log(`📄 Config: ${configFile}\n`);

  // Dynamically import hardhat to avoid circular dependency
  const hre = require("hardhat");
  const ethers = hre.ethers;

  const addresses = await loadDeployment(network);
  const expected = await loadExpectedConfig(configFile);

  const errors: string[] = [];
  const warnings: string[] = [];
  const checks: Array<{ name: string; status: string; details: string }> = [];

  // ============= DUST TOKEN =============
  console.log("🪙  Checking DUST Token...");
  const dust = await ethers.getContractAt("Dust", addresses.Dust);

  const dustOwner = await dust.owner();
  const dustTotalSupply = await dust.totalSupply();
  const dustName = await dust.name();
  const dustSymbol = await dust.symbol();

  checks.push({
    name: "DUST Owner",
    status:
      dustOwner.toLowerCase() === expected.dust.initialOwner.toLowerCase()
        ? "✅"
        : "❌",
    details: `Expected: ${expected.dust.initialOwner}, Got: ${dustOwner}`,
  });

  const expectedSupply = ethers.parseEther(expected.dust.totalSupply);
  checks.push({
    name: "DUST Total Supply",
    status: dustTotalSupply === expectedSupply ? "✅" : "❌",
    details: `Expected: ${ethers.formatEther(
      expectedSupply
    )}, Got: ${ethers.formatEther(dustTotalSupply)}`,
  });

  checks.push({
    name: "DUST Token Info",
    status: "ℹ️",
    details: `Name: ${dustName}, Symbol: ${dustSymbol}`,
  });

  const ownerBalance = await dust.balanceOf(dustOwner);
  checks.push({
    name: "DUST Minted to Owner",
    status: ownerBalance === dustTotalSupply ? "✅" : "⚠️ ",
    details: `Owner has ${ethers.formatEther(ownerBalance)} DUST`,
  });

  // ============= DUST LOCK =============
  console.log("\n🔒 Checking DustLock...");
  const dustLock = await ethers.getContractAt("DustLock", addresses.DustLock);

  const lockTeam = await dustLock.team();
  const lockPendingTeam = await dustLock.pendingTeam();
  const lockTreasury = await dustLock.earlyWithdrawTreasury();
  const lockMinAmount = await dustLock.minLockAmount();
  const lockTokenURI = await dustLock
    .tokenURI(1)
    .catch(() => "N/A (no tokens yet)");
  const lockRevenueReward = await dustLock.revenueReward();
  const lockToken = await dustLock.token();

  // Check if team matches or is pending (two-step transfer)
  const teamMatches =
    lockTeam.toLowerCase() === expected.dustLock.team.toLowerCase();
  const teamPending =
    lockPendingTeam.toLowerCase() === expected.dustLock.team.toLowerCase();
  checks.push({
    name: "DustLock Team",
    status: teamMatches ? "✅" : teamPending ? "⏳" : "❌",
    details: teamMatches
      ? `Current: ${lockTeam}`
      : teamPending
      ? `Pending acceptance: ${lockPendingTeam} (current: ${lockTeam})`
      : `Expected: ${expected.dustLock.team}, Got: ${lockTeam}`,
  });

  checks.push({
    name: "DustLock Early Withdraw Treasury",
    status:
      lockTreasury.toLowerCase() ===
      expected.dustLock.earlyWithdrawTreasury.toLowerCase()
        ? "✅"
        : "❌",
    details: `Expected: ${expected.dustLock.earlyWithdrawTreasury}, Got: ${lockTreasury}`,
  });

  const expectedMinLock = BigInt(expected.dustLock.minLockAmount);
  checks.push({
    name: "DustLock Min Lock Amount",
    status: lockMinAmount === expectedMinLock ? "✅" : "❌",
    details: `Expected: ${ethers.formatEther(
      expectedMinLock
    )}, Got: ${ethers.formatEther(lockMinAmount)}`,
  });

  checks.push({
    name: "DustLock Token Address",
    status:
      lockToken.toLowerCase() === addresses.Dust.toLowerCase() ? "✅" : "❌",
    details: `Expected: ${addresses.Dust}, Got: ${lockToken}`,
  });

  checks.push({
    name: "DustLock Revenue Reward Linked",
    status:
      lockRevenueReward.toLowerCase() === addresses.RevenueReward.toLowerCase()
        ? "✅"
        : "❌",
    details: `Expected: ${addresses.RevenueReward}, Got: ${lockRevenueReward}`,
  });

  // ============= DUST REWARDS CONTROLLER =============
  console.log("\n🎁 Checking DustRewardsController...");
  const controller = await ethers.getContractAt(
    "DustRewardsController",
    addresses.DustRewardsController
  );

  const emissionManager = await controller.getEmissionManager();
  const controllerStrategy = await controller.getTransferStrategy(
    addresses.Dust
  );

  checks.push({
    name: "DustRewardsController Emission Manager",
    status:
      emissionManager.toLowerCase() ===
      expected.dustRewardsController.emissionManager.toLowerCase()
        ? "✅"
        : "❌",
    details: `Expected: ${expected.dustRewardsController.emissionManager}, Got: ${emissionManager}`,
  });

  // Transfer strategy can be zero (will be set during configureAssets)
  const strategyIsZero = controllerStrategy === ethers.ZeroAddress;
  const strategyIsSet =
    controllerStrategy.toLowerCase() ===
    addresses.DustLockTransferStrategy.toLowerCase();
  checks.push({
    name: "DustRewardsController Transfer Strategy",
    status: strategyIsSet ? "✅" : strategyIsZero ? "⏳" : "❌",
    details: strategyIsSet
      ? `Set: ${controllerStrategy}`
      : strategyIsZero
      ? `Not set yet (will be configured with emissions)`
      : `Unexpected: ${controllerStrategy}`,
  });

  // ============= REVENUE REWARD =============
  console.log("\n💰 Checking RevenueReward...");
  const revenueReward = await ethers.getContractAt(
    "RevenueReward",
    addresses.RevenueReward
  );

  const rrDistributor = await revenueReward.rewardDistributor();
  const rrDustLock = await revenueReward.dustLock();

  checks.push({
    name: "RevenueReward Distributor",
    status:
      rrDistributor.toLowerCase() ===
      expected.revenueReward.distributor.toLowerCase()
        ? "✅"
        : "❌",
    details: `Expected: ${expected.revenueReward.distributor}, Got: ${rrDistributor}`,
  });

  checks.push({
    name: "RevenueReward DustLock Address",
    status:
      rrDustLock.toLowerCase() === addresses.DustLock.toLowerCase()
        ? "✅"
        : "❌",
    details: `Expected: ${addresses.DustLock}, Got: ${rrDustLock}`,
  });

  // ============= DUST LOCK TRANSFER STRATEGY =============
  console.log("\n🔄 Checking DustLockTransferStrategy...");
  const strategy = await ethers.getContractAt(
    "DustLockTransferStrategy",
    addresses.DustLockTransferStrategy
  );

  const strategyController = await strategy.getIncentivesController();
  const strategyAdmin = await strategy.getRewardsAdmin();
  const strategyVault = await strategy.DUST_VAULT();
  const strategyDustLock = await strategy.DUST_LOCK();

  checks.push({
    name: "Strategy Incentives Controller",
    status:
      strategyController.toLowerCase() ===
      addresses.DustRewardsController.toLowerCase()
        ? "✅"
        : "❌",
    details: `Expected: ${addresses.DustRewardsController}, Got: ${strategyController}`,
  });

  checks.push({
    name: "Strategy Rewards Admin",
    status:
      strategyAdmin.toLowerCase() ===
      expected.transferStrategy.rewardsAdmin.toLowerCase()
        ? "✅"
        : "❌",
    details: `Expected: ${expected.transferStrategy.rewardsAdmin}, Got: ${strategyAdmin}`,
  });

  checks.push({
    name: "Strategy DUST Vault",
    status:
      strategyVault.toLowerCase() ===
      expected.transferStrategy.dustVault.toLowerCase()
        ? "✅"
        : "❌",
    details: `Expected: ${expected.transferStrategy.dustVault}, Got: ${strategyVault}`,
  });

  checks.push({
    name: "Strategy DustLock Address",
    status:
      strategyDustLock.toLowerCase() === addresses.DustLock.toLowerCase()
        ? "✅"
        : "❌",
    details: `Expected: ${addresses.DustLock}, Got: ${strategyDustLock}`,
  });

  // Check DUST vault approval
  const vaultAllowance = await dust.allowance(
    strategyVault,
    addresses.DustLockTransferStrategy
  );
  const isMaxApproved = vaultAllowance === ethers.MaxUint256;
  checks.push({
    name: "DUST Vault Approval",
    status: isMaxApproved ? "✅" : "⚠️ ",
    details: isMaxApproved
      ? "MaxUint256 approved"
      : `${ethers.formatEther(vaultAllowance)} approved (needs MaxUint256)`,
  });

  if (!isMaxApproved) {
    warnings.push(
      `DUST Vault needs to approve DustLockTransferStrategy: Call Dust(${addresses.Dust}).approve(${addresses.DustLockTransferStrategy}, MaxUint256) from ${strategyVault}`
    );
  }

  // ============= USER VAULT REGISTRY =============
  console.log("\n🏦 Checking UserVaultRegistry...");
  const registry = await ethers.getContractAt(
    "UserVaultRegistry",
    addresses.UserVaultRegistry
  );

  const registryOwner = await registry.owner();
  const registryPendingOwner = await registry.pendingOwner();
  const registryExecutor = await registry.executor();
  const registrySlippage = await registry.maxSwapSlippageBps();

  // Check if owner matches or is pending (two-step transfer)
  const ownerMatches =
    registryOwner.toLowerCase() ===
    expected.selfRepaying.registry.owner.toLowerCase();
  const ownerPending =
    registryPendingOwner.toLowerCase() ===
    expected.selfRepaying.registry.owner.toLowerCase();
  checks.push({
    name: "UserVaultRegistry Owner",
    status: ownerMatches ? "✅" : ownerPending ? "⏳" : "❌",
    details: ownerMatches
      ? `Current: ${registryOwner}`
      : ownerPending
      ? `Pending acceptance: ${registryPendingOwner} (current: ${registryOwner})`
      : `Expected: ${expected.selfRepaying.registry.owner}, Got: ${registryOwner}`,
  });

  checks.push({
    name: "UserVaultRegistry Executor",
    status:
      registryExecutor.toLowerCase() ===
      expected.selfRepaying.registry.executor.toLowerCase()
        ? "✅"
        : "❌",
    details: `Expected: ${expected.selfRepaying.registry.executor}, Got: ${registryExecutor}`,
  });

  const expectedSlippage = BigInt(
    expected.selfRepaying.registry.maxSwapSlippageBps
  );
  checks.push({
    name: "UserVaultRegistry Max Slippage",
    status: registrySlippage === expectedSlippage ? "✅" : "❌",
    details: `Expected: ${expectedSlippage} bps (${
      Number(expectedSlippage) / 100
    }%), Got: ${registrySlippage} bps (${Number(registrySlippage) / 100}%)`,
  });

  // ============= USER VAULT BEACON =============
  console.log("\n🏗️  Checking UserVaultBeacon...");
  const beacon = await ethers.getContractAt(
    "UpgradeableBeacon",
    addresses.UserVaultBeacon
  );

  const beaconOwner = await beacon.owner();
  const beaconImpl = await beacon.implementation();

  checks.push({
    name: "UserVaultBeacon Owner",
    status:
      beaconOwner.toLowerCase() ===
      expected.selfRepaying.beaconOwner.toLowerCase()
        ? "✅"
        : "❌",
    details: `Expected: ${expected.selfRepaying.beaconOwner}, Got: ${beaconOwner}`,
  });

  checks.push({
    name: "UserVaultBeacon Implementation",
    status:
      beaconImpl.toLowerCase() ===
      addresses.UserVaultImplementation.toLowerCase()
        ? "✅"
        : "❌",
    details: `Expected: ${addresses.UserVaultImplementation}, Got: ${beaconImpl}`,
  });

  // ============= USER VAULT FACTORY =============
  console.log("\n🏭 Checking UserVaultFactory...");
  const factory = await ethers.getContractAt(
    "UserVaultFactory",
    addresses.UserVaultFactory
  );

  const factoryRegistry = await factory.userVaultRegistry();
  const factoryRevenueReward = await factory.revenueReward();
  const factoryPoolRegistry = await factory.poolAddressesProviderRegistry();

  checks.push({
    name: "UserVaultFactory Registry",
    status:
      factoryRegistry.toLowerCase() ===
      addresses.UserVaultRegistry.toLowerCase()
        ? "✅"
        : "❌",
    details: `Expected: ${addresses.UserVaultRegistry}, Got: ${factoryRegistry}`,
  });

  checks.push({
    name: "UserVaultFactory Revenue Reward",
    status:
      factoryRevenueReward.toLowerCase() ===
      addresses.RevenueReward.toLowerCase()
        ? "✅"
        : "❌",
    details: `Expected: ${addresses.RevenueReward}, Got: ${factoryRevenueReward}`,
  });

  checks.push({
    name: "UserVaultFactory Pool Registry",
    status:
      factoryPoolRegistry.toLowerCase() ===
      expected.selfRepaying.poolAddressesProviderRegistry.toLowerCase()
        ? "✅"
        : "❌",
    details: `Expected: ${expected.selfRepaying.poolAddressesProviderRegistry}, Got: ${factoryPoolRegistry}`,
  });

  // ============= PROXY ADMIN =============
  if (addresses.ProxyAdmin) {
    console.log("\n🔐 Checking ProxyAdmin...");
    const proxyAdmin = await ethers.getContractAt(
      "ProxyAdmin",
      addresses.ProxyAdmin
    );

    const proxyAdminOwner = await proxyAdmin.owner();

    checks.push({
      name: "ProxyAdmin Owner",
      status:
        proxyAdminOwner.toLowerCase() ===
        expected.proxyAdmin.owner.toLowerCase()
          ? "✅"
          : "❌",
      details: `Expected: ${expected.proxyAdmin.owner}, Got: ${proxyAdminOwner}`,
    });
  }

  // ============= PRINT RESULTS =============
  console.log("\n📊 ============= VERIFICATION RESULTS =============\n");

  // Format checks for console.table
  const tableData = checks.map((check) => ({
    Status: check.status,
    Check: check.name,
    Details: check.details,
  }));

  console.table(tableData);

  const pendingChecks = checks.filter((c) => c.status === "⏳");
  if (pendingChecks.length > 0) {
    console.log("\n⏳ ============= PENDING ACTIONS =============\n");
    const pendingTable = pendingChecks.map((c) => ({
      Action: c.name,
      Status: c.details,
    }));
    console.table(pendingTable);
  }

  if (warnings.length > 0) {
    console.log("\n⚠️  ============= WARNINGS =============\n");
    warnings.forEach((w, i) => console.log(`${i + 1}. ${w}\n`));
  }

  if (errors.length > 0) {
    console.log("\n❌ ============= ERRORS =============\n");
    errors.forEach((e, i) => console.log(`${i + 1}. ${e}\n`));
  }

  const failedChecks = checks.filter((c) => c.status === "❌");
  if (failedChecks.length > 0) {
    console.log(`\n❌ ${failedChecks.length} checks FAILED\n`);
    process.exit(1);
  }

  console.log("\n✅ All checks passed!\n");
  if (pendingChecks.length > 0) {
    console.log(
      `⏳ ${pendingChecks.length} pending actions (requires acceptance)\n`
    );
  }
  if (warnings.length > 0) {
    console.log(`⚠️  ${warnings.length} warnings (manual action required)\n`);
  }
}

// CLI
const network = process.argv[2] || "anvilFork";
const configFile =
  process.argv[3] || "script/hardhat/config/deploy.mainnet.json";

verifyDeployment(network, configFile)
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
