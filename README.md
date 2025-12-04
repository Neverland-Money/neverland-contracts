# Neverland Protocol

> **License**: Mixed. Neverland-authored code is under Business Source License 1.1 (changes to MIT on 2028-07-20); some components are AGPL/GPL per SPDX. See [License](#license) section below.

Neverland Protocol is a next-generation decentralized lending platform that combines Aave V3's battle-tested lending infrastructure with an innovative vote-escrow (veNFT) system. Users can lock `DUST` tokens to receive `veDUST` NFTs that provide:

- **Time-weighted governance power** for protocol decisions
- **Revenue sharing** from protocol fees and activities  
- **Transferable positions** via ERC-721 veNFTs with flexible management
- **Self-repaying loans** via RevenueReward contract

## Table of Contents

- [Key Features](#key-features)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Development Workflow](#development-workflow)
- [Deployment](#deployment)
- [Protocol Architecture](#protocol-architecture)
- [Dependencies & Compatibility](#dependencies--compatibility)
- [Smart Contracts](#smart-contracts)
- [Testing Framework](#testing-framework)
- [License](#license)
- [Security](#security)
- [Contributing](#contributing)
- [Contact](#contact)

## Key Features

- **Battle-tested Lending**: Built on Aave V3 with zero modifications to core lending logic
- **Vote-Escrow Governance**: Lock DUST for 28 days to 1 year, receive voting power that decays linearly
- **Revenue Distribution**: Automatic protocol revenue sharing to veNFT holders via RevenueReward contract
- **Flexible Incentives**: Configurable emissions via DustRewardsController with auto-locking to veNFTs
- **Leaderboard & Engagement**: Points-based rewards system with voting power multipliers and NFT partnership boosts
- **High Precision Math**: PRB Math UD60x18 ensures accurate calculations for all financial operations
- **Advanced Operations**: Batch operations, permanent locks, self-repaying loans, and comprehensive veNFT management

## Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation) (1.5.0-stable)
- [Node.js](https://nodejs.org/) (v16 or later)
- [npm](https://www.npmjs.com/) or [yarn](https://yarnpkg.com/)

## Quick Start

### Installation

1. **Clone the repository:**
```bash
git clone https://github.com/Neverland-Money/neverland-contracts.git
cd neverland-contracts
```

2. Install Git submodules:
```bash
git submodule update --init --recursive
```

3. Install Foundry dependencies:
```bash
forge install
```

4. Install Node.js dependencies:
```bash
npm install
# or
yarn install
```

5. Build the contracts with Foundry:
```bash
forge build
```

6. Compile contracts with Hardhat and generate TypeChain types:
```bash
npx hardhat compile
```

7. Run tests:
```bash
forge test
```

## Development Workflow

### Foundry (Primary)
```bash
# Build contracts
forge build

# Run all tests
forge test

# Run tests with verbose output
forge test -vv

# Run specific contract tests
forge test --match-contract DustLock -vv
```

### Hardhat (TypeScript Support)
```bash
# Compile contracts and generate TypeChain types
npx hardhat compile
```

### TypeChain Integration
After running `npx hardhat compile`, TypeScript type definitions will be generated in the `typechain-types/` directory, providing full type safety for contract interactions. 

Default typechain is `ethers-v6`, to choose `ethers-v5` specify `ETHERS_V5=true` env variable.

## Deployment

Deployment scripts and configurations are located in the `docs/` directory. For Aave V3 core deployment, see the [aave-v3-deploy repository](https://github.com/Neverland-Money/aave-v3-deploy).

### Pre-deployment Checklist

- Verify all contracts compile: `forge build`
- Run full test suite: `forge test`
- Review deployment parameters in scripts
- Ensure deployer wallet has sufficient gas

> **Note**: Production deployments should be reviewed by the Neverland Foundation team.

## Protocol Architecture

Neverland Protocol is built on five interconnected layers:

### 1. Lending Market Layer
- **Foundation**: Unmodified Aave V3 core contracts
- **Assets**: Support for multiple ERC-20 tokens as collateral and borrowable assets
- **Security**: Inherits Aave's battle-tested liquidation and risk management
- **Integration**: Seamlessly connects with veNFT incentive system

### 2. Vote-Escrow System
- **DUST Token**: Protocol governance token (ERC-20)
- **DustLock Contract**: Locks DUST into transferable veDUST NFT (ERC-721)
- **Voting Power**: Time-weighted, linearly decaying based on lock duration
- **Flexibility**: 28 days to 1 year locks, permanent locks, early withdrawal with penalty

### 3. Incentive Distribution
- **DustRewardsController**: Modified Aave rewards controller for DUST emissions
- **DustLockTransferStrategy**: Automatically locks claimed rewards into veDUST
- **Multi-Asset Support**: Configure emissions for any lending market asset
- **User Choice**: Claim as liquid DUST (with penalty) or lock into veDUST for full rewards

### 4. Revenue Sharing
- **RevenueReward Contract**: Distributes protocol fees to veDUST holders
- **Multi-Token Support**: Revenue sharing with the option to add multiple tokens
- **Epoch-Based**: Weekly distribution cycles with proportional allocation
- **Self-Repaying Loans**: Optional revenue redirection for automated loan repayment

### 5. Leaderboard System
- **Points-Based Rewards**: Track user activities and protocol engagement through epochs
- **Voting Power Multipliers**: VotingPowerMultiplier provides tiered bonuses (1.0x to 5.0x) based on veDUST holdings
- **NFT Partnership Boosts**: NFTPartnershipRegistry enables partner NFT collections to grant additional multipliers
- **Dynamic Configuration**: LeaderboardConfig allows real-time adjustment of point accrual rates
- **Keeper Automation**: LeaderboardKeeper handles automated state verification and settlement
- **Subgraph Integration**: All events emitted for off-chain tracking and leaderboard calculation

### Technical Features

- **High-Precision Mathematics**: Implements PRB Math UD60x18 for 18-decimal fixed-point arithmetic
- **Optimized Vote-Escrow**: Enhanced precision in voting power calculations and decay mechanics
- **Flexible Incentives**: Configurable reward distribution with multiple token support
- **Comprehensive Testing**: Extensive test suite covering edge cases and precision scenarios


## Dependencies & Compatibility

### External Libraries (MIT Licensed)

| Library | Version | Commit Hash | Purpose |
|---------|---------|-------------|---------|
| [Forge Std](https://github.com/foundry-rs/forge-std) | v1.9.7 | 77041d2 | Foundry testing framework and utilities |
| [OpenZeppelin Contracts](https://github.com/OpenZeppelin/openzeppelin-contracts) | v4.9.5-2 | dc44c9f | Standard contract implementations |
| [OpenZeppelin Upgradeable](https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable) | v4.9.6 | 2d081f2 | Upgradeable contract implementations |
| [PRB Math](https://github.com/PaulRBerg/prb-math) | v4.1.0 | 280fc5f | High-precision 18-decimal arithmetic |

### Forked Repositories (Various Licenses)

| Repository          | Release | Commit Hash | License | Purpose |
|---------------------|---------|-------------|---------|---------|
| [aave-v3-core](https://github.com/aave/aave-v3-core) | v1.19.4-1 | 782f519 | BUSL-1.1→MIT | Core lending protocol contracts |
| [aave-v3-periphery](https://github.com/aave/aave-v3-periphery) | v2.1.0-17 | 9afa826 | BUSL-1.1→MIT | Rewards and helper contracts |
| [velodrome-contracts](https://github.com/velodrome-finance/contracts) | — | 9e5a574 | MIT | Vote-escrow mechanics reference |

> **Note**: Aave V3 contracts are managed and deployed in [this repository](https://github.com/Neverland-Money/aave-v3-deploy).

## Smart Contracts

| Contract                     | Description                                                                                         | Forked From                                       | Changes Scope                                                                                                                                                                                                                                                                            |
|------------------------------|-----------------------------------------------------------------------------------------------------|---------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| **Dust**                     | Protocol ERC20 token                                                                                | —                                                 | —                                                                                                                                                                                                                                                                                        |
| **DustLock**                 | ERC-721 vote-escrow contract. Users lock DUST tokens for governance participation with time-weighted voting power | [velodrome-contracts](https://github.com/velodrome-finance/contracts):<br/>VotingEscrow             | - Extensively restructured, primarily retaining epoch time mathematics <br/> - Implemented [PRB Math](https://github.com/PaulRBerg/prb-math) UD60x18 for refined voting power precision <br/> - Removed voting and delegation mechanisms <br/> - Removed managed lock functionality <br/> - Added permanent lock capability <br/> - Added early withdrawal with penalty calculation <br/> - Set lock duration range: 28 days to 1 year <br/> - Added configurable tokenURI and minimum lock validation |
| **RevenueReward**            | Distributes ERC20 token rewards to veDUST holders                                                   | Inspired by [velodrome-contracts](https://github.com/velodrome-finance/contracts):<br/>Reward                  | - Custom implementation inspired by core reward distribution concepts <br/> - Added comprehensive batch operations for multiple tokenIds and reward tokens <br/> - Added self-repaying loan functionality with automatic redirect <br/> - Implemented multi-token reward support with precision handling <br/> - Added epoch-based distribution with remainder tracking <br/> - Added access controls and operator management                                                                                                                                                                                             |
| **DustRewardsController**    | Modified Aave rewards controller handling DUST emissions                                            | [aave-v3-periphery](https://github.com/aave/aave-v3-periphery):<br/>RewardsController          | - Replaced `ITransferStrategyBase` with `IDustTransferStrategy` interface <br/> - Added `lockTime` and `tokenId` arguments to claiming functions, to pass them to `IDustTransferStrategy.performTransfer()` function<br/> - Removed rewards oracles used to display price data on the UI |
| **DustTransferStrategy**     | Base contract for reward transfer strategies                                                        | [aave-v3-periphery](https://github.com/aave/aave-v3-periphery):<br/>TransferStrategyBase       | - Replaced `ITransferStrategyBase` with `IDustTransferStrategy` interface <br/> - Added `lockTime` and `tokenId` arguments to the `performTransfer()` function                                                                                                                           |
| **DustLockTransferStrategy** | Strategy used by the controller to lock or withdraw DUST rewards                                    | [aave-v3-periphery](https://github.com/aave/aave-v3-periphery):<br/>PullRewardTransferStrategy | - Based on forked contract <br/> - Integrates with [DustLock](https://github.com/velodrome-finance/contracts) for automatic veNFT creation <br/> - Supports early withdrawal with penalty via direct DUST transfer                                                                                                                                                                                               |
| **EpochTimeLibrary**         | Helper library for epoch time calculations                                                          | [velodrome-contracts](https://github.com/velodrome-finance/contracts):<br/>VelodromeTimeLibrary     | - Changed contract name from VelodromeTimeLibrary to EpochTimeLibrary                                                                                                                                                                                                                                                                  |
| **BalanceLogicLibrary**      | Library for veDUST balance accounting                                                               | [velodrome-contracts](https://github.com/velodrome-finance/contracts):<br/>BalanceLogicLibrary      | - Renamed IVotingEscrow interface to IDustLock <br/> - Updated references to match Neverland's veNFT implementation                                                                                                                                                                                                                                                     |
| **SafeCastLibrary**          | Utilities for safe casting between integer types                                                    | [velodrome-contracts](https://github.com/velodrome-finance/contracts):<br/>SafeCastLibrary          | - No modifications, used as-is from upstream                                                                                                                                                                                                                                                                                   |

### Leaderboard System

| Contract                     | Description                                                                                         |
|------------------------------|-----------------------------------------------------------------------------------------------------|
| **EpochManager**             | Manages leaderboard epochs for the points system. Emits events for subgraph tracking of epoch transitions |
| **LeaderboardConfig**        | Dynamic configuration for point accrual rates across different protocol activities. Subgraph listens to rate changes |
| **LeaderboardKeeper**        | Handles automated user state verification and settlement. Keeper bot submits verified on-chain state to trigger subgraph updates |
| **VotingPowerMultiplier**    | Manages veNFT voting power-based point multipliers using a tiered system (higher voting power = higher multiplier, 1.0x to 5.0x) |
| **NFTPartnershipRegistry**   | Registry for partner NFT collections that provide additional point multipliers with configurable decay ratios |

## Testing Framework

Our comprehensive test suite ensures protocol security and mathematical precision across all operations.

### Core Functionality Tests

| Test File | Coverage | Key Scenarios |
|-----------|----------|---------------|
| `DustLock.t.sol` | Vote-escrow mechanics | Lock creation, deposits, withdrawals, transfers, permanent locks |
| `RevenueReward.t.sol` | Revenue distribution | Multi-token rewards, batch claims, self-repaying loans, precision |
| `DustRewardsController.t.sol` | Incentive distribution | Emission configuration, reward claiming, transfer strategies |
| `DustLockTransferStrategy.t.sol` | Reward auto-locking | DUST reward conversion to veNFTs, penalty calculations |
| `leaderboard/*.t.sol` | Leaderboard system | Epoch management, point multipliers, NFT partnerships, keeper operations |

### Flow Tests (`/test/flow/`)

Integration tests validating full protocol workflows:

| Test Suite | Purpose | Validation Points |
|------------|---------|-------------------|
| `DustLockFlow.t.sol` | Complete veNFT lifecycles | Lock creation, deposits, transfers, withdrawals |
| `RevenueRewardFlow.t.sol` | Complete revenue distribution | Multi-epoch rewards, batch operations, precision validation |

### Running Tests

```bash
# Full test suite (recommended for CI)
forge test

# Verbose output with execution traces
forge test -vv

# Extra verbose with stack traces  
forge test -vvv

# Test specific functionality
forge test --match-contract DustLock -vv
forge test --match-path "test/flow/*" -vv
forge test --match-test "testRewardPrecision" -vvv

# Run tests with gas reporting
forge test --gas-report
```

### Test Coverage

The protocol maintains comprehensive test coverage across all critical paths:

- **Vote-Escrow Operations**: Complete coverage of lock mechanics
- **Reward Distribution**: Complete coverage of claim and allocation logic  
- **Mathematical Operations**: Comprehensive precision validation
- **Access Controls**: Full security boundary testing
- **Edge Cases**: Extensive boundary condition coverage

> **Note**: Coverage analysis may cause some time-sensitive and gas-dependent tests to fail due to compilation differences.
> All tests pass with standard `forge test` execution.
> This is expected behavior when using `--ir-minimum` for coverage reporting.

## License

This repository contains code under multiple licenses. See [LICENSE](./LICENSE) for full details.

### Primary License

Unless noted below, Neverland-authored code is licensed under the **Business Source License 1.1** (BUSL-1.1):
- **Licensor**: Neverland Foundation
- **Change Date**: 2028-07-20
- **Change License**: MIT
- **Restrictions**: No commercial use or production deployment outside Neverland Foundation without explicit permission

### Exceptions

Due to dependencies on copyleft-licensed code, certain files use different licenses:

- **GNU AGPL-3.0**: Aave-derived reward distribution stack
  - `src/emissions/DustTransferStrategyBase.sol`
  - `src/emissions/DustRewardsController.sol`
  - `src/emissions/DustLockTransferStrategy.sol`
  - Related interfaces in `src/interfaces/IDustTransferStrategy.sol`, `src/interfaces/IDustRewardsController.sol`, `src/interfaces/IDustLockTransferStrategy.sol`

- **GNU GPL-3.0-or-later**: Uniswap-dependent oracle contracts
  - `src/utils/NeverlandDustHelper.sol`

- **MIT**: Selected interfaces and test utilities
  - `src/interfaces/IUserVaultRegistry.sol`
  - Test harnesses in `test/`

### Vendored Dependencies

Third-party libraries in `lib/` retain their original licenses:
- **OpenZeppelin**: MIT
- **Aave V3**: BUSL-1.1 (now MIT after Change Date)
- **Uniswap V2**: GPL-3.0
- **Uniswap V3**: GPL-2.0-or-later (after Change Date)
- **PRB Math**: MIT
- **forge-std**: MIT/Apache-2.0

**SPDX identifiers in each file are authoritative.** See [LICENSE](./LICENSE) for complete terms.

## Security

### Audits

All security audits are publicly available. View our completed audits in the [`audits`](./audits) folder.

### Bug Bounty

Security researchers: please responsibly disclose any vulnerabilities to security@neverland.money.

### Best Practices

- All core contracts are thoroughly tested with Foundry
- High-precision arithmetic using PRB Math prevents common overflow/underflow issues
- Access controls follow OpenZeppelin standards
- Follows Solidity best practices and CEI (Checks-Effects-Interactions) pattern

## Contributing

Contributions are welcome! Please note the licensing structure before contributing:

1. **Fork the repository** and create your branch from `main`
2. **Make your changes** ensuring all tests pass: `forge test`
3. **Add tests** for any new functionality
4. **Follow code style** consistent with existing contracts
5. **Submit a pull request** with a clear description

By contributing, you agree that your contributions will be licensed under the same license as the file you're modifying (BUSL-1.1, AGPL-3.0, GPL-3.0, or MIT as indicated by SPDX headers).

## Contact

- **Website**: [neverland.money](https://neverland.money)
- **Email**: legal@neverland.money
- **Security**: security@neverland.money

---

**Built with ❤️ by Neverland Foundation**
