# Borrowable Limit Order Book

An orderbook which lets users borrow its deposited assets.

## Overview

A Borrowed limit order book (BLOB) is a special order book in which ($i$) the assets backing the limit orders can be borrowed and ($ii$) the borrowed assets of the bid side are collateralized by the assets in the ask side, and reciprocally.

### Benefits

The benefits of appending a lending protocol to an order book are multiple:

- stop loss orders with guaranteed stop price
- zero liquidation costs
- high leverage
- minimized loss ratio
- no risk of bad debt and minimized governance

#### Disclaimer

This is experimental software and is provided on an "as is" and "as available" basis. We do not give any warranties and will not be liable for any loss incurred through any use of this codebase.

## Getting Started

### Requirements

- [git](https://git-scm.com/book/en/v2/Getting-Started-Installing-Git)
- [foundry](https://getfoundry.sh/)

### Quickstart

```
git clone https://github.com/pre-vert/Borrowed-limit-order-book
forge build
```

## Usage

### Deploy:

```
forge script script/DeployOrderBook.s.sol
```

### Testing

```
forge test
```

or

```
// Only run test functions matching the specified regex pattern.

"forge test -m testFunctionName" is deprecated. Please use

forge test --match-test testFunctionName
```

or

```
forge test --fork-url $SEPOLIA_RPC_URL
```

### Test Coverage

```
forge coverage
```

### Scripts

After deploying to a testnet or local net, you can run the scripts.

Using cast deployed locally example:

```
cast send <FUNDME_CONTRACT_ADDRESS> "fund()" --value 0.1ether --private-key <PRIVATE_KEY>
```

or

```
forge script script/Interactions.s.sol --rpc-url sepolia  --private-key $PRIVATE_KEY  --broadcast
```

#### Withdraw

```
cast send <FUNDME_CONTRACT_ADDRESS> "withdraw()"  --private-key <PRIVATE_KEY>
```
