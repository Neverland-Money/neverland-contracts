import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
import DustModule from "./DustModule";

const DustLockModule = buildModule("DustLockModule", (m) => {
  const forwarder = m.getParameter(
    "forwarder",
    "0x1111111111111111111111111111111111111111"
  );
  const baseURI = m.getParameter(
    "baseURI",
    "https://testnet-nft.neverland.money/"
  );

  const { dust, dustProxyAdmin } = m.useModule(DustModule);

  const myLib = m.library("BalanceLogicLibrary");

  // Deploy implementation with linked library
  const dustLockImpl = m.contract("DustLock", [forwarder], {
    id: "DustLockImpl",
    libraries: { BalanceLogicLibrary: myLib },
  });

  // Proxy using shared ProxyAdmin
  const dustLockProxy = m.contract(
    "TransparentUpgradeableProxy",
    [dustLockImpl, dustProxyAdmin, "0x"],
    { id: "DustLockProxy" }
  );

  // Access the proxy as DustLock and initialize
  const dustLock = m.contractAt("DustLock", dustLockProxy);
  m.call(dustLock, "initialize", [forwarder, dust, baseURI]);

  return { dustLock, dustLockImpl };
});

export default DustLockModule;
