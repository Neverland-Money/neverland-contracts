import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
import DustModule from "./DustModule";

const DustLockModule = buildModule("DustLockModule", (m) => {
  const forwarder = m.getParameter("forwarder", "0x1111111111111111111111111111111111111111");
  const baseURI = m.getParameter("baseURI", "https://testnet-nft.neverland.money/");

  const {dust} = m.useModule(DustModule);

  const myLib = m.library("BalanceLogicLibrary");

  const dustLock = m.contract("DustLock", [forwarder, dust, baseURI], { libraries: { BalanceLogicLibrary: myLib } });

  return { dustLock };
});

export default DustLockModule;