import "@nomicfoundation/hardhat-toolbox";
import "@nomicfoundation/hardhat-chai-matchers";
import "@nomicfoundation/hardhat-foundry";
import "@nomicfoundation/hardhat-ignition-ethers";
import "@openzeppelin/hardhat-upgrades";
import { loadTasks } from "./script/hardhat/helpers";
require("dotenv").config();

const SKIP_LOAD = process.env.SKIP_LOAD === "true";
const ETHERS_V5 = process.env.ETHERS_V5 === "true";

// Prevent to load tasks before compilation and typechain
if (!SKIP_LOAD) {
  loadTasks(["hardhat"]);
}

const ETHERSCAN_KEY = process.env.ETHERSCAN_KEY || "";
const PRIVATE_KEY = process.env.PRIVATE_KEY || "";
const MONAD_MAINNET_RPC = process.env.MONAD_MAINNET_RPC || "";
// Anvil fork chain ID: 143 for mainnet, 10143 for testnet
const ANVIL_CHAIN_ID = process.env.ANVIL_CHAIN_ID
  ? parseInt(process.env.ANVIL_CHAIN_ID)
  : 143;

export default {
  solidity: {
    version: "0.8.30",
    settings: {
      optimizer: { enabled: true, runs: 200 },
      metadata: {
        bytecodeHash: "none",
        useLiteralContent: true,
      },
    },
  },
  networks: {
    hardhat: {
      forking: {
        enabled: true,
        // blockNumber: 36063418,
        url: `https://monad-testnet.g.alchemy.com/v2/u6NNPB_CUTwPMMW-zQsiJ8d3QHATGJLA`,
      },
    },
    // Local Anvil Fork
    "anvil-fork": {
      url: "http://127.0.0.1:8545",
      chainId: ANVIL_CHAIN_ID,
      accounts: [PRIVATE_KEY],
      timeout: 60000,
    },
    // Monad Testnet
    "monad-testnet": {
      url: `https://testnet-rpc.monad.xyz`,
      chainId: 10143,
      accounts: [PRIVATE_KEY],
    },
    // Monad Mainnet
    "monad-mainnet": {
      url: MONAD_MAINNET_RPC,
      chainId: 143,
      accounts: [PRIVATE_KEY],
      gasPrice: "auto",
    },
  },
  typechain: {
    outDir: ETHERS_V5 ? "typechain-v5" : "typechain-v6",
    target: ETHERS_V5 ? "ethers-v5" : "ethers-v6",
  },
  sourcify: {
    enabled: true,
    apiUrl: "https://sourcify-api-monad.blockvision.org",
    browserUrl: "https://mainnet-beta.monvision.io/",
  },
  etherscan: {
    enabled: true,
    apiKey: ETHERSCAN_KEY,
    customChains: [
      {
        network: "monad-testnet",
        chainId: 10143,
        urls: {
          apiURL: "https://api.etherscan.io/v2/api?chainid=10143",
          browserURL: "https://testnet.monadscan.com/",
        },
      },
      {
        network: "monad-mainnet",
        chainId: 143,
        urls: {
          apiURL: "https://api.etherscan.io/v2/api?chainid=143",
          browserURL: "https://monadscan.com/",
        },
      },
    ],
  },
};
