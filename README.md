# LendBook

This repository contains the core Solidity contract of a new lending protocol in which lenders supply liquidity in limit orders.

## Overview

Other users can borrow the assets by posting collateral in limit orders. All orders are displayed in a limit order book and can be taken by traders. The main rule governing the protocol ensures that any position borrowing from a limit order must be closed when the limit order is executed. The alignment of the two events significantly streamlines the settlement process for both parties.

### Benefits

The benefits of appending a lending protocol to an order book are multiple:

- stop loss orders with guaranteed stop price
- zero liquidation costs
- high leverage
- leverage programmability
- no risk of bad debt
- minimized governance
- automatic market making

Please read more about LendBook in the 5p-[light paper](llob_lp.pdf) or the full [white paper](llob_wp.pdf).
