import { task } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import Enquirer from "enquirer";
import chalk from "chalk";
import { DeploymentResult } from "./types/deploy";
import {
  loadDeploymentConfig,
  getDefaultValue,
  resolveDependencies,
  sortContractsByDependencies,
  generateDeploymentExport,
} from "./helpers/deployment";
import { exportDeployments } from "./helpers/export";
import { CONTRACTS } from "./config/contracts";

const CONTRACTS_MAP = CONTRACTS as Record<string, any>;

// For backwards compatibility - can be removed later
const getContractConfig = (key: string) => CONTRACTS_MAP[key] || {};

task("deploy", "Interactive deployment of Neverland contracts")
  .setDescription(
    `Deploy Neverland contracts with an interactive wizard.

Features:
  - Multi-select contracts to deploy
  - Automatic dependency resolution
  - Configure parameters from defaults or custom input
  - Batch verification
  - Deployment summary with addresses

Example:
  npx hardhat deploy --network monad-testnet`
  )
  .setAction(async (taskArgs, hre) => {
    const enquirer = new Enquirer();

    try {
      console.log(
        chalk.cyan("\n═══════════════════════════════════════════════════════")
      );
      console.log(chalk.cyan("  Neverland Interactive Deployment"));
      console.log(
        chalk.cyan("═══════════════════════════════════════════════════════\n")
      );

      // Get deployer info
      const [deployer] = await hre.ethers.getSigners();
      console.log(chalk.gray(`Network: ${hre.network.name}`));
      console.log(chalk.gray(`Deployer: ${deployer.address}\n`));

      // Step 1: Select contracts to deploy
      console.log(chalk.cyan("📋 Step 1: Select Contracts to Deploy"));
      console.log(chalk.gray("  Use SPACE to select, ENTER to confirm\n"));

      const contractChoices = Object.entries(CONTRACTS).map(
        ([key, config]) => ({
          name: key,
          message: `${config.displayName} - ${config.description}`,
          value: key,
        })
      );

      const selectedResponse: any = await enquirer.prompt({
        type: "multiselect",
        name: "contracts",
        message: "Select contracts to deploy:",
        choices: contractChoices,
      });

      let selectedContracts = selectedResponse.contracts;

      if (!selectedContracts || selectedContracts.length === 0) {
        console.log(chalk.yellow("\n✗ No contracts selected. Exiting."));
        return;
      }

      console.log(
        chalk.green(`\n✓ Selected ${selectedContracts.length} contract(s)\n`)
      );

      // Load network config first to check for existing deployments
      const networkConfig = loadDeploymentConfig(hre.network.name);
      const existingDeployments = networkConfig.addresses || {};

      // Step 2: Resolve dependencies
      console.log(chalk.cyan("🔗 Step 2: Checking Dependencies"));

      const { allContracts: allContractsNeeded, addedDeps } =
        resolveDependencies(selectedContracts, getContractConfig);

      // Check which contracts are already deployed
      const alreadyDeployed: string[] = [];
      const notDeployed: string[] = [];

      for (const contractKey of Array.from(allContractsNeeded)) {
        if (existingDeployments[contractKey]) {
          alreadyDeployed.push(contractKey);
          console.log(
            chalk.gray(
              `  ✓ ${contractKey} already deployed at ${existingDeployments[contractKey]}`
            )
          );
        } else {
          notDeployed.push(contractKey);
          console.log(chalk.yellow(`  + ${contractKey} needs deployment`));
        }
      }

      // If some contracts are already deployed, ask user what to do
      let contractsToDeploy = new Set<string>(notDeployed);

      if (alreadyDeployed.length > 0) {
        console.log("");
        const redeployChoice: any = await enquirer.prompt({
          type: "select",
          name: "action",
          message: `${alreadyDeployed.length} contract(s) already deployed. What would you like to do?`,
          choices: [
            {
              name: "use",
              message: `Use existing deployments (recommended)`,
              value: "use",
            },
            {
              name: "redeploy-selected",
              message: `Redeploy only selected contracts (${selectedContracts.join(", ")})`,
              value: "redeploy-selected",
            },
            {
              name: "redeploy-all",
              message: `Redeploy all contracts including dependencies`,
              value: "redeploy-all",
            },
          ],
          initial: 0,
        });

        if (redeployChoice.action === "redeploy-selected") {
          // Only redeploy the originally selected contracts if they exist
          for (const contract of selectedContracts) {
            if (alreadyDeployed.includes(contract)) {
              contractsToDeploy.add(contract);
              console.log(chalk.yellow(`  ⚠️  Will redeploy: ${contract}`));
            }
          }
        } else if (redeployChoice.action === "redeploy-all") {
          // Redeploy everything
          contractsToDeploy = new Set<string>(Array.from(allContractsNeeded));
          console.log(
            chalk.yellow(
              `  ⚠️  Will redeploy all ${contractsToDeploy.size} contract(s)`
            )
          );
        }
      }

      // Sort by dependencies (topological sort)
      let sortedContracts: string[];
      try {
        sortedContracts = sortContractsByDependencies(
          contractsToDeploy,
          getContractConfig
        );
      } catch (error: any) {
        console.log(chalk.red(`\n✗ ${error.message}`));
        return;
      }

      if (sortedContracts.length === 0) {
        console.log(
          chalk.green(
            "\n✓ Using existing deployments - no new contracts to deploy!"
          )
        );
        console.log(chalk.white("\n📝 Existing Addresses:\n"));
        for (const contractKey of Array.from(allContractsNeeded)) {
          console.log(chalk.white(`  ${contractKey}:`));
          console.log(chalk.gray(`    ${existingDeployments[contractKey]}`));
        }
        console.log(
          chalk.white(
            "\n💡 To redeploy, run the command again and choose a different option."
          )
        );
        return;
      }

      console.log(
        chalk.green(`✓ Deployment order: ${sortedContracts.join(" → ")}\n`)
      );

      // Step 3: Configure parameters
      console.log(chalk.cyan("⚙️  Step 3: Configure Parameters"));
      console.log(chalk.gray(`  Loaded config for: ${hre.network.name}\n`));

      const useDefaultsResponse: any = await enquirer.prompt({
        type: "confirm",
        name: "useDefaults",
        message: "Use default/previous deployment addresses where available?",
        initial: true,
      });

      const deploymentParams: Record<string, string[]> = {};
      // Initialize with existing deployments so they can be used as dependencies
      const deployedAddresses: Record<string, string> = {
        ...existingDeployments,
      };

      // Track which contracts will be deployed (to avoid using old addresses)
      const contractsBeingDeployed = new Set(sortedContracts);

      for (const contractKey of sortedContracts) {
        const config = CONTRACTS[contractKey];
        console.log(chalk.white(`\n  ${config.displayName}:`));

        const params: string[] = [];

        for (const param of config.constructorParams) {
          let value: string;

          // Check if this dependency will be deployed in this session
          const isDependencyBeingDeployed =
            param.configKey && contractsBeingDeployed.has(param.configKey);

          // Try to get default value from config (but NOT if dependency is being redeployed)
          const defaultValue = !isDependencyBeingDeployed
            ? getDefaultValue(
                param.name,
                param.configKey,
                networkConfig,
                deployedAddresses
              )
            : undefined;

          // Check if this is a dependency contract (check by configKey first)
          const deployedByConfigKey =
            param.configKey &&
            deployedAddresses[param.configKey] &&
            !isDependencyBeingDeployed;
          const deployedByParamName =
            deployedAddresses[param.name] && !isDependencyBeingDeployed;

          // Special case: dependency will be deployed in this session
          if (isDependencyBeingDeployed) {
            // Use placeholder that will be filled after deployment
            value = `__PLACEHOLDER__:${param.configKey}`;
            console.log(
              chalk.yellow(
                `    ${param.name}: Will use newly deployed ${param.configKey} address`
              )
            );
          }
          // If user wants to use defaults, auto-fill
          else if (useDefaultsResponse.useDefaults) {
            if (deployedByConfigKey) {
              value = deployedAddresses[param.configKey!];
              const source = existingDeployments[param.configKey!]
                ? "existing deployment"
                : "this session";
              console.log(
                chalk.gray(`    ${param.name}: ${value} (from ${source})`)
              );
            } else if (deployedByParamName) {
              value = deployedAddresses[param.name];
              console.log(
                chalk.gray(`    ${param.name}: ${value} (from this session)`)
              );
            } else if (defaultValue) {
              value = defaultValue;
              console.log(
                chalk.gray(`    ${param.name}: ${value} (from config)`)
              );
            } else {
              // No default available, must prompt
              const paramResponse: any = await enquirer.prompt({
                type: "input",
                name: "value",
                message: `  ${param.name} (${param.type}):`,
                initial: "",
                validate: (input: string) => {
                  if (!input) return "Value is required";
                  if (
                    param.type === "address" &&
                    !hre.ethers.isAddress(input)
                  ) {
                    return "Invalid address format";
                  }
                  return true;
                },
              });
              value = paramResponse.value;
            }
          } else {
            // User wants to customize - ALWAYS prompt but show default as placeholder
            const source = deployedByConfigKey
              ? existingDeployments[param.configKey!]
                ? "existing deployment"
                : "this session"
              : deployedByParamName
                ? "this session"
                : defaultValue
                  ? "config"
                  : null;

            const paramResponse: any = await enquirer.prompt({
              type: "input",
              name: "value",
              message: `  ${param.name} (${param.type})${
                source ? ` [default: from ${source}]` : ""
              }:`,
              initial: defaultValue || "",
              validate: (input: string) => {
                if (!input) return "Value is required";
                if (param.type === "address" && !hre.ethers.isAddress(input)) {
                  return "Invalid address format";
                }
                return true;
              },
            });
            value = paramResponse.value;
          }

          params.push(value);
        }

        deploymentParams[contractKey] = params;
      }

      // Step 4: Verification option
      console.log(chalk.cyan("\n📝 Step 4: Verification"));

      const verifyResponse: any = await enquirer.prompt({
        type: "confirm",
        name: "verify",
        message: "Verify contracts on block explorer after deployment?",
        initial: true,
      });

      // Step 5: Summary and confirmation
      console.log(
        chalk.cyan("\n═══════════════════════════════════════════════════════")
      );
      console.log(chalk.cyan("  Deployment Summary"));
      console.log(
        chalk.cyan("═══════════════════════════════════════════════════════\n")
      );

      console.log(chalk.white(`Network: ${hre.network.name}`));
      console.log(chalk.white(`Deployer: ${deployer.address}`));
      console.log(chalk.white(`Contracts: ${sortedContracts.length}`));
      console.log(
        chalk.white(`Verification: ${verifyResponse.verify ? "Yes" : "No"}\n`)
      );

      for (const contractKey of sortedContracts) {
        const config = CONTRACTS[contractKey];
        console.log(chalk.white(`\n  • ${config.displayName}`));
        if (deploymentParams[contractKey].length > 0) {
          console.log(chalk.gray(`    Constructor parameters:`));
          deploymentParams[contractKey].forEach((param, idx) => {
            const paramDef = config.constructorParams[idx];
            if (
              typeof param === "string" &&
              param.startsWith("__PLACEHOLDER__:")
            ) {
              const dependencyKey = param.replace("__PLACEHOLDER__:", "");
              console.log(
                chalk.yellow(
                  `      ${paramDef.name}: <will use newly deployed ${dependencyKey}>`
                )
              );
            } else {
              console.log(chalk.gray(`      ${paramDef.name}: ${param}`));
            }
          });
        } else {
          console.log(chalk.gray(`    No constructor parameters`));
        }
      }

      const confirmResponse: any = await enquirer.prompt({
        type: "confirm",
        name: "confirm",
        message: chalk.yellow("\n⚠️  Proceed with deployment?"),
        initial: true,
      });

      if (!confirmResponse.confirm) {
        console.log(chalk.yellow("\n✗ Deployment cancelled."));
        return;
      }

      // Step 6: Deploy contracts
      console.log(
        chalk.cyan("\n═══════════════════════════════════════════════════════")
      );
      console.log(chalk.cyan("  Deployment"));
      console.log(
        chalk.cyan("═══════════════════════════════════════════════════════\n")
      );

      // Compile contracts silently (capture output)
      process.stdout.write(chalk.gray("📦 Compiling contracts... "));
      try {
        await hre.run("compile", { quiet: true });
        console.log(chalk.green("✓"));
      } catch (error) {
        console.log(chalk.red("✗"));
        // Run again with output to show the error
        console.log(chalk.yellow("\nCompilation failed. Showing details:\n"));
        await hre.run("compile");
        throw error;
      }
      console.log("");

      const deploymentResults: DeploymentResult[] = [];

      for (const contractKey of sortedContracts) {
        const config = CONTRACTS[contractKey];
        let params = deploymentParams[contractKey];

        // Replace placeholders with actual deployed addresses
        params = params.map((param) => {
          if (
            typeof param === "string" &&
            param.startsWith("__PLACEHOLDER__:")
          ) {
            const dependencyKey = param.replace("__PLACEHOLDER__:", "");
            const actualAddress = deployedAddresses[dependencyKey];
            if (!actualAddress) {
              throw new Error(
                `Missing dependency: ${dependencyKey} should have been deployed first`
              );
            }
            console.log(
              chalk.gray(
                `  Replacing placeholder for ${dependencyKey} with ${actualAddress}`
              )
            );
            return actualAddress;
          }
          return param;
        });

        console.log(chalk.yellow(`\n⏳ Deploying ${config.displayName}...`));

        try {
          // Predict contract address before deployment
          const currentNonce = await deployer.getNonce();
          const predictedAddress = hre.ethers.getCreateAddress({
            from: deployer.address,
            nonce: currentNonce,
          });

          console.log(chalk.gray(`  Predicted address: ${predictedAddress}`));
          console.log(chalk.gray(`  Nonce: ${currentNonce}`));

          const ContractFactory = await hre.ethers.getContractFactory(
            config.name
          );
          const contract = await ContractFactory.deploy(...params);
          await contract.waitForDeployment();

          const address = await contract.getAddress();
          // Store with both PascalCase (contract name) and lowercase for lookups
          deployedAddresses[contractKey] = address;
          deployedAddresses[contractKey.toLowerCase()] = address;

          // Verify prediction
          if (address.toLowerCase() === predictedAddress.toLowerCase()) {
            console.log(
              chalk.green(
                `✓ ${config.displayName} deployed at ${address} ✓ (predicted correctly)`
              )
            );
          } else {
            console.log(
              chalk.green(`✓ ${config.displayName} deployed at ${address}`)
            );
            console.log(
              chalk.yellow(`  ⚠️  Predicted: ${predictedAddress} (mismatch)`)
            );
          }

          deploymentResults.push({
            name: config.name,
            address,
            params,
          });
        } catch (error: any) {
          console.log(chalk.red(`✗ Failed to deploy ${config.displayName}`));
          console.log(chalk.red(`  Error: ${error.message}`));
          throw error;
        }
      }

      // Step 7: Verification
      if (verifyResponse.verify) {
        console.log(
          chalk.cyan(
            "\n═══════════════════════════════════════════════════════"
          )
        );
        console.log(chalk.cyan("  Verification"));
        console.log(
          chalk.cyan(
            "═══════════════════════════════════════════════════════\n"
          )
        );

        console.log(chalk.gray("Waiting 10s before verification...\n"));
        await new Promise((resolve) => setTimeout(resolve, 10000));

        for (const result of deploymentResults) {
          console.log(chalk.yellow(`\n⏳ Verifying ${result.name}...`));

          try {
            await hre.run("verify:verify", {
              address: result.address,
              constructorArguments: result.params,
            });
            console.log(chalk.green(`✓ ${result.name} verified`));
          } catch (error: any) {
            if (error.message.includes("Already Verified")) {
              console.log(chalk.green(`✓ ${result.name} already verified`));
            } else {
              console.log(
                chalk.yellow(`⚠️  ${result.name} verification failed`)
              );
              console.log(chalk.gray(`  ${error.message}`));
            }
          }
        }
      }

      // Final summary
      console.log(
        chalk.cyan("\n═══════════════════════════════════════════════════════")
      );
      console.log(chalk.cyan("  Deployment Complete"));
      console.log(
        chalk.cyan("═══════════════════════════════════════════════════════\n")
      );

      console.log(
        chalk.green(
          `✅ Successfully deployed ${deploymentResults.length} contract(s)\n`
        )
      );

      console.log(chalk.white("📝 Deployed Addresses:\n"));
      for (const result of deploymentResults) {
        console.log(chalk.white(`  ${result.name}:`));
        console.log(chalk.gray(`    ${result.address}`));
      }

      console.log(
        chalk.white("\n💡 Save these addresses for future deployments!")
      );

      // Save deployments to standard location (addresses.json + individual files)
      const deploymentsToExport: Record<string, any> = {};
      for (const result of deploymentResults) {
        deploymentsToExport[result.name] = {
          address: result.address,
          constructorArgs: [], // Could be enhanced to include actual args
          metadata: {
            deployer: deployer.address,
            timestamp: Date.now(),
            chainId: hre.network.config.chainId,
          },
        };
      }

      await exportDeployments(hre, deploymentsToExport);

      console.log(
        chalk.green(
          `\n✅ All deployments saved to deployments/${hre.network.name}/`
        )
      );
    } catch (error: any) {
      console.error(
        chalk.red("\n✗ Deployment failed:"),
        error.message || error
      );
      throw error;
    }
  });
