# Neverland

Smart contracts for Neverland, a lending protocol built on AAVE and Aerodrome.

## Setup

This repository uses Foundry for testing.

Foundry Setup

```
forge install
forge build
forge test
```

## Deployment

// TODO

## Protocol Overview

| Contract | Description |
|----------|-------------|
| **Dust** | Protocol ERC20 token |
| **DustLock** | ERC-721 veDUST. Users lock DUST for up to one year while the voting power decays linearly over time |
| **RevenueReward** | Distributes ERC20 token rewards to veDUST holders |
| **DustRewardsController** | Modified Aave rewards controller handling DUST emissions |
| **DustLockTransferStrategy** | Strategy used by the controller to lock or withdraw DUST rewards |
| **DustTransferStrategyBase** | Base contract for reward transfer strategies |
| **EpochTimeLibrary** | Helper library for epoch time calculations |
| **BalanceLogicLibrary** | Library for veDUST balance accounting |
| **SafeCastLibrary** | Utilities for safe casting between integer types |