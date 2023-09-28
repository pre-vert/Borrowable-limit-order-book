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

Issue 1. The liquidation of a borrowing position following the removal of an order could be challenging.

Example:

- Alice deposits 3600 USDC and places a buy order at price 1800 for 2 ETH
- Bob deposits 1 ETH and places a sell order at price 2200 USDC
- Bob borrows 1800 USDC from Alice's buy order
- At current price $p \in (1800, 2200)$, Alice removes her order and claims 3600 USDC
- If Bob's position cannot be relocated, he's liquidated, but his collateral is in ETH, not USDC

Solutions:

- The protocol takes enough ETH from Bob, swaps them for 1800 USDC and gives Alice the proceeds (if the proceeds is less than 1800 USDC, the swap is canceled and Alice is given 1 ETH)
- Alice is prevented from removing the part of assets which would liquidate the borrowing positions

I have a slight preference for the second solution. The first one relies on the protocole being able to programmatically execute a swap on an external AMM at a satisfactory rate, which could be challenging.

Issue 2 (critical). A maker takes her own limit order instead of cancelling it, which hurts the borrowing positions

Example:

- Alice deposits 3600 USDC and places a buy order at price 1800 for 2 ETH
- Bob deposits 1 ETH and places a sell order at price 2200 USDC
- With the collateral, he borrows 1800 USDC from Alice's buy order
- At current price $p \in (1800, 2200)$, Alice takes her own buy order for 1 ETH and receives 1800 USDC
- If Bob's position cannot be relocated, this forces Bob to exchange his collateral (1 ETH) against 1800 USDC
- Bob has lost $p - 1800$ USDC. Alice profits.

Relocating the debt to another buy order avoids Bob's liquidation and prevents the attack but won't be always feasible.

Solution: pulling the price of an oracle before any taking to forbid snapping an order at a loss.

## Core functions

```solidity
placeOrder(
        uint256 _quantity,
        uint256 _price,
        bool _isBuyOrder
    ) external;
```

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

```solidity
removeOrder(
        uint256 _removedOrderId,
        uint256 _quantityToBeRemoved
    ) external;
```

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

```solidity
function takeOrder(
        uint256 _takenOrderId,
        uint256 _takenQuantity
    ) external;
```

```solidity
borrowOrder(
        uint256 _borrowedOrderId,
        uint256 _borrowedQuantity
    ) external;
```

```solidity
repayBorrowing(
        uint256 _repaidOrderId,
        uint256 _repaidQuantity
    ) external;
```

## Internal functions

```solidity
_findNewPosition(uint256 _positionId)
        internal
        returns (uint256 newOrderId)
```

Called by removeOrder() for each borrowing position to relocate

Scan buyOrderList or sellOrderList for alternative order

input: positionId

Tasks:

```solidity
_reposition(
    uint256 _positionId,
    uint256 _orderToId,
    uint256 _borrowedAssets)
        internal
        returns (bool success)
```

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
