# :book: Borrowable Limit Order Book - SPEC

## :family: Actors

- Makers:
  - place orders
  - receive interest
  - liquidate borderline positions due to growing interest rate
  - can make their order unborrowable
- Makers/borrowers:
  - place orders and borrow from other-side orders
  - pay interest
- Takers:
  - take orders on the book and exchange at limit price

## :card_index: Orders: type and status

- Limit buy order (or bid): order to buy the base token (e.g., ETH) at a price lower than current price in exchange of quote tokens (e.g., USDC)
- Limit sell order (or ask): order to sell the base token at a price higher than current price in exchange of quote tokens
- Collateral order: limit order which assets (quote token for a buy order, base token for a sell order) serve as collateral for a borrowed positions on the other side of the book (example: borrow ETH from a sell order by depositing USDC in a buy order)
- Borrowable order: order which assets can be borrowed
- Unborrowable order: order which asset cannot be borowed, either because the maker made it unborrowable or because the maker is a borrower

## :scroll: Rules

1. Taking an order liquidates enough positions which borrow from it
2. Removing an order cannot liquidate nor relocate positions on the order book
3. Removing is limited to unborrowed assets
4. Users cannot borrow assets from collateral orders (see definition supra)
5. Users whose assets are borrowed cannot use the same assets as collateral to borrow
6. Taking a collateral order has the effect of closing the maker's borrowing positions
7. Orders cannot be taken at a loss. A price oracle is pulled before any taking to check the condition
