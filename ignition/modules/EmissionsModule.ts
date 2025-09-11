import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
import DustLockModule from "./DustLockModule";
import DustModule from "./DustModule";

const EmissionsModule = buildModule("EmissionsModule", (m) => {
  const rewardsAdmin = m.getParameter("rewardsAdmin");
  const dustVault = m.getParameter("dustVault");
  const emissionsManager = m.getParameter("emissionsManager");

  const {dust} = m.useModule(DustModule);
  const {dustLock} = m.useModule(DustLockModule);

  const dustRewardsController = m.contract("DustRewardsController", [emissionsManager]);
  
  const dustTransferStrategy = m.contract("DustLockTransferStrategy", [dustRewardsController, rewardsAdmin, dustVault, dustLock]);

  m.call(dustRewardsController, "setTransferStrategy", [dust, dustTransferStrategy]);

  return { dustRewardsController, dustTransferStrategy };
});

export default EmissionsModule;