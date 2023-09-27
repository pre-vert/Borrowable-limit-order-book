# Borrowable Limit Order Book - SPEC

## Actors

- Makers: only place orders, receive interest
- Makers/borrowers: place orders and borrow from other-side orders (borrowers for short), pay interest rate
- Takers: take orders
- Keepers: liquidate borderline positions due to growing interest rate

## Allowances

- Taking an order liquidates all positions which borrow from it and cannot be relocated
- Cancelling an order cannot liquidate positions, only relocate them on the order book

## Issues

1. A maker takes his own limit order instead of cancelling it => bypasses the cancellation constraint
2. A taker takes a limit order for \$1 at an arbitray price and liquidate borrowing positions => dust attack

Possible solutions:

- Cancelling liquidates positions which cannot be repositioned => makes 1. irrelevant ; ok if the book has enough liquidity to allow relocation most of the time
- Pulling the price of an oracle before any taking to forbid unprofitable takings => forbids 2.
- Imposing a minimum amount to take from an order to makes the attack costly (seems better)

## Core functions

### PlaceOrder()

Who: Maker

Inputs :

- type: bid or ask
- quantity
- price
- interest rate

Tasks:

- sanity checks
- transfer tokens to the pool
- update orders, users and borrowable list
- emit event

### RemoveOrder()

Who: Maker (remover)

Inputs :

- removed order id
- quantity to be removed (can be partial)

Tasks:

- sanity checks
- scan available orders to reposition debt at least equal to quantity to be removed
  - find available orders: findNewPosition()
  - relocate debt from removed order to available orders: reposition()
  - update repositioned quantity
  - stop when repositioned quantity >= quantity to be removed
- transfer tokens to the remover (full or partial)
- update orders, users (borrowFromIds) and borrowable list (delete removed order)
- emit event

### TakeOrder()

### BorrowOrder()

### RepayBorrowing()

## Internal functions

### findNewPosition()

Called by removeOrder() for each borrowing position to relocate

Scan buyOrderList or sellOrderList for alternative order

input: positionId

Tasks:

### reposition()

Called by RemoveOrder(), once a new order have been found

Update balances and state variables following a debt repositioning

inputs:

- positionId
- orderId
- orderToId

Tasks:

- update positions (delete previous position, create new one)
- update positionIds in orders (create a new positionId)
- update borrowFromIds in users (delete previous positionId, create new positionId)
- update buy or sellOrderList (orderTo may become unborrowable)
