# Neverland Protocol

A decentralized lending protocol built on Aave V3 with an advanced vote-escrow system for governance and incentive alignment.

## Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)

## Installation

1. Clone the repository:
```bash
git clone https://github.com/Neverland-Money/neverland-contracts.git
cd neverland-contracts
```

2. Install dependencies:
```bash
forge install
```

3. Build the contracts:
```bash
forge build
```

4. Run tests:
```bash
forge test
```

## Deployment

TBD

## Architecture

Neverland Protocol consists of four main components:

- **Lending Market**: Built on Aave V3 with no modifications to core lending functionality
- **Vote-Escrow System**: DUST token and DustLock contracts implementing time-weighted governance
- **Incentive Distribution**: DustRewardsController and DustLockTransferStrategy for emissions management
- **Revenue Sharing**: RevenueReward contract for distributing protocol revenues to governance participants

### Technical Features

- **High-Precision Mathematics**: Implements PRB Math UD60x18 for 18-decimal fixed-point arithmetic
- **Optimized Vote-Escrow**: Enhanced precision in voting power calculations and decay mechanics
- **Flexible Incentives**: Configurable reward distribution with multiple token support
- **Comprehensive Testing**: Extensive test suite covering edge cases and precision scenarios

## Dependencies

### Forked Repositories

| Repository          | Release | Commit                                   | Repository Link                                |
|---------------------|---------|------------------------------------------|------------------------------------------------|
| aave-v3-deploy      | 1.56.2  | 27ccc6d24ef767a2b71946784a843526edbc9618 | https://github.com/aave/aave-v3-deploy         |
| aave-v3-core        | 1.19.4  | b74526a7bc67a3a117a1963fc871b3eb8cea8435 | https://github.com/aave/aave-v3-core           |
| aave-v3-periphery   | 2.5.2   | 803c3e7d6d1c6da8d91411f4d085494f7189ea0b | https://github.com/aave/aave-v3-periphery      |
| velodrome-contracts | —       | 9e5a5748c3e2bcef7016cc4194ce9758f880153f | https://github.com/velodrome-finance/contracts |

Aave V3 contracts are managed and deployed in [this repository](https://github.com/Neverland-Money/aave-v3-deploy).

## Smart Contracts

| Contract                     | Description                                                                                         | Forked From                                       | Changes Scope                                                                                                                                                                                                                                                                            |
|------------------------------|-----------------------------------------------------------------------------------------------------|---------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| **Dust**                     | Protocol ERC20 token                                                                                | —                                                 | —                                                                                                                                                                                                                                                                                        |
| **DustLock**                 | ERC-721 vote-escrow contract. Users lock DUST tokens for governance participation with time-weighted voting power | velodrome-contracts:<br/>VotingEscrow             | - Implemented PRB Math UD60x18 for enhanced precision <br/> - Removed voting and delegation logic <br/> - Removed managed lock functionality <br/> - Added configurable tokenURI <br/> - Added early withdrawal with penalty <br/> - Set lock duration range: 28 days to 1 year <br/> - Added minimum lock amount validation |
| **RevenueReward**            | Distributes ERC20 token rewards to veDUST holders                                                   | velodrome-contracts:<br/> Reward                  | - Based on forked contract, reusing `earned()`, `getReward()` and `notifyReward()` functions                                                                                                                                                                                             |
| **DustRewardsController**    | Modified Aave rewards controller handling DUST emissions                                            | aave-v3-periphery:<br/>RewardsController          | - Replaced `ITransferStrategyBase` with `IDustTransferStrategy` interface <br/> - Added `lockTime` and `tokenId` arguments to claiming functions, to pass them to `IDustTransferStrategy.performTransfer()` function<br/> - Removed rewards oracles used to display price data on the UI |
| **DustTransferStrategy**     | Base contract for reward transfer strategies                                                        | aave-v3-periphery:<br/>TransferStrategyBase       | - Replaced `ITransferStrategyBase` with `IDustTransferStrategy` interface <br/> - Added `lockTime` and `tokenId` arguments to the `performTransfer()` function                                                                                                                           |
| **DustLockTransferStrategy** | Strategy used by the controller to lock or withdraw DUST rewards                                    | aave-v3-periphery:<br/>PullRewardTransferStrategy | - Based on forked contract                                                                                                                                                                                                                                                               |
| **EpochTimeLibrary**         | Helper library for epoch time calculations                                                          | velodrome-contracts:<br/>VelodromeTimeLibrary     | - Changed contract name                                                                                                                                                                                                                                                                  |
| **BalanceLogicLibrary**      | Library for veDUST balance accounting                                                               | velodrome-contracts:<br/>BalanceLogicLibrary      | - Renamed IVotingEscrow to IDustLock                                                                                                                                                                                                                                                     |
| **SafeCastLibrary**          | Utilities for safe casting between integer types                                                    | velodrome-contracts:<br/>SafeCastLibrary          | - None                                                                                                                                                                                                                                                                                   |

## Testing

The test suite is organized into core functionality tests and comprehensive precision validation:

### Core Tests
- `DustLock.t.sol` - Core vote-escrow functionality
- `DustLockTransferStrategy.t.sol` - Reward transfer strategies  
- `RevenueReward.t.sol` - Revenue distribution mechanics
- `DustRewardsController.t.sol` - Incentive controller integration

### Precision Tests (`/test/precision/`)
- `CheckpointTests.t.sol` - Voting power checkpoint accuracy
- `DecayTests.t.sol` - Time-based voting power decay
- `PrecisionTests.t.sol` - Mathematical precision scenarios
- `RewardTests.t.sol` - Multi-epoch reward distribution
- `ValidationTests.t.sol` - Edge case validation
- `ExtendedBaseTest.sol` - Shared testing utilities

### Running Tests

```bash
# Run all tests
forge test

# Run with verbose output
forge test -vv

# Run specific test suite
forge test --match-path "test/precision/*" -vv

# Run specific test file
forge test test/DustLock.t.sol -vv
```

## Acknowledgments

- [Aave](https://aave.com/) for the lending protocol foundation
- [Velodrome Finance](https://velodrome.finance/) for vote-escrow mechanics inspiration
- [PRB Math](https://github.com/PaulRBerg/prb-math) for high-precision mathematical operations
