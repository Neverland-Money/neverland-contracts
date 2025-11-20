import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
import DustLockModule from "./DustLockModule";
import DustModule from "./DustModule";

const UserVaultModule = buildModule("UserVaultModule", (m) => {
  const poolAddressesProviderRegistry = m.getParameter(
    "poolAddressesProviderRegistry"
  );
  const executor = m.getParameter("executor");
  const rewardDIstributor = m.getParameter("rewardDistributor");

  const userVaultRegistry = m.contract("UserVaultRegistry", []);

  m.call(userVaultRegistry, "setExecutor", [executor]);

  const userVaultImpl = m.contract("UserVault", []);

  const userVaultBeacon = m.contract("UpgradeableBeacon", [userVaultImpl]);

  const userVaultFactory = m.contract("UserVaultFactory", []);

  const { dustLock } = m.useModule(DustLockModule);
  const { dustProxyAdmin } = m.useModule(DustModule);

  const forwarder = m.staticCall(dustLock, "forwarder", []);

  // Deploy RevenueReward behind a TransparentUpgradeableProxy
  const revenueRewardImpl = m.contract("RevenueReward", [forwarder], {
    id: "RevenueRewardImpl",
  });
  const revenueRewardProxy = m.contract(
    "TransparentUpgradeableProxy",
    [revenueRewardImpl, dustProxyAdmin, "0x"],
    { id: "RevenueRewardProxy" }
  );

  const revenueReward = m.contractAt("RevenueReward", revenueRewardProxy);
  m.call(revenueReward, "initialize", [
    forwarder,
    dustLock,
    rewardDIstributor,
    userVaultFactory,
  ]);

  m.call(userVaultFactory, "initialize", [
    userVaultBeacon,
    userVaultRegistry,
    poolAddressesProviderRegistry,
    revenueReward,
  ]);

  return {
    userVaultImpl,
    userVaultRegistry,
    userVaultBeacon,
    userVaultFactory,
    revenueReward,
    revenueRewardImpl,
  };
});

export default UserVaultModule;
