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

interface VotingPowerTier {
  minVotingPower: string;
  multiplierBps: string;
}

interface LeaderboardConfig {
  addresses?: {
    dustLock?: string;
  };
  leaderboard?: {
    initialOwner?: string;
    depositRateBps?: string;
    borrowRateBps?: string;
    supplyDailyBonus?: string;
    borrowDailyBonus?: string;
    repayDailyBonus?: string;
    withdrawDailyBonus?: string;
    cooldownSeconds?: string;
    minDailyBonusUsd?: string;
  };
  epochManager?: {
    initialOwner?: string;
  };
  nftRegistry?: {
    initialOwner?: string;
    firstBonus?: string;
    decayRatio?: string;
  };
  votingPowerMultiplier?: {
    initialOwner?: string;
    tiers?: VotingPowerTier[];
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

const loadConfig = (configPath: string): LeaderboardConfig => {
  if (!fs.existsSync(configPath)) {
    throw new Error(`Config file not found at ${configPath}`);
  }
  const raw = fs.readFileSync(configPath, "utf8");
  try {
    return JSON.parse(raw) as LeaderboardConfig;
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

const deployLeaderboardConfig = async (
  hre: HardhatRuntimeEnvironment,
  configPath: string,
  shouldVerify: boolean
): Promise<void> => {
  console.log(`📄 Using config: ${configPath}`);

  // Load configuration
  const config = loadConfig(configPath);

  if (!config.addresses?.dustLock) {
    throw new Error("Missing addresses.dustLock in config file");
  }
  if (!config.leaderboard) {
    throw new Error("Missing leaderboard configuration in config file");
  }
  if (!config.epochManager) {
    throw new Error("Missing epochManager configuration in config file");
  }
  if (!config.nftRegistry) {
    throw new Error("Missing nftRegistry configuration in config file");
  }
  if (!config.votingPowerMultiplier) {
    throw new Error(
      "Missing votingPowerMultiplier configuration in config file"
    );
  }

  const dustLockAddress = config.addresses.dustLock;

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

  // Extract EpochManager parameters
  const epochOwner = requireConfigValue(
    config.epochManager.initialOwner,
    "epochManager.initialOwner"
  );

  // Extract NFTPartnershipRegistry parameters
  const nftOwner = requireConfigValue(
    config.nftRegistry.initialOwner,
    "nftRegistry.initialOwner"
  );
  const firstBonus = requireConfigValue(
    config.nftRegistry.firstBonus,
    "nftRegistry.firstBonus"
  );
  const decayRatio = requireConfigValue(
    config.nftRegistry.decayRatio,
    "nftRegistry.decayRatio"
  );

  // Extract VotingPowerMultiplier parameters
  const vpOwner = requireConfigValue(
    config.votingPowerMultiplier.initialOwner,
    "votingPowerMultiplier.initialOwner"
  );
  const tiers = config.votingPowerMultiplier.tiers || [];

  // Get deployer
  const [deployer] = await hre.ethers.getSigners();
  const deployerAddress = await deployer.getAddress();
  console.log(`👤 Deployer: ${deployerAddress}`);

  // Deploy EpochManager
  console.log("\n⛏️  Deploying EpochManager...");
  const EpochManagerFactory = await hre.ethers.getContractFactory(
    "EpochManager"
  );
  const epochManager = await EpochManagerFactory.deploy(epochOwner);
  await epochManager.waitForDeployment();
  const epochManagerAddress = await epochManager.getAddress();
  console.log(`✅ EpochManager deployed at ${epochManagerAddress}`);

  // Deploy NFTPartnershipRegistry
  console.log("\n⛏️  Deploying NFTPartnershipRegistry...");
  const NFTRegistryFactory = await hre.ethers.getContractFactory(
    "NFTPartnershipRegistry"
  );
  const nftRegistry = await NFTRegistryFactory.deploy(
    nftOwner,
    firstBonus,
    decayRatio
  );
  await nftRegistry.waitForDeployment();
  const nftRegistryAddress = await nftRegistry.getAddress();
  console.log(`✅ NFTPartnershipRegistry deployed at ${nftRegistryAddress}`);

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

  // Deploy VotingPowerMultiplier
  console.log("\n⛏️  Deploying VotingPowerMultiplier...");
  const VotingPowerMultiplierFactory = await hre.ethers.getContractFactory(
    "VotingPowerMultiplier"
  );
  const votingPowerMultiplier = await VotingPowerMultiplierFactory.deploy(
    vpOwner,
    dustLockAddress
  );
  await votingPowerMultiplier.waitForDeployment();
  const votingPowerMultiplierAddress = await votingPowerMultiplier.getAddress();
  console.log(
    `✅ VotingPowerMultiplier deployed at ${votingPowerMultiplierAddress}`
  );

  // Add tiers if configured (only if deployer is owner)
  if (tiers.length > 1) {
    if (deployerAddress.toLowerCase() === vpOwner.toLowerCase()) {
      console.log(`\n⚙️  Adding ${tiers.length - 1} additional tiers...`);
      for (let i = 1; i < tiers.length; i++) {
        const tier = tiers[i];
        const tx = await votingPowerMultiplier.addTier(
          tier.minVotingPower,
          tier.multiplierBps
        );
        await tx.wait();
        console.log(
          `   ✅ Tier ${i}: ${tier.minVotingPower} VP = ${
            Number(tier.multiplierBps) / 100
          }%`
        );
      }
    } else {
      console.log(`\n⚠️  Skipping tier configuration - deployer is not owner`);
      console.log(`   Deployer: ${deployerAddress}`);
      console.log(`   Owner: ${vpOwner}`);
      console.log(
        `   Please add ${
          tiers.length - 1
        } additional tiers manually using the owner account`
      );
    }
  }

  // Display deployment parameters
  console.log("\n📋 Deployment Summary:");
  console.log("\n🔹 EpochManager:");
  console.log(`   Address: ${epochManagerAddress}`);
  console.log(`   Owner: ${epochOwner}`);

  console.log("\n🔹 NFTPartnershipRegistry:");
  console.log(`   Address: ${nftRegistryAddress}`);
  console.log(`   Owner: ${nftOwner}`);
  console.log(
    `   First Bonus: ${firstBonus} bps (${Number(firstBonus) / 100}%)`
  );
  console.log(
    `   Decay Ratio: ${decayRatio} bps (${Number(decayRatio) / 100}%)`
  );

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

  console.log("\n🔹 VotingPowerMultiplier:");
  console.log(`   Address: ${votingPowerMultiplierAddress}`);
  console.log(`   Owner: ${vpOwner}`);
  console.log(`   DustLock: ${dustLockAddress}`);
  console.log(`   Tiers: ${tiers.length}`);

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

  // Verify contracts if requested
  if (shouldVerify) {
    console.log("\n🔍 Waiting before verification...");
    await new Promise((resolve) => setTimeout(resolve, 10000)); // Wait 10s

    console.log("\n🔍 Verifying EpochManager...");
    await verifyContract(hre, epochManagerAddress, [epochOwner]);

    console.log("\n🔍 Verifying NFTPartnershipRegistry...");
    await verifyContract(hre, nftRegistryAddress, [
      nftOwner,
      firstBonus,
      decayRatio,
    ]);

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

    console.log("\n🔍 Verifying VotingPowerMultiplier...");
    await verifyContract(hre, votingPowerMultiplierAddress, [
      vpOwner,
      dustLockAddress,
    ]);
  }

  // Save deployment info
  const deploymentInfo = {
    epochManager: epochManagerAddress,
    nftPartnershipRegistry: nftRegistryAddress,
    leaderboardConfig: leaderboardAddress,
    votingPowerMultiplier: votingPowerMultiplierAddress,
    deployer: deployerAddress,
    network: hre.network.name,
    timestamp: new Date().toISOString(),
    parameters: {
      addresses: {
        dustLock: dustLockAddress,
      },
      epochManager: {
        initialOwner: epochOwner,
      },
      nftRegistry: {
        initialOwner: nftOwner,
        firstBonus,
        decayRatio,
      },
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
      votingPowerMultiplier: {
        initialOwner: vpOwner,
        tiers,
      },
    },
  };

  const outputPath = path.resolve(
    __dirname,
    `../../deployments/leaderboard-${hre.network.name}-${Date.now()}.json`
  );
  fs.mkdirSync(path.dirname(outputPath), { recursive: true });
  fs.writeFileSync(outputPath, JSON.stringify(deploymentInfo, null, 2));
  console.log(`\n💾 Deployment info saved to ${outputPath}`);

  console.log("\n================ Post-Deployment Notes ==================");
  console.log("\n📌 EpochManager - Start the leaderboard:");
  console.log(
    "   • startNewEpoch() - Start epoch 1 (leaderboard currently NOT started)"
  );
  console.log("   • endCurrentEpoch() - End current epoch");
  console.log("   • currentEpoch = 0 until first startNewEpoch() is called");

  console.log("\n📌 NFTPartnershipRegistry - Manage NFT multipliers:");
  console.log(
    "   • setMultiplierParams(firstBonus, decayRatio) - Update global multiplier curve"
  );
  console.log(
    "   • addPartnership(collection, name, start, end) - Add NFT collection"
  );
  console.log(
    "   • updatePartnership(collection, active) - Enable/disable collection"
  );
  console.log("   • removePartnership(collection) - Remove collection");
  console.log(
    `   • Current multiplier: first=${Number(firstBonus) / 100}%, decay=${
      Number(decayRatio) / 100
    }%`
  );

  console.log("\n📌 LeaderboardConfig - Update point rates:");
  console.log("   • setDepositRate(uint256 newRateBps)");
  console.log("   • setBorrowRate(uint256 newRateBps)");
  console.log("   • setDailyBonuses(supply, borrow, repay, withdraw)");
  console.log("   • setCooldown(uint256 newSeconds)");
  console.log("   • setMinDailyBonusUsd(uint256 newMin)");
  console.log("   • updateAllRates(...) for batch updates");

  console.log("\n📌 VotingPowerMultiplier - Manage voting power tiers:");
  console.log("   • addTier(minVotingPower, multiplierBps) - Add new tier");
  console.log(
    "   • updateTier(tierIndex, minVotingPower, multiplierBps) - Update tier"
  );
  console.log("   • removeTier(tierIndex) - Remove tier");
  console.log("   • getUserMultiplier(address user) - Get user's multiplier");
  console.log(`   • Range: 1.0x (10000 bps) to 5.0x (50000 bps)`);

  console.log("\n📊 Events emitted for subgraph indexing:");
  console.log("   • EpochStarted / EpochEnded");
  console.log(
    "   • MultiplierParamsUpdated / PartnershipAdded / PartnershipUpdated"
  );
  console.log("   • TierAdded / TierUpdated / TierRemoved");
  console.log(
    "   • DepositRateUpdated / BorrowRateUpdated / DailyBonusUpdated"
  );
  console.log("   • ConfigSnapshot (on every config change)");

  console.log(
    "\n⚠️  Important: Leaderboard will NOT start until you call startNewEpoch()!"
  );
};

/*//////////////////////////////////////////////////////////////
                    TASK: DEPLOY LEADERBOARD
//////////////////////////////////////////////////////////////*/

task(
  "deploy:leaderboard",
  "Deploy complete leaderboard system (EpochManager, NFTPartnershipRegistry, LeaderboardConfig, VotingPowerMultiplier)"
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
      await deployLeaderboardConfig(hre, configPath, shouldVerify);
      console.log("\n🎉 Leaderboard deployment completed successfully!");
    } catch (error) {
      console.error("\n❌ Deployment failed:", error);
      throw error;
    }
  });

/*//////////////////////////////////////////////////////////////
              TASK: VALIDATE LEADERBOARD CONFIG
//////////////////////////////////////////////////////////////*/

task(
  "deploy:validate-leaderboard",
  "Validate leaderboard deployment configuration"
)
  .addOptionalParam(
    "configFile",
    "Path to deployment config JSON file",
    DEFAULT_CONFIG_PATH
  )
  .setAction(async (taskArgs: TaskArgs) => {
    const configPath = resolvePath(taskArgs.configFile || DEFAULT_CONFIG_PATH);

    try {
      console.log(`📄 Validating config: ${configPath}`);
      const config = loadConfig(configPath);

      const missing: string[] = [];

      // Validate addresses
      if (!config.addresses?.dustLock) {
        missing.push("addresses.dustLock");
      }

      // Validate LeaderboardConfig
      if (!config.leaderboard) {
        missing.push("leaderboard (entire section)");
      } else {
        const leaderboardRequired = [
          "initialOwner",
          "depositRateBps",
          "borrowRateBps",
          "supplyDailyBonus",
          "borrowDailyBonus",
          "cooldownSeconds",
        ];
        for (const field of leaderboardRequired) {
          const value = (config.leaderboard as any)[field];
          if (value === undefined || value === null || value === "") {
            missing.push(`leaderboard.${field}`);
          }
        }
      }

      // Validate EpochManager
      if (!config.epochManager) {
        missing.push("epochManager (entire section)");
      } else {
        const epochRequired = ["initialOwner"];
        for (const field of epochRequired) {
          const value = (config.epochManager as any)[field];
          if (value === undefined || value === null || value === "") {
            missing.push(`epochManager.${field}`);
          }
        }
      }

      // Validate NFTPartnershipRegistry
      if (!config.nftRegistry) {
        missing.push("nftRegistry (entire section)");
      } else {
        const nftRequired = ["initialOwner", "firstBonus", "decayRatio"];
        for (const field of nftRequired) {
          const value = (config.nftRegistry as any)[field];
          if (value === undefined || value === null || value === "") {
            missing.push(`nftRegistry.${field}`);
          }
        }
      }

      // Validate VotingPowerMultiplier
      if (!config.votingPowerMultiplier) {
        missing.push("votingPowerMultiplier (entire section)");
      } else {
        const vpRequired = ["initialOwner"];
        for (const field of vpRequired) {
          const value = (config.votingPowerMultiplier as any)[field];
          if (value === undefined || value === null || value === "") {
            missing.push(`votingPowerMultiplier.${field}`);
          }
        }
      }

      if (missing.length > 0) {
        console.log("❌ Missing required fields:");
        missing.forEach((field) => console.log(`  • ${field}`));
        throw new Error("Configuration validation failed");
      }

      console.log("✅ All required fields present");
      console.log("\n📋 Configuration Summary:");

      console.log("\n🔹 EpochManager:");
      console.log(`   Owner: ${config.epochManager!.initialOwner}`);

      console.log("\n🔹 NFTPartnershipRegistry:");
      console.log(`   Owner: ${config.nftRegistry!.initialOwner}`);
      console.log(
        `   First Bonus: ${config.nftRegistry!.firstBonus} bps (${
          Number(config.nftRegistry!.firstBonus) / 100
        }%)`
      );
      console.log(
        `   Decay Ratio: ${config.nftRegistry!.decayRatio} bps (${
          Number(config.nftRegistry!.decayRatio) / 100
        }%)`
      );

      console.log("\n🔹 LeaderboardConfig:");
      console.log(`   Owner: ${config.leaderboard!.initialOwner}`);
      console.log(`   Deposit Rate: ${config.leaderboard!.depositRateBps} bps`);
      console.log(`   Borrow Rate: ${config.leaderboard!.borrowRateBps} bps`);
      console.log(
        `   Supply Bonus: ${config.leaderboard!.supplyDailyBonus} points`
      );
      console.log(
        `   Borrow Bonus: ${config.leaderboard!.borrowDailyBonus} points`
      );

      console.log("\n🔹 VotingPowerMultiplier:");
      console.log(`   Owner: ${config.votingPowerMultiplier!.initialOwner}`);
      console.log(`   DustLock: ${config.addresses!.dustLock}`);
      console.log(
        `   Tiers: ${config.votingPowerMultiplier!.tiers?.length || 0}`
      );

      console.log("\n🎉 Config validation completed");
    } catch (error) {
      console.error("❌ Config validation failed:", error);
      throw error;
    }
  });
