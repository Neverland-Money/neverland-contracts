import { task } from "hardhat/config";
import type { ContractFactory } from "ethers";

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

