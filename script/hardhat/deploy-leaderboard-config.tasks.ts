import fs from "fs";
import path from "path";
import { task } from "hardhat/config";
import type { HardhatRuntimeEnvironment } from "hardhat/types";

/*//////////////////////////////////////////////////////////////
                        CONFIGURATION
//////////////////////////////////////////////////////////////*/

const DEFAULT_CONFIG_PATH = path.resolve(
  __dirname,
  "config",
  "deploy-leaderboard.json"
);

interface LeaderboardConfigOnly {
  leaderboard: {
    initialOwner: string;
    depositRateBps: string;
    borrowRateBps: string;
    supplyDailyBonus: string;
    borrowDailyBonus: string;
    repayDailyBonus?: string;
    withdrawDailyBonus?: string;
    cooldownSeconds: string;
    minDailyBonusUsd?: string;
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

const loadConfig = (configPath: string): LeaderboardConfigOnly => {
  if (!fs.existsSync(configPath)) {
    throw new Error(`Config file not found at ${configPath}`);
  }
  const raw = fs.readFileSync(configPath, "utf8");
  try {
    return JSON.parse(raw) as LeaderboardConfigOnly;
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

const deployLeaderboardConfigOnly = async (
  hre: HardhatRuntimeEnvironment,
  configPath: string,
  shouldVerify: boolean
): Promise<void> => {
  console.log(`📄 Using config: ${configPath}`);

  // Load configuration
  const config = loadConfig(configPath);

  if (!config.leaderboard) {
    throw new Error("Missing leaderboard configuration in config file");
  }

  // Extract LeaderboardConfig parameters
  const leaderboardOwner = requireConfigValue(
    config.leaderboard.initialOwner,
    "leaderboard.initialOwner"
  );
  const depositRateBps = requireConfigValue(
    config.leaderboard.depositRateBps,
    "leaderboard.depositRateBps"
  );
  const borrowRateBps = requireConfigValue(
    config.leaderboard.borrowRateBps,
    "leaderboard.borrowRateBps"
  );
  const supplyDailyBonus = requireConfigValue(
    config.leaderboard.supplyDailyBonus,
    "leaderboard.supplyDailyBonus"
  );
  const borrowDailyBonus = requireConfigValue(
    config.leaderboard.borrowDailyBonus,
    "leaderboard.borrowDailyBonus"
  );
  const repayDailyBonus = config.leaderboard.repayDailyBonus || "0";
  const withdrawDailyBonus = config.leaderboard.withdrawDailyBonus || "0";
  const cooldownSeconds = requireConfigValue(
    config.leaderboard.cooldownSeconds,
    "leaderboard.cooldownSeconds"
  );
  const minDailyBonusUsd = config.leaderboard.minDailyBonusUsd || "0";

  // Get deployer
  const [deployer] = await hre.ethers.getSigners();
  const deployerAddress = await deployer.getAddress();
  console.log(`👤 Deployer: ${deployerAddress}`);

  // Deploy LeaderboardConfig
  console.log("\n⛏️  Deploying LeaderboardConfig...");
  const LeaderboardConfigFactory = await hre.ethers.getContractFactory(
    "LeaderboardConfig"
  );
  const leaderboard = await LeaderboardConfigFactory.deploy(
    leaderboardOwner,
    depositRateBps,
    borrowRateBps,
    supplyDailyBonus,
    borrowDailyBonus,
    repayDailyBonus,
    withdrawDailyBonus,
    cooldownSeconds,
    minDailyBonusUsd
  );
  await leaderboard.waitForDeployment();
  const leaderboardAddress = await leaderboard.getAddress();
  console.log(`✅ LeaderboardConfig deployed at ${leaderboardAddress}`);

  // Display deployment parameters
  console.log("\n📋 Deployment Summary:");
  console.log("\n🔹 LeaderboardConfig:");
  console.log(`   Address: ${leaderboardAddress}`);
  console.log(`   Owner: ${leaderboardOwner}`);
  console.log(`   Deposit Rate: ${depositRateBps} bps`);
  console.log(`   Borrow Rate: ${borrowRateBps} bps`);
  console.log(`   Supply Bonus: ${supplyDailyBonus}`);
  console.log(`   Borrow Bonus: ${borrowDailyBonus}`);
  console.log(`   Repay Bonus: ${repayDailyBonus}`);
  console.log(`   Withdraw Bonus: ${withdrawDailyBonus}`);
  console.log(`   Cooldown: ${cooldownSeconds}s`);
  console.log(`   Min USD: ${minDailyBonusUsd}`);

  // Get deployment transaction details
  const depTx = leaderboard.deploymentTransaction();
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

    console.log("\n🔍 Verifying LeaderboardConfig...");
    await verifyContract(hre, leaderboardAddress, [
      leaderboardOwner,
      depositRateBps,
      borrowRateBps,
      supplyDailyBonus,
      borrowDailyBonus,
      repayDailyBonus,
      withdrawDailyBonus,
      cooldownSeconds,
      minDailyBonusUsd,
    ]);
  }

  // Save deployment info
  const deploymentInfo = {
    leaderboardConfig: leaderboardAddress,
    deployer: deployerAddress,
    network: hre.network.name,
    timestamp: new Date().toISOString(),
    parameters: {
      leaderboard: {
        initialOwner: leaderboardOwner,
        depositRateBps,
        borrowRateBps,
        supplyDailyBonus,
        borrowDailyBonus,
        repayDailyBonus,
        withdrawDailyBonus,
        cooldownSeconds,
        minDailyBonusUsd,
      },
    },
  };

  const outputPath = path.resolve(
    __dirname,
    `../../deployments/leaderboard-config-${
      hre.network.name
    }-${Date.now()}.json`
  );
  fs.mkdirSync(path.dirname(outputPath), { recursive: true });
  fs.writeFileSync(outputPath, JSON.stringify(deploymentInfo, null, 2));
  console.log(`\n💾 Deployment info saved to ${outputPath}`);

  console.log("\n================ Post-Deployment Notes ==================");
  console.log("\n📌 LeaderboardConfig - Available Functions:");
  console.log("   • setDepositRate(uint256 newRateBps)");
  console.log("   • setBorrowRate(uint256 newRateBps)");
  console.log("   • setDailyBonuses(supply, borrow, repay, withdraw)");
  console.log("   • setCooldown(uint256 newSeconds)");
  console.log("   • setMinDailyBonusUsd(uint256 newMin)");
  console.log("   • updateAllRates(...) for batch updates");
  console.log(
    "   • awardPoints(address user, uint256 points, string reason) - NEW!"
  );

  console.log("\n📊 Events emitted for subgraph indexing:");
  console.log(
    "   • DepositRateUpdated / BorrowRateUpdated / DailyBonusUpdated"
  );
  console.log("   • ConfigSnapshot (on every config change)");
  console.log("   • PointsAwarded (manual point awards)");

  console.log(
    "\n⚠️  Remember to update your subgraph with the new contract address!"
  );
};

/*//////////////////////////////////////////////////////////////
                TASK: DEPLOY LEADERBOARD CONFIG ONLY
//////////////////////////////////////////////////////////////*/

task(
  "deploy:leaderboard-config",
  "Deploy only the LeaderboardConfig contract (with new awardPoints function)"
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
      await deployLeaderboardConfigOnly(hre, configPath, shouldVerify);
      console.log("\n🎉 LeaderboardConfig deployment completed successfully!");
    } catch (error) {
      console.error("\n❌ Deployment failed:", error);
      throw error;
    }
  });
