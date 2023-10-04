# :book: Borrowable Limit Order Book - SPEC

## :family: Actors

- Makers: only place orders, receive interest
- Makers/borrowers: place orders and borrow from other-side orders (borrowers for short), pay interest
- Takers: take orders on the book and exchange at limit price
- Keepers: liquidate borderline positions due to growing interest rate

## :card_index: Orders: type and status

- Limit buy order (or bid): order to buy the base token (e.g., ETH) at a price lower than current price in exchange of quote tokens (e.g., USDC)
- Limit sell order (or ask): order to sell the base token at a price higher than current price in exchange of quote tokens
- Collateral order: limit order which assets (quote token for a buy order, base token for a sell order) serve as collateral for a borrowed positions on the other side of the book (example: borrow ETH from a sell order by depositing USDC in a buy order)
- Borrowable order: order which assets can be borrowed
- Unborrowable order: order which asset cannot be borowed, either because the maker made it unborrowable or because the maker is a borrower

## :scroll: Rules

1. Taking an order liquidates all positions which borrow from it
2. Removing an order cannot liquidate positions, only relocate them on the order book
3. If not enough assets can be relocated, removing is partial
4. Users cannot borrow assets from collateral orders (see definition supra)
5. Users whose assets are borrowed cannot use the same assets as collateral to borrow
6. Taking a collateral order has the effect of closing the maker's borrowing positions
7. Orders cannot be taken at a loss. A price oracle is pulled before any taking to check the condition

### Notes regarding 6.

See Potential issue 3. in [ISSUES.md](ISSUES.md#3)

### Notes regarding 7.

See Potential issue 2. in [ISSUES.md](ISSUES.md#2)

## Excess collateral

Strictly speaking, users doesn't have to choose between being a lender or a borrower:

- They can be lender in one side of the book and borrower in the other side
- They can always borrow based on their excess collateral
- Users can borrow their excess collateral

**Excess collateral** in base token X  is total deposits of X backing all users sell orders minus 




