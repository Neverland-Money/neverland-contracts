import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const DustModule = buildModule("DustModule", (m) => {
  const proxyAdminOwner = m.getAccount(0);

  const dustProxyAdmin = m.contract("ProxyAdmin", []);

  const dustImpl = m.contract("Dust", [], { id: "DustImpl" });

  const proxy = m.contract("TransparentUpgradeableProxy", [
    dustImpl,
    dustProxyAdmin,
    "0x",
  ]);

  const dust = m.contractAt("Dust", proxy);

  m.call(dust, "initialize", [proxyAdminOwner])

  return { dustProxyAdmin, dust, dustImpl };
});

export default DustModule;