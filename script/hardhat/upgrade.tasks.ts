import { task } from "hardhat/config";
import type { ContractFactory } from "ethers";
import type { HardhatRuntimeEnvironment } from "hardhat/types";
import fs from "fs";
import path from "path";

/*//////////////////////////////////////////////////////////////
                   IMPLEMENTATION DEPLOY HELPERS
//////////////////////////////////////////////////////////////*/
task("deployImpl:DustLock", "Deploy new DustLock implementation")
  .addParam("forwarder", "Trusted forwarder address")
  .addParam("balancelib", "Deployed BalanceLogicLibrary address")
  .setAction(async (args, hre) => {
    const { forwarder, balancelib } = args as { forwarder: string; balancelib: string };
    const factory: ContractFactory = await hre.ethers.getContractFactory("DustLock", {
      libraries: { BalanceLogicLibrary: balancelib },
    });
    const impl = await factory.deploy(forwarder);
    await impl.waitForDeployment();
    console.log("DustLock impl:", await impl.getAddress());
  });

task("deployImpl:RevenueReward", "Deploy new RevenueReward implementation")
  .addParam("forwarder", "Trusted forwarder address")
  .setAction(async (args, hre) => {
    const { forwarder } = args as { forwarder: string };
    const factory = await hre.ethers.getContractFactory("RevenueReward");
    const impl = await factory.deploy(forwarder);
    await impl.waitForDeployment();
    console.log("RevenueReward impl:", await impl.getAddress());
  });

/*//////////////////////////////////////////////////////////////
                 PROXY ADMIN UPGRADE (GENERIC)
//////////////////////////////////////////////////////////////*/
task("upgrade:proxy", "Upgrade a TransparentUpgradeableProxy via ProxyAdmin")
  .addParam("proxyadmin", "ProxyAdmin address")
  .addParam("proxy", "Proxy address to upgrade")
  .addParam("impl", "New implementation address")
  .setAction(async (args, hre) => {
    const { proxyadmin, proxy, impl } = args as { proxyadmin: string; proxy: string; impl: string };
    const signer = (await hre.ethers.getSigners())[0];
    const admin = await hre.ethers.getContractAt("ProxyAdmin", proxyadmin, signer);
    const tx = await admin.upgrade(proxy, impl);
    console.log("Upgrade tx:", tx.hash);
    await tx.wait();
    console.log("Upgraded", proxy, "->", impl);
  });

/*//////////////////////////////////////////////////////////////
                           CONFIG + IO
//////////////////////////////////////////////////////////////*/
const DEFAULT_CONFIG_PATH = path.resolve(__dirname, "../hardhat/config/deploy.json");
function loadConfig(p: string): any {
  if (!fs.existsSync(p)) throw new Error(`Config not found: ${p}`);
  return JSON.parse(fs.readFileSync(p, "utf8"));
}

async function showImplChange(hre: HardhatRuntimeEnvironment, proxyAddr: string, label: string): Promise<void> {
  const before = await hre.upgrades.erc1967.getImplementationAddress(proxyAddr);
  console.log(`• ${label} impl before: ${before}`);
  const after = await hre.upgrades.erc1967.getImplementationAddress(proxyAddr);
  console.log(`• ${label} impl after:  ${after}`);
  if (before.toLowerCase() === after.toLowerCase()) {
    console.warn("⚠️  Implementation unchanged. Ensure code diff or use redeployImplementation option.");
  }
}

/*//////////////////////////////////////////////////////////////
                        UPGRADE: DUST
//////////////////////////////////////////////////////////////*/
task("upgrade:dust", "Upgrade Dust proxy using a fresh implementation")
  .addOptionalParam("proxy", "Dust proxy address (defaults to config.addresses.Dust)")
  .addOptionalParam("configFile", "Path to deployment config JSON file", DEFAULT_CONFIG_PATH)
  .setAction(async (args: { proxy?: string; configFile: string }, hre) => {
    const config = loadConfig(args.configFile);
    const proxy = args.proxy || config.addresses?.Dust;
    if (!proxy) throw new Error("Missing Dust proxy address (pass --proxy or set config.addresses.Dust)");
    console.log(`Upgrading Dust at ${proxy}...`);
    const F = await hre.ethers.getContractFactory("Dust");
    await showImplChange(hre, proxy, "Dust (pre)");
    const upgraded = await hre.upgrades.upgradeProxy(proxy, F, { redeployImplementation: "onchange" });
    await upgraded.waitForDeployment();
    await showImplChange(hre, proxy, "Dust (post)");
  });

/*//////////////////////////////////////////////////////////////
                      UPGRADE: DUSTLOCK
//////////////////////////////////////////////////////////////*/
task("upgrade:dustlock", "Upgrade DustLock proxy (requires --forwarder and --balancelib)")
  .addOptionalParam("proxy", "DustLock proxy address (defaults to config.addresses.DustLock)")
  .addParam("forwarder", "Trusted forwarder address")
  .addParam("balancelib", "Deployed BalanceLogicLibrary address")
  .addOptionalParam("configFile", "Path to deployment config JSON file", DEFAULT_CONFIG_PATH)
  .setAction(async (args: { proxy?: string; forwarder: string; balancelib: string; configFile: string }, hre) => {
    const config = loadConfig(args.configFile);
    const proxy = args.proxy || config.addresses?.DustLock;
    if (!proxy) throw new Error("Missing DustLock proxy address (pass --proxy or set config.addresses.DustLock)");
    console.log(`Upgrading DustLock at ${proxy}...`);
    const F = await hre.ethers.getContractFactory("DustLock", { libraries: { BalanceLogicLibrary: args.balancelib } });
    await showImplChange(hre, proxy, "DustLock (pre)");
    const upgraded = await hre.upgrades.upgradeProxy(proxy, F, {
      constructorArgs: [args.forwarder],
      unsafeAllow: ["constructor", "external-library-linking"],
      unsafeAllowLinkedLibraries: true,
      redeployImplementation: "onchange",
    });
    await upgraded.waitForDeployment();
    await showImplChange(hre, proxy, "DustLock (post)");
  });

/*//////////////////////////////////////////////////////////////
                   UPGRADE: REVENUE REWARD
//////////////////////////////////////////////////////////////*/
task("upgrade:revenuereward", "Upgrade RevenueReward proxy (requires --forwarder)")
  .addOptionalParam("proxy", "RevenueReward proxy address (defaults to config.addresses.RevenueReward)")
  .addParam("forwarder", "Trusted forwarder address")
  .addOptionalParam("configFile", "Path to deployment config JSON file", DEFAULT_CONFIG_PATH)
  .setAction(async (args: { proxy?: string; forwarder: string; configFile: string }, hre) => {
    const config = loadConfig(args.configFile);
    const proxy = args.proxy || config.addresses?.RevenueReward;
    if (!proxy) throw new Error("Missing RevenueReward proxy address (pass --proxy or set config.addresses.RevenueReward)");
    console.log(`Upgrading RevenueReward at ${proxy}...`);
    const F = await hre.ethers.getContractFactory("RevenueReward");
    await showImplChange(hre, proxy, "RevenueReward (pre)");
    const upgraded = await hre.upgrades.upgradeProxy(proxy, F, {
      constructorArgs: [args.forwarder],
      unsafeAllow: ["constructor"],
      redeployImplementation: "onchange",
    });
    await upgraded.waitForDeployment();
    await showImplChange(hre, proxy, "RevenueReward (post)");
  });

/*//////////////////////////////////////////////////////////////
               UPGRADE: DUST REWARDS CONTROLLER
//////////////////////////////////////////////////////////////*/
task("upgrade:dustrewardscontroller", "Upgrade DustRewardsController proxy (requires --emissionmanager)")
  .addOptionalParam("proxy", "DustRewardsController proxy address (defaults to config.addresses.DustRewardsController)")
  .addParam("emissionmanager", "Emission manager address (immutable in impl)")
  .addOptionalParam("configFile", "Path to deployment config JSON file", DEFAULT_CONFIG_PATH)
  .setAction(async (args: { proxy?: string; emissionmanager: string; configFile: string }, hre) => {
    const config = loadConfig(args.configFile);
    const proxy = args.proxy || config.addresses?.DustRewardsController;
    if (!proxy) throw new Error("Missing DustRewardsController proxy address (pass --proxy or set config.addresses.DustRewardsController)");
    console.log(`Upgrading DustRewardsController at ${proxy}...`);
    const F = await hre.ethers.getContractFactory("DustRewardsController");
    await showImplChange(hre, proxy, "DustRewardsController (pre)");
    const upgraded = await hre.upgrades.upgradeProxy(proxy, F, {
      constructorArgs: [args.emissionmanager],
      unsafeAllow: ["constructor", "state-variable-immutable", "state-variable-assignment", "missing-initializer"],
      redeployImplementation: "onchange",
    });
    await upgraded.waitForDeployment();
    await showImplChange(hre, proxy, "DustRewardsController (post)");
  });

/*//////////////////////////////////////////////////////////////
                  UPGRADE: USER VAULT FACTORY
//////////////////////////////////////////////////////////////*/
task("upgrade:uservaultfactory", "Upgrade UserVaultFactory proxy")
  .addOptionalParam("proxy", "UserVaultFactory proxy address (defaults to config.addresses.UserVaultFactory)")
  .addOptionalParam("configFile", "Path to deployment config JSON file", DEFAULT_CONFIG_PATH)
  .setAction(async (args: { proxy?: string; configFile: string }, hre) => {
    const config = loadConfig(args.configFile);
    const proxy = args.proxy || config.addresses?.UserVaultFactory;
    if (!proxy) throw new Error("Missing UserVaultFactory proxy address (pass --proxy or set config.addresses.UserVaultFactory)");
    console.log(`Upgrading UserVaultFactory at ${proxy}...`);
    const F = await hre.ethers.getContractFactory("UserVaultFactory");
    await showImplChange(hre, proxy, "UserVaultFactory (pre)");
    const upgraded = await hre.upgrades.upgradeProxy(proxy, F, { redeployImplementation: "onchange" });
    await upgraded.waitForDeployment();
    await showImplChange(hre, proxy, "UserVaultFactory (post)");
  });
