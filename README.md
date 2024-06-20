# LendBook

This repository contains the core Solidity contract of a new lending protocol in which lenders supply liquidity in limit orders. Other users can borrow the assets by posting collateral in limit orders. All orders are displayed in a limit order book and can be taken by traders. All positions are liquidated when the limit orders from which the assets are borrowed are filled.

### Benefits

The benefits of associating a limit price to the supplied liquidity are multiple:

- stop loss orders with guaranteed stop price
- low liquidation costs
- high loan-to-value and leverage
- leverage programmability
- no risk of bad debt
- minimized governance
- automatic market making

Please read more about LendBook in the 5p-[light paper](pdf/llob_lp.pdf) or the full [white paper](pdf/llob_wp.pdf).
