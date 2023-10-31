# LendBook

This repository contains the core Solidity contract for an order book which lets users borrow its deposited assets.

## Overview

A Lending limit order book is a special order book in which ($i$) the assets backing the limit orders can be borrowed and ($ii$) the borrowed assets of the bid side are collateralized by the assets in the ask side, and reciprocally.

### Benefits

The benefits of appending a lending protocol to an order book are multiple:

- stop loss orders with guaranteed stop price
- zero liquidation costs
- high leverage
- leverage programmability
- no risk of bad debt
- minimized governance

Please read more about LendBook in the [white paper](wp_llob.pdf).
