# Neverland

Smart contracts for Neverland, a lending protocol built on AAVE and Aerodrome.

## Setup

This repository uses Foundry for testing

Foundry Setup

```
forge install
forge build
forge test
```

## Deployment

// TODO

## Protocol Overview

| contract      | Description                                                                                              |
|---------------|----------------------------------------------------------------------------------------------------------|
| Dust          | Protocol ERC20 token                                                                                     |
| DustLock      | ERC-721 veDUST, stakes DUST for a max time of 1y for with decaying its value linearly decaying over time |
| RevenueReward | Stores ERC20 token rewards and provides them to veDUST owners                                            |