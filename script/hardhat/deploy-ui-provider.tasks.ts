import { task } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";

task("deploy:ui-provider", "Deploy NeverlandUiProvider contract")
  .addFlag("verify", "Verify contract after deployment")
  .setAction(async (taskArgs, hre) => {
    // Compile contracts first to ensure latest changes
    console.log("📦 Compiling contracts...");
    await hre.run("compile");
    console.log("✅ Compilation complete");
    console.log("");
    
    console.log("=== Deploying NeverlandUiProvider ===");
    console.log(`Network: ${hre.network.name}`);
    console.log("");

    // Constructor arguments - Update these for your network
    const DUST_LOCK = "0x6bAf63f7959EA253006e7Af0BeFf29810CcbF661";
    const REVENUE_REWARD = "0x498d3bCB37b004f40EbAAF19fec0E6b9e61786a4";
    const DUST_REWARDS_CONTROLLER = "0x7f60150CaF5AA98A99E6EcD2e34E1E8A18d99174";
    const NEVERLAND_DUST_HELPER = "0x611Db9cb04B5a8E0B275712F263552dc522a3DDa";
    const AAVE_POOL_ADDRESSES_PROVIDER = "0x0bAe833178A7Ef0C5b47ca10D844736F65CBd499";

    const constructorArgs = [
      DUST_LOCK,
      REVENUE_REWARD,
      DUST_REWARDS_CONTROLLER,
      NEVERLAND_DUST_HELPER,
      AAVE_POOL_ADDRESSES_PROVIDER,
    ];

    console.log("Constructor arguments:");
    console.log("  DustLock:", DUST_LOCK);
    console.log("  RevenueReward:", REVENUE_REWARD);
    console.log("  DustRewardsController:", DUST_REWARDS_CONTROLLER);
    console.log("  DustHelper:", NEVERLAND_DUST_HELPER);
    console.log("  PoolAddressesProvider:", AAVE_POOL_ADDRESSES_PROVIDER);
    console.log("");

    // Deploy
    console.log("Deploying NeverlandUiProvider...");
    const NeverlandUiProvider = await hre.ethers.getContractFactory(
      "NeverlandUiProvider"
    );
    const uiProvider = await NeverlandUiProvider.deploy(...constructorArgs);
    await uiProvider.waitForDeployment();

    const address = await uiProvider.getAddress();
    console.log("✅ NeverlandUiProvider deployed at:", address);
    console.log("");

    // Verify if flag is set
    if (taskArgs.verify) {
      console.log("Waiting for 5 blocks before verification...");
      const deployTx = uiProvider.deploymentTransaction();
      if (deployTx) {
        await deployTx.wait(5);
      }
      console.log("");

      console.log("Verifying contract on block explorer...");
      try {
        await hre.run("verify:verify", {
          address: address,
          constructorArguments: constructorArgs,
        });
        console.log("✅ Contract verified successfully!");
      } catch (error: any) {
        if (error.message.includes("Already Verified")) {
          console.log("✅ Contract is already verified!");
        } else {
          console.error("❌ Verification failed:", error.message);
          console.log("");
          console.log("You can verify manually later with:");
          console.log(
            `npx hardhat verify --network ${hre.network.name} ${address} ${constructorArgs.join(" ")}`
          );
        }
      }
    } else {
      console.log("💡 To verify later, run:");
      console.log(
        `npx hardhat verify --network ${hre.network.name} ${address} ${constructorArgs.join(" ")}`
      );
    }

    console.log("");
    console.log("🎉 Deployment completed!");
    console.log("");
    console.log("📝 Save this address:");
    console.log(`   NeverlandUiProvider: ${address}`);
  });
