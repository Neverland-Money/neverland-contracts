import fs from "fs";
import path from "path";
import { task } from "hardhat/config";
import type { HardhatRuntimeEnvironment } from "hardhat/types";
import { exportDeployment } from "./helpers/export";

/*//////////////////////////////////////////////////////////////
                        CONFIGURATION
//////////////////////////////////////////////////////////////*/

const DEFAULT_CONFIG_PATH = path.resolve(
  __dirname,
  "config",
  "deploy-leaderboard-keeper.json"
);

interface LeaderboardKeeperConfig {
  keeper: {
    initialOwner: string;
    keeperAddress: string;
    minSettlementInterval: string;
    dustLock: string;
    nftRegistry: string;
  };
  verify?: boolean;
}

interface TaskArgs {
  configFile?: string;
  verify?: boolean;
}

/*//////////////////////////////////////////////////////////////
                            HELPERS
//////////////////////////////////////////////////////////////*/

const resolvePath = (maybePath: string): string =>
  path.isAbsolute(maybePath) ? maybePath : path.join(process.cwd(), maybePath);

const loadConfig = (configPath: string): LeaderboardKeeperConfig => {
  if (!fs.existsSync(configPath)) {
    throw new Error(`Config file not found at ${configPath}`);
  }
  const raw = fs.readFileSync(configPath, "utf8");
  try {
    return JSON.parse(raw) as LeaderboardKeeperConfig;
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

const verifyContract = async (
  hre: HardhatRuntimeEnvironment,
  address: string,
  constructorArgs: any[] = []
): Promise<void> => {
  try {
    console.log(`   🔍 Verifying contract at ${address}...`);
    await hre.run("verify:verify", {
      address,
      constructorArguments: constructorArgs,
    });
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

const deployLeaderboardKeeper = async (
  hre: HardhatRuntimeEnvironment,
  configPath: string,
  shouldVerify: boolean
): Promise<void> => {
  console.log(`📄 Using config: ${configPath}`);

  // Load configuration
  const config = loadConfig(configPath);

  if (!config.keeper) {
    throw new Error("Missing keeper configuration in config file");
  }

  // Extract LeaderboardKeeper parameters
  const initialOwner = requireConfigValue(
    config.keeper.initialOwner,
    "keeper.initialOwner"
  );
  const keeperAddress = requireConfigValue(
    config.keeper.keeperAddress,
    "keeper.keeperAddress"
  );
  const minSettlementInterval = requireConfigValue(
    config.keeper.minSettlementInterval,
    "keeper.minSettlementInterval"
  );
  const dustLock = requireConfigValue(
    config.keeper.dustLock,
    "keeper.dustLock"
  );
  const nftRegistry = requireConfigValue(
    config.keeper.nftRegistry,
    "keeper.nftRegistry"
  );

  // Get deployer
  const [deployer] = await hre.ethers.getSigners();
  const deployerAddress = await deployer.getAddress();
  console.log(`👤 Deployer: ${deployerAddress}`);

  // Deploy LeaderboardKeeper
  console.log("\n⛏️  Deploying LeaderboardKeeper...");
  const LeaderboardKeeperFactory =
    await hre.ethers.getContractFactory("LeaderboardKeeper");
  const keeper = await LeaderboardKeeperFactory.deploy(
    initialOwner,
    keeperAddress,
    minSettlementInterval,
    dustLock,
    nftRegistry
  );
  await keeper.waitForDeployment();
  const keeperContractAddress = await keeper.getAddress();
  console.log(`✅ LeaderboardKeeper deployed at ${keeperContractAddress}`);

  // Display deployment parameters
  console.log("\n📋 Deployment Summary:");
  console.log("\n🔹 LeaderboardKeeper:");
  console.log(`   Address: ${keeperContractAddress}`);
  console.log(`   Owner: ${initialOwner}`);
  console.log(`   Keeper Bot: ${keeperAddress}`);
  console.log(`   Min Settlement Interval: ${minSettlementInterval}s`);
  console.log(`   DustLock: ${dustLock}`);
  console.log(`   NFT Registry: ${nftRegistry}`);
  console.log(
    `   Max Correction Batch: ${await keeper.MAX_CORRECTION_BATCH()}`
  );
  console.log(
    `   Max Settlement Batch: ${await keeper.MAX_SETTLEMENT_BATCH()}`
  );

  // Get deployment transaction details
  const depTx = keeper.deploymentTransaction();
  if (depTx) {
    const receipt = await depTx.wait();
    const gasUsed = receipt?.gasUsed ?? BigInt(0);
    const gasPrice =
      (receipt as any)?.effectiveGasPrice ??
      (receipt as any)?.gasPrice ??
      BigInt(0);
    const costWei = gasUsed * gasPrice;
    console.log(`\n⛽ Gas Details:`);
    console.log(`   Gas Used: ${gasUsed.toString()}`);
    console.log(
      `   Gas Price: ${hre.ethers.formatUnits(gasPrice, "gwei")} gwei`
    );
    console.log(`   Total Cost: ${hre.ethers.formatEther(costWei)} MON`);
  }

  // Verify contract if requested
  if (shouldVerify) {
    console.log("\n🔍 Waiting before verification...");
    await new Promise((resolve) => setTimeout(resolve, 10000)); // Wait 10s

    console.log("\n🔍 Verifying LeaderboardKeeper...");
    await verifyContract(hre, keeperContractAddress, [
      initialOwner,
      keeperAddress,
      minSettlementInterval,
      dustLock,
      nftRegistry,
    ]);
  }

  // Save deployment info
  const deploymentInfo = {
    leaderboardKeeper: keeperContractAddress,
    deployer: deployerAddress,
    network: hre.network.name,
    timestamp: new Date().toISOString(),
    parameters: {
      keeper: {
        initialOwner,
        keeperAddress,
        minSettlementInterval,
        dustLock,
        nftRegistry,
      },
    },
  };

  // Export to standard deployments folder
  await exportDeployment(hre, "LeaderboardKeeper", {
    address: keeperContractAddress,
    constructorArgs: [
      initialOwner,
      keeperAddress,
      minSettlementInterval,
      dustLock,
      nftRegistry,
    ],
    metadata: {
      deployer: deployerAddress,
      timestamp: Date.now(),
      chainId: hre.network.config.chainId,
      gasUsed: depTx ? (await depTx.wait())?.gasUsed.toString() : undefined,
    },
  });

  console.log("\n================ Post-Deployment Notes ==================");
  console.log("\n📌 LeaderboardKeeper - Available Functions:");
  console.log(
    "   • batchVerifyAndSettle(users[], states[]) - Submit corrections"
  );
  console.log(
    "   • batchSyncCollectionBalances(users[], collections[], balances[]) - Sync NFT balances"
  );
  console.log(
    "   • batchSettleAccurate(users[]) - Fast path for accurate users"
  );
  console.log("   • syncMyState() - User callable state sync (1hr cooldown)");
  console.log("   • emergencySettle(user) - Owner-only single user settlement");
  console.log("   • setKeeper(address) - Update keeper address");
  console.log("   • setMinSettlementInterval(uint256) - Update interval");

  console.log("\n📊 Events emitted for subgraph indexing:");
  console.log("   • StateVerified - When on-chain state is verified");
  console.log(
    "   • CollectionBalanceVerified - Per-collection NFT balance updates"
  );
  console.log("   • UserSettled - Triggers point accrual in subgraph");
  console.log("   • BatchSettlementComplete - Summary of batch operation");
};

/*//////////////////////////////////////////////////////////////
              TASK: DEPLOY LEADERBOARD KEEPER ONLY
//////////////////////////////////////////////////////////////*/

task(
  "deploy:leaderboard-keeper",
  "Deploy LeaderboardKeeper contract for automated state verification"
)
  .addOptionalParam(
    "configFile",
    "Path to deployment config JSON file",
    DEFAULT_CONFIG_PATH
  )
  .addFlag("verify", "Verify contract on block explorer after deployment")
  .setAction(async (taskArgs: TaskArgs, hre: HardhatRuntimeEnvironment) => {
    const configPath = resolvePath(taskArgs.configFile || DEFAULT_CONFIG_PATH);
    const shouldVerify = taskArgs.verify ?? false;

    try {
      await deployLeaderboardKeeper(hre, configPath, shouldVerify);
      console.log("\n🎉 LeaderboardKeeper deployment completed successfully!");
    } catch (error) {
      console.error("\n❌ Deployment failed:", error);
      throw error;
    }
  });
