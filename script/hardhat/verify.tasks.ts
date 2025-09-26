/*//////////////////////////////////////////////////////////////
                            IMPORTS
//////////////////////////////////////////////////////////////*/
import { task } from "hardhat/config";
import type { HardhatRuntimeEnvironment } from "hardhat/types";
import fs from "fs";
import path from "path";

/*//////////////////////////////////////////////////////////////
                           HELPERS
//////////////////////////////////////////////////////////////*/
const DEPLOYMENTS_ROOT = path.resolve(process.cwd(), "deployments");

function readJson(p: string): any {
  return JSON.parse(fs.readFileSync(p, "utf8"));
}

async function verify(
  hre: HardhatRuntimeEnvironment,
  address: string,
  args: any[] = []
): Promise<void> {
  await hre.run("verify:verify", { address, constructorArguments: args });
}

// Resolve Hardhat metadata JSON (standard solc metadata) for a contract by name
async function getHardhatMetadata(
  hre: HardhatRuntimeEnvironment,
  contractName: string
): Promise<any | null> {
  try {
    const artifact = await hre.artifacts.readArtifact(contractName);
    const fqName = `${artifact.sourceName}:${artifact.contractName}`;
    const buildInfo = await hre.artifacts.getBuildInfo(fqName);
    if (buildInfo) {
      const metaStr = (buildInfo as any).output?.contracts?.[
        artifact.sourceName
      ]?.[artifact.contractName]?.metadata;
      if (metaStr) return JSON.parse(metaStr);
    }
  } catch (_) {
    // Fallback exhaustive scan
    try {
      const biDir = path.resolve(process.cwd(), "artifacts", "build-info");
      const files = fs.existsSync(biDir)
        ? fs.readdirSync(biDir).filter((f) => f.endsWith(".json"))
        : [];
      for (const f of files) {
        const bi = JSON.parse(fs.readFileSync(path.join(biDir, f), "utf8"));
        const contracts = bi.output?.contracts || {};
        for (const [src, table] of Object.entries(contracts) as Array<
          [string, any]
        >) {
          if (table && table[contractName] && table[contractName].metadata) {
            return JSON.parse(table[contractName].metadata);
          }
        }
      }
    } catch (_) {}
  }
  return null;
}

/*//////////////////////////////////////////////////////////////
                           TASK: VERIFY ALL
//////////////////////////////////////////////////////////////*/
task(
  "verify:all",
  "Verify all deployed contracts using deployments/<network>/addresses.json"
)
  .addOptionalParam(
    "networkName",
    "Deployments network folder (defaults to current network)"
  )
  .addOptionalParam("deploymentsDir", "Deployments root dir", DEPLOYMENTS_ROOT)
  .setAction(
    async (
      args: { networkName?: string; deploymentsDir: string },
      hre: HardhatRuntimeEnvironment
    ) => {
      const networkName = args.networkName || hre.network.name;
      const folder = path.join(args.deploymentsDir, networkName);
      const addressesFile = path.join(folder, "addresses.json");
      if (!fs.existsSync(addressesFile))
        throw new Error(`addresses.json not found: ${addressesFile}`);
      const cfgFile = path.resolve(
        process.cwd(),
        "script",
        "hardhat",
        "config",
        "deploy.json"
      );
      if (!fs.existsSync(cfgFile))
        throw new Error(`deploy.json not found: ${cfgFile}`);

      const summary = readJson(addressesFile);
      const deployCfg = readJson(cfgFile);
      const A = summary.addresses || {};
      const I = summary.implementations || {};

      const results: Array<{
        contract: string;
        address: string;
        ok: boolean;
        note?: string;
      }> = [];
      const wrap = async (
        label: string,
        addr: string,
        fn: () => Promise<void>
      ) => {
        try {
          await fn();
          results.push({ contract: label, address: addr, ok: true });
        } catch (e: any) {
          results.push({
            contract: label,
            address: addr,
            ok: false,
            note: e?.message || String(e),
          });
        }
      };

      // Implementations (transparent proxies)
      if (I.Dust) await wrap("Dust (impl)", I.Dust, () => verify(hre, I.Dust));
      if (I.DustLock)
        await wrap("DustLock (impl)", I.DustLock, () =>
          verify(hre, I.DustLock, [deployCfg.dustLock?.forwarder])
        );
      if (I.RevenueReward)
        await wrap("RevenueReward (impl)", I.RevenueReward, () =>
          verify(hre, I.RevenueReward, [deployCfg.revenueReward?.forwarder])
        );
      if (I.DustRewardsController) {
        // Read emission manager from chain (immutable) to avoid config drift
        let emission = deployCfg.dustRewardsController?.emissionManager;
        try {
          const ctrlAddr = A.DustRewardsController as string;
          if (ctrlAddr) {
            const ctrl = await hre.ethers.getContractAt(
              "DustRewardsController",
              ctrlAddr
            );
            // The base contract exposes EMISSION_MANAGER() as a public getter
            emission = await ctrl.EMISSION_MANAGER();
          }
        } catch (_) {}
        await wrap(
          "DustRewardsController (impl)",
          I.DustRewardsController,
          () => verify(hre, I.DustRewardsController, [emission])
        );
      }
      if (I.UserVaultFactory)
        await wrap("UserVaultFactory (impl)", I.UserVaultFactory, () =>
          verify(hre, I.UserVaultFactory)
        );

      // Beacon + implementation
      if (A.UserVaultBeacon && A.UserVaultImplementation) {
        await wrap("UpgradeableBeacon", A.UserVaultBeacon, () =>
          verify(hre, A.UserVaultBeacon, [A.UserVaultImplementation])
        );
        await wrap("UserVault (impl)", A.UserVaultImplementation, () =>
          verify(hre, A.UserVaultImplementation)
        );
      }

      // Direct contracts
      if (A.UserVaultRegistry)
        await wrap("UserVaultRegistry", A.UserVaultRegistry, () =>
          verify(hre, A.UserVaultRegistry)
        );
      if (A.DustLockTransferStrategy) {
        const inc =
          deployCfg.transferStrategy?.incentivesControllerOverride ||
          A.DustRewardsController;
        const admin = deployCfg.transferStrategy?.rewardsAdmin;
        const vault = deployCfg.transferStrategy?.dustVault;
        const lock = A.DustLock;
        await wrap("DustLockTransferStrategy", A.DustLockTransferStrategy, () =>
          verify(hre, A.DustLockTransferStrategy, [inc, admin, vault, lock])
        );
      }
      if (A.NeverlandDustHelper) {
        // Read actual owner from chain (constructor arg should be current owner)
        const helper = await hre.ethers.getContractAt(
          "NeverlandDustHelper",
          A.NeverlandDustHelper
        );
        const owner = await helper.owner();
        await wrap("NeverlandDustHelper", A.NeverlandDustHelper, () =>
          verify(hre, A.NeverlandDustHelper, [A.Dust, owner])
        );
      }
      if (A.NeverlandUiProvider) {
        await wrap("NeverlandUiProvider", A.NeverlandUiProvider, () =>
          verify(hre, A.NeverlandUiProvider, [
            A.DustLock,
            A.RevenueReward,
            A.DustRewardsController,
            A.NeverlandDustHelper,
            deployCfg.uiProvider?.aaveLendingPoolAddressProvider,
          ])
        );
      }

      // ProxyAdmin (no args)
      if (summary.proxyAdmin) {
        await wrap("ProxyAdmin", summary.proxyAdmin, () =>
          verify(hre, summary.proxyAdmin)
        );
      }

      console.log("\nVerification results:");
      console.table(
        results.map((r) => ({
          contract: r.contract,
          address: r.address,
          ok: r.ok,
          note: r.note || "",
        }))
      );
    }
  );

/*//////////////////////////////////////////////////////////////
                    TASK: EXPORT METADATA ONLY
//////////////////////////////////////////////////////////////*/
task(
  "export:metadata",
  "Export per-contract metadata JSONs to deployments/<network>/"
)
  .addOptionalParam(
    "networkName",
    "Deployments network folder (defaults to current network)"
  )
  .addOptionalParam("deploymentsDir", "Deployments root dir", DEPLOYMENTS_ROOT)
  .setAction(
    async (
      args: { networkName?: string; deploymentsDir: string },
      hre: HardhatRuntimeEnvironment
    ) => {
      const networkName = args.networkName || hre.network.name;
      const folder = path.join(args.deploymentsDir, networkName);
      const addressesFile = path.join(folder, "addresses.json");
      if (!fs.existsSync(addressesFile))
        throw new Error(`addresses.json not found: ${addressesFile}`);
      const summary = readJson(addressesFile);
      const A = summary.addresses || {};
      const I = summary.implementations || {};

      const ensureDir = (p: string) => fs.mkdirSync(p, { recursive: true });
      ensureDir(folder);

      const rows: Array<{ contract: string; file: string; hasMeta: boolean }> =
        [];
      const write = (name: string, content: any) => {
        const outFile = path.join(folder, `${name}.json`);
        fs.writeFileSync(outFile, JSON.stringify(content, null, 2));
        rows.push({
          contract: name,
          file: `deployments/${networkName}/${name}.json`,
          hasMeta: !!content.metadata,
        });
      };

      // Write entries for every address in addresses.json
      for (const [name, addr] of Object.entries(A) as Array<[string, string]>) {
        const meta = await getHardhatMetadata(hre, name);
        const isProxied = I[name] !== undefined;
        const content: any = {
          networkName,
          chainId: summary.chainId,
          contract: name,
        };
        if (isProxied) {
          content.proxy = addr;
          content.implementation = I[name];
          if (summary.proxyAdmin) content.proxyAdmin = summary.proxyAdmin;
        } else {
          content.address = addr;
        }
        if (meta) content.metadata = meta;
        write(name, content);
      }

      // Also output ProxyAdmin.json if present, with metadata
      if (summary.proxyAdmin) {
        let adminMeta: any = null;
        try {
          const biDir = path.resolve(process.cwd(), "artifacts", "build-info");
          const files = fs.existsSync(biDir)
            ? fs.readdirSync(biDir).filter((f) => f.endsWith(".json"))
            : [];
          for (const f of files) {
            const bi = JSON.parse(fs.readFileSync(path.join(biDir, f), "utf8"));
            const entry =
              bi.output?.contracts?.[
                "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol"
              ]?.ProxyAdmin;
            if (entry?.metadata) {
              adminMeta = JSON.parse(entry.metadata);
              break;
            }
          }
        } catch (_) {}
        const content: any = {
          networkName,
          chainId: summary.chainId,
          contract: "ProxyAdmin",
          proxyAdmin: summary.proxyAdmin,
        };
        if (adminMeta) content.metadata = adminMeta;
        write("ProxyAdmin", content);
      }

      console.table(
        rows.map((r) => ({
          contract: r.contract,
          file: r.file,
          hasMetadata: r.hasMeta,
        }))
      );
    }
  );
