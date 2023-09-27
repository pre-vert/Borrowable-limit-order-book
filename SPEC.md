# Borrowable Limit Order Book - SPEC

## Actors

- Makers: only place orders
- Makers/borrowers: place orders and borrow from other-side orders (borrowers for short)
- Takers: take orders
- Keepers: liquidate borderline positions due to growing interest rate

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
