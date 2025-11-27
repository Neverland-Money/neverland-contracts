import { task } from "hardhat/config";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import Enquirer from "enquirer";
import chalk from "chalk";
import fs from "fs";
import path from "path";

const enquirer = new Enquirer();

interface SetupConfig {
  helperAddress?: string;
  dustPair?: string;
  pairOracle?: string;
  v4Pool?: {
    poolManager: string;
    poolId: string;
    isDustToken0: boolean;
  };
}

/**
 * Interactive task to setup NeverlandDustHelper oracle configuration
 * Supports:
 * - Direct DUST/USD oracle (only dustPair needed)
 * - Two-step conversion: DUST/<PAIR> + <PAIR>/USD
 * - Uniswap V2/V3/V4 pools with oracle
 */
task(
  "setup:dusthelper",
  "Configure NeverlandDustHelper oracle settings"
).setAction(async (_, hre: HardhatRuntimeEnvironment) => {
  console.log(chalk.blue("\n🔧 NeverlandDustHelper Setup\n"));

  const network = hre.network.name;
  const deploymentsDir = path.join(__dirname, "../../deployments", network);
  const addressesFile = path.join(deploymentsDir, "addresses.json");

  let existingAddresses: Record<string, string> = {};
  if (fs.existsSync(addressesFile)) {
    existingAddresses = JSON.parse(fs.readFileSync(addressesFile, "utf-8"));
  }

  const config = await promptSetupConfig(existingAddresses);

  // Display summary
  displaySetupSummary(config);

  const confirm: any = await enquirer.prompt({
    type: "confirm",
    name: "confirm",
    message: "Proceed with this configuration?",
    initial: true,
  });

  if (!confirm.confirm) {
    console.log(chalk.yellow("Setup cancelled."));
    return;
  }

  // Execute setup
  await executeSetup(hre, config);

  console.log(chalk.green("\n✅ Setup complete!\n"));
});

async function promptSetupConfig(
  existingAddresses: Record<string, string>
): Promise<SetupConfig> {
  const config: SetupConfig = {};

  // Step 1: Get NeverlandDustHelper address
  const helperSource: any = await enquirer.prompt({
    type: "select",
    name: "helperSource",
    message: "NeverlandDustHelper address:",
    choices: [
      {
        name: "deployed",
        message: `Use deployed (${existingAddresses.NeverlandDustHelper || "not found"})`,
        value: "deployed",
        disabled: !existingAddresses.NeverlandDustHelper,
      },
      {
        name: "manual",
        message: "Enter manually",
        value: "manual",
      },
    ],
  });

  if (helperSource.helperSource === "deployed") {
    config.helperAddress = existingAddresses.NeverlandDustHelper;
  } else {
    const address: any = await enquirer.prompt({
      type: "input",
      name: "address",
      message: "NeverlandDustHelper address:",
      validate: (input: string) => {
        if (!input.match(/^0x[a-fA-F0-9]{40}$/)) {
          return "Invalid Ethereum address";
        }
        return true;
      },
    });
    config.helperAddress = address.address;
  }

  console.log(
    chalk.gray(`\nUsing NeverlandDustHelper: ${config.helperAddress}\n`)
  );

  // Step 2: Determine setup type
  const setupType: any = await enquirer.prompt({
    type: "select",
    name: "setupType",
    message: "What type of price setup do you want?",
    choices: [
      {
        name: "direct",
        message: "Direct DUST/USD oracle (single oracle, no pairOracle needed)",
        value: "direct",
      },
      {
        name: "two-step-oracle",
        message: "Two-step: DUST/<PAIR> oracle + <PAIR>/USD oracle",
        value: "two-step-oracle",
      },
      {
        name: "two-step-v3",
        message: "Two-step: Uniswap V3 pool + <PAIR>/USD oracle",
        value: "two-step-v3",
      },
      {
        name: "two-step-v2",
        message: "Two-step: Uniswap V2 pool + <PAIR>/USD oracle",
        value: "two-step-v2",
      },
      {
        name: "v4-pool",
        message: "Uniswap V4 pool (direct DUST/<PAIR> price from V4)",
        value: "v4-pool",
      },
      {
        name: "custom",
        message: "Custom (manually specify both addresses)",
        value: "custom",
      },
    ],
  });

  // Step 3: Get addresses based on setup type
  if (setupType.setupType === "direct") {
    console.log(
      chalk.cyan(
        "\n💡 Direct DUST/USD oracle setup - only dustPair (setPair) is needed"
      )
    );
    console.log(
      chalk.gray(
        "   The oracle should return DUST/USD price directly (e.g., Chainlink DUST/USD feed)\n"
      )
    );

    const dustPair: any = await enquirer.prompt({
      type: "input",
      name: "dustPair",
      message: "DUST/USD oracle address:",
      validate: (input: string) => {
        if (!input.match(/^0x[a-fA-F0-9]{40}$/)) {
          return "Invalid Ethereum address";
        }
        return true;
      },
    });
    config.dustPair = dustPair.dustPair;
    config.pairOracle = undefined; // Explicitly not setting pairOracle
  } else if (setupType.setupType === "two-step-oracle") {
    console.log(
      chalk.cyan(
        "\n💡 Two-step oracle setup - DUST/<PAIR> oracle + <PAIR>/USD oracle"
      )
    );
    console.log(
      chalk.gray("   Example: DUST/MON oracle (or MON/DUST) + MON/USD oracle\n")
    );

    const dustPair: any = await enquirer.prompt({
      type: "input",
      name: "dustPair",
      message:
        "DUST/<PAIR> oracle address (can be UniV3 TWAP oracle or Chainlink):",
      validate: (input: string) => {
        if (!input.match(/^0x[a-fA-F0-9]{40}$/)) {
          return "Invalid Ethereum address";
        }
        return true;
      },
    });
    const pairOracle: any = await enquirer.prompt({
      type: "input",
      name: "pairOracle",
      message: "<PAIR>/USD Chainlink oracle address:",
      validate: (input: string) => {
        if (!input.match(/^0x[a-fA-F0-9]{40}$/)) {
          return "Invalid Ethereum address";
        }
        return true;
      },
    });
    config.dustPair = dustPair.dustPair;
    config.pairOracle = pairOracle.pairOracle;
  } else if (setupType.setupType === "two-step-v3") {
    console.log(chalk.cyan("\n💡 Uniswap V3 pool + oracle setup"));
    console.log(
      chalk.gray(
        "   Uses V3 pool for DUST/<PAIR> price, oracle for <PAIR>/USD\n"
      )
    );

    const dustPair: any = await enquirer.prompt({
      type: "input",
      name: "dustPair",
      message: "Uniswap V3 pool address (DUST/<PAIR> or <PAIR>/DUST):",
      validate: (input: string) => {
        if (!input.match(/^0x[a-fA-F0-9]{40}$/)) {
          return "Invalid Ethereum address";
        }
        return true;
      },
    });
    const pairOracle: any = await enquirer.prompt({
      type: "input",
      name: "pairOracle",
      message: "<PAIR>/USD Chainlink oracle address:",
      validate: (input: string) => {
        if (!input.match(/^0x[a-fA-F0-9]{40}$/)) {
          return "Invalid Ethereum address";
        }
        return true;
      },
    });
    config.dustPair = dustPair.dustPair;
    config.pairOracle = pairOracle.pairOracle;
  } else if (setupType.setupType === "two-step-v2") {
    console.log(chalk.cyan("\n💡 Uniswap V2 pool + oracle setup"));
    console.log(
      chalk.gray(
        "   Uses V2 pool for DUST/<PAIR> price, oracle for <PAIR>/USD\n"
      )
    );

    const dustPair: any = await enquirer.prompt({
      type: "input",
      name: "dustPair",
      message: "Uniswap V2 pool address (DUST/<PAIR> or <PAIR>/DUST):",
      validate: (input: string) => {
        if (!input.match(/^0x[a-fA-F0-9]{40}$/)) {
          return "Invalid Ethereum address";
        }
        return true;
      },
    });
    const pairOracle: any = await enquirer.prompt({
      type: "input",
      name: "pairOracle",
      message: "<PAIR>/USD Chainlink oracle address:",
      validate: (input: string) => {
        if (!input.match(/^0x[a-fA-F0-9]{40}$/)) {
          return "Invalid Ethereum address";
        }
        return true;
      },
    });
    config.dustPair = dustPair.dustPair;
    config.pairOracle = pairOracle.pairOracle;
  } else if (setupType.setupType === "v4-pool") {
    console.log(chalk.cyan("\n💡 Uniswap V4 pool setup"));
    console.log(
      chalk.gray(
        "   Uses V4 PoolManager to read pool state for DUST/<PAIR> price\n"
      )
    );

    const poolManager: any = await enquirer.prompt({
      type: "input",
      name: "poolManager",
      message: "V4 PoolManager address:",
      validate: (input: string) => {
        if (!input.match(/^0x[a-fA-F0-9]{40}$/)) {
          return "Invalid Ethereum address";
        }
        return true;
      },
    });

    const poolId: any = await enquirer.prompt({
      type: "input",
      name: "poolId",
      message: "Pool ID (bytes32 from explorer):",
      validate: (input: string) => {
        if (!input.match(/^0x[a-fA-F0-9]{64}$/)) {
          return "Invalid bytes32 (should be 0x followed by 64 hex characters)";
        }
        return true;
      },
    });

    const isDustToken0: any = await enquirer.prompt({
      type: "confirm",
      name: "isDustToken0",
      message: "Is DUST currency0 (token0) in the pool?",
      initial: false,
    });

    config.v4Pool = {
      poolManager: poolManager.poolManager,
      poolId: poolId.poolId,
      isDustToken0: isDustToken0.isDustToken0,
    };

    // V4 gives us DUST/<PAIR> price, we need <PAIR>/USD oracle for complete conversion
    console.log(
      chalk.cyan(
        "\n💡 V4 pool provides DUST/<PAIR> price. You also need <PAIR>/USD oracle."
      )
    );
    console.log(
      chalk.gray("   Example: V4 gives DUST/WMON, oracle gives WMON/USD\n")
    );

    const pairOracle: any = await enquirer.prompt({
      type: "input",
      name: "pairOracle",
      message: "<PAIR>/USD oracle address (e.g., WMON/USD):",
      validate: (input: string) => {
        if (!input.match(/^0x[a-fA-F0-9]{40}$/)) {
          return "Invalid Ethereum address";
        }
        return true;
      },
    });
    config.pairOracle = pairOracle.pairOracle;
  } else {
    // custom
    console.log(chalk.cyan("\n💡 Custom setup"));

    const setDustPair: any = await enquirer.prompt({
      type: "confirm",
      name: "setDustPair",
      message: "Set dustPair (setPair)?",
      initial: true,
    });

    if (setDustPair.setDustPair) {
      const dustPair: any = await enquirer.prompt({
        type: "input",
        name: "dustPair",
        message: "dustPair address (pool or oracle):",
        validate: (input: string) => {
          if (!input.match(/^0x[a-fA-F0-9]{40}$/)) {
            return "Invalid Ethereum address";
          }
          return true;
        },
      });
      config.dustPair = dustPair.dustPair;
    }

    const setPairOracle: any = await enquirer.prompt({
      type: "confirm",
      name: "setPairOracle",
      message: "Set pairOracle (setPairOracle)?",
      initial: !!config.dustPair, // Default yes if dustPair is set
    });

    if (setPairOracle.setPairOracle) {
      const pairOracle: any = await enquirer.prompt({
        type: "input",
        name: "pairOracle",
        message: "<PAIR>/USD oracle address:",
        validate: (input: string) => {
          if (!input.match(/^0x[a-fA-F0-9]{40}$/)) {
            return "Invalid Ethereum address";
          }
          return true;
        },
      });
      config.pairOracle = pairOracle.pairOracle;
    }
  }

  return config;
}

function displaySetupSummary(config: SetupConfig) {
  console.log(chalk.blue("\n📋 Setup Summary:\n"));
  console.log(chalk.gray(`NeverlandDustHelper: ${config.helperAddress}`));

  if (config.dustPair) {
    console.log(chalk.gray(`dustPair (setPair):  ${config.dustPair}`));
  } else {
    console.log(chalk.gray(`dustPair (setPair):  [not set]`));
  }

  if (config.pairOracle) {
    console.log(chalk.gray(`pairOracle:          ${config.pairOracle}`));
  } else {
    console.log(chalk.gray(`pairOracle:          [not set]`));
  }

  if (config.v4Pool) {
    console.log(chalk.gray(`\nV4 Pool Configuration:`));
    console.log(chalk.gray(`  poolManager:       ${config.v4Pool.poolManager}`));
    console.log(chalk.gray(`  poolId:            ${config.v4Pool.poolId}`));
    console.log(chalk.gray(`  isDustToken0:      ${config.v4Pool.isDustToken0}`));
  }

  console.log();

  // Explain the configuration
  if (config.v4Pool) {
    console.log(chalk.cyan("📊 Configuration: Uniswap V4 pool"));
    console.log(
      chalk.gray(
        "   → Will use V4 PoolManager to read DUST/<PAIR> price directly"
      )
    );
    console.log(
      chalk.gray(
        "   → Auto-detects price and will be tried first before V3/V2/Chainlink"
      )
    );
  } else if (config.dustPair && !config.pairOracle) {
    console.log(chalk.cyan("📊 Configuration: Direct DUST/USD oracle"));
    console.log(
      chalk.gray("   → dustPair will be used as direct DUST/USD price source")
    );
  } else if (config.dustPair && config.pairOracle) {
    console.log(chalk.cyan("📊 Configuration: Two-step conversion"));
    console.log(
      chalk.gray(
        "   → DUST/USD = DUST/<PAIR> (from dustPair) × <PAIR>/USD (from pairOracle)"
      )
    );
  } else if (!config.dustPair && config.pairOracle) {
    console.log(chalk.yellow("⚠️  Warning: Only pairOracle set"));
    console.log(
      chalk.gray(
        "   → This configuration won't work. You need at least dustPair."
      )
    );
  } else {
    console.log(chalk.yellow("⚠️  No oracles will be set"));
    console.log(chalk.gray("   → Contract will use hardcoded price"));
  }
  console.log();
}

async function executeSetup(
  hre: HardhatRuntimeEnvironment,
  config: SetupConfig
) {
  const [signer] = await hre.ethers.getSigners();
  console.log(chalk.gray(`Using account: ${signer.address}\n`));

  // Get contract instance
  const helper = await hre.ethers.getContractAt(
    "NeverlandDustHelper",
    config.helperAddress!,
    signer
  );

  // Set dustPair if provided
  if (config.dustPair) {
    console.log(chalk.cyan(`Setting dustPair to ${config.dustPair}...`));
    const tx1 = await helper.setPair(config.dustPair);
    console.log(chalk.gray(`  Transaction: ${tx1.hash}`));
    await tx1.wait();
    console.log(chalk.green("  ✓ dustPair set"));
  }

  // Set pairOracle if provided
  if (config.pairOracle) {
    console.log(chalk.cyan(`\nSetting pairOracle to ${config.pairOracle}...`));
    const tx2 = await helper.setPairOracle(config.pairOracle);
    console.log(chalk.gray(`  Transaction: ${tx2.hash}`));
    await tx2.wait();
    console.log(chalk.green("  ✓ pairOracle set"));
  }

  // Set V4 pool if provided
  if (config.v4Pool) {
    console.log(chalk.cyan(`\nSetting V4 pool configuration...`));
    const tx3 = await helper.setV4Pool(
      config.v4Pool.poolManager,
      config.v4Pool.poolId,
      config.v4Pool.isDustToken0
    );
    console.log(chalk.gray(`  Transaction: ${tx3.hash}`));
    await tx3.wait();
    console.log(chalk.green("  ✓ V4 pool configured"));
  }

  // Update price cache to test configuration
  console.log(chalk.cyan("\nUpdating price cache to verify configuration..."));
  try {
    const tx4 = await helper.updatePriceCache();
    console.log(chalk.gray(`  Transaction: ${tx4.hash}`));
    await tx4.wait();
    console.log(chalk.green("  ✓ Price cache updated successfully"));

    // Get and display current price
    const [price, fromOracle] = await helper.getPrice();
    const priceFormatted = hre.ethers.formatUnits(price, 8);
    console.log(
      chalk.gray(
        `\n  Current DUST/USD price: $${priceFormatted} (${fromOracle ? "from oracle" : "hardcoded"})`
      )
    );
  } catch (error: any) {
    console.log(chalk.red("  ✗ Failed to update price cache"));
    console.log(chalk.gray(`  Error: ${error.message}`));
    console.log(
      chalk.yellow(
        "\n  ⚠️  This might indicate an issue with the oracle configuration."
      )
    );
    console.log(
      chalk.gray(
        "     Common causes: wrong addresses, oracles returning invalid data, or price out of bounds.\n"
      )
    );
  }
}

// Export for testing
export { promptSetupConfig, displaySetupSummary, executeSetup };
