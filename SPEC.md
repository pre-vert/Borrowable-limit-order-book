# Borrowable Limit Order Book - SPEC

## Actors

- Makers: only place orders
- Makers/borrowers: place orders and borrow from other-side orders (borrowers for short)
- Takers: take orders
- Keepers: liquidate borderline positions due to growing interest rate

## Functions

### Place order

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

### Remove order

Who: Maker (remover)

Inputs :

- removed order id
- quantity to be removed (can be partial)

Tasks:

- sanity checks
- scan available orders to reposition debt at least equal to quantity to be removed
  - relocate debt from removed order to available orders
  - update repositioned quantity
  - stop when repositioned quantity >= quantity to be removed
- perform full transfer if success, otherwise partial transfer
- transfer tokens to the remover
- update orders, users, positions and borrowable list
- emit event

### Take order

### Borrow order

### Repay borrowing
