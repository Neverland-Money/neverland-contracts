# Neverland

Smart contracts for Neverland, a lending protocol built on Aave V3 and Velodrome.

## Setup

This repository uses Foundry for testing.

Foundry Setup

```
forge install
forge build
forge test
```

## Deployment

TBD

## Protocol Overview

We can divide Neverland contracts based on their functionalities:
- Lending Market: Aave V3 (no contract changes).
- veDUST Token: Dust and DustLock contracts.
- DUST emissions: DustRewardsController and DustLockTransferStrategy contracts.
- Revenue Distribution: RevenueReward contract.

#### Aave V3 Interaction Points
The only interaction point between Aave V3 contracts and contracts in this repository is `DustRewardsController`, which should be set as IncentivesController for ATokens (ERC20 supply/borrow receipt tokens in Aave). <br/>
ATokens are calling `handleAction()` on `incentivesController` on each transfer/mint/burn, so incentivesController can keep track of rewards for users holding these tokens. 

### Forked Codebase

| Repository          | Release | Commit                                   | Repository Link                                |
|---------------------|---------|------------------------------------------|------------------------------------------------|
| aave-v3-deploy      | 1.56.2  | 27ccc6d24ef767a2b71946784a843526edbc9618 | https://github.com/aave/aave-v3-deploy         |
| aave-v3-core        | 1.19.4  | b74526a7bc67a3a117a1963fc871b3eb8cea8435 | https://github.com/aave/aave-v3-core           |
| aave-v3-periphery   | 2.5.2   | 803c3e7d6d1c6da8d91411f4d085494f7189ea0b | https://github.com/aave/aave-v3-periphery      |
| velodrome-contracts | —       | 9e5a5748c3e2bcef7016cc4194ce9758f880153f | https://github.com/velodrome-finance/contracts |

Aave V3 contracts are managed and deployed in [this repository](https://github.com/Neverland-Money/aave-v3-deploy).

### Smart Contracts

| Contract                     | Description                                                                                         | Forked From                                       | Changes Scope                                                                                                                                                                                                                                                                            |
|------------------------------|-----------------------------------------------------------------------------------------------------|---------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| **Dust**                     | Protocol ERC20 token                                                                                | —                                                 | —                                                                                                                                                                                                                                                                                        |
| **DustLock**                 | ERC-721 veDUST. Users lock DUST for up to one year while the voting power decays linearly over time | velodrome-contracts:<br/>VotingEscrow             | - Removed all voting logic <br/> - Removed all Managed Lock logic <br/> - Added settable tokenURI instead of using veArtProxy to compute it <br/> - Added `earlyWithdraw()` function <br/> - Changed min/max lock durations to 5 weeks/1 year                                            |
| **RevenueReward**            | Distributes ERC20 token rewards to veDUST holders                                                   | velodrome-contracts:<br/> Reward                  | - Based on forked contract, reusing `earned()`, `getReward()` and `notifyReward()` functions                                                                                                                                                                                             |
| **DustRewardsController**    | Modified Aave rewards controller handling DUST emissions                                            | aave-v3-periphery:<br/>RewardsController          | - Replaced `ITransferStrategyBase` with `IDustTransferStrategy` interface <br/> - Added `lockTime` and `tokenId` arguments to claiming functions, to pass them to `IDustTransferStrategy.performTransfer()` function<br/> - Removed rewards oracles used to display price data on the UI |
| **DustTransferStrategy**     | Base contract for reward transfer strategies                                                        | aave-v3-periphery:<br/>TransferStrategyBase       | - Replaced `ITransferStrategyBase` with `IDustTransferStrategy` interface <br/> - Added `lockTime` and `tokenId` arguments to the `performTransfer()` function                                                                                                                           |
| **DustLockTransferStrategy** | Strategy used by the controller to lock or withdraw DUST rewards                                    | aave-v3-periphery:<br/>PullRewardTransferStrategy | - Based on forked contract                                                                                                                                                                                                                                                               |
| **EpochTimeLibrary**         | Helper library for epoch time calculations                                                          | velodrome-contracts:<br/>VelodromeTimeLibrary     | - Changed contract name                                                                                                                                                                                                                                                                  |
| **BalanceLogicLibrary**      | Library for veDUST balance accounting                                                               | velodrome-contracts:<br/>BalanceLogicLibrary      | - Renamed IVotingEscrow to IDustLock                                                                                                                                                                                                                                                     |
| **SafeCastLibrary**          | Utilities for safe casting between integer types                                                    | velodrome-contracts:<br/>SafeCastLibrary          | - None                                                                                                                                                                                                                                                                                   |

### Tests

- `/test/DustLock.t.sol` tests DustLock (changed functionalities).
- `/test/DustLockTransferStrategy.t.sol` tests DustLockTransferStrategy.
- `/test/RevenueReward.t.sol` tests RevenueReward.

Tests should be well named and easy to understand.
We didn't write tests for functionalities we didn't change in `DustLock`.
We didn't test `DustRewardsController` as changes only pass additional arguments to the DustLockTransferStrategy, which is teseted.
