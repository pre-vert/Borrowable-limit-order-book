# :book: Borrowable Limit Order Book - FUNCTIONS

## Core functions

```solidity
placeOrder(
    uint256 _quantity,
    uint256 _price,
    bool _isBuyOrder
) external;
```

Who: Maker

Consequences:

- increases collateral and borrowing capacity for the maker
- more borrowable assets for other borrower
- more orders to relocate positions from removed orders

Inputs :

- type: bid or ask
- quantity
- price
- interest rate

Tasks:

- performs sanity checks
- transfers tokens to the pool
- updates orders, users and borrowable list
- emits event

```solidity
removeOrder(
    uint256 _removedOrderId,
    uint256 _quantityToRemove
) external;
```

Who: Maker (remover)

Consequences:

- less collateral and borrowing capacity for the remover
- less borrowable assets for other borrower

Inputs :

- removed order id
- quantity to be removed (can be partial)

Tasks:

- performs sanity checks
- calls \_displaceAssets(): scan available orders to reposition debt at least equal to quantity to be removed
- transfers tokens to the remover (full or partial)
- updates orders, users (borrowFromIds) and borrowable list (delete removed order)
- emits event

```solidity
function takeOrder(
    uint256 _takenOrderId,
    uint256 _takenQuantity
) external;
```

Who: anyone (including the maker and borrowers of the order)

Consequences:

- borrowing positions are liquidated
- less orders and assets in the book
- less collateral and borrowing capacity for the maker which order is taken

Inputs :

- \_takenOrderId id of the order to be taken
- \_takenQuantity quantity of assets taken from the order

Tasks:

- performs sanity checks
- calls \_displaceAssets(): liquidates all borrowing positions
- checks taker's balance and allowance
- if all assets are taken, remove:
  - order in orders
  - orderId in depositIds array in users
  - orderId from the list of borrowable orders
- otherwise adjust internal balances
- transfers ERC20 tokens between the taker and the maker
- emits event

```solidity
borrowOrder(
    uint256 _borrowedOrderId,
    uint256 _borrowedQuantity
) external;
```

Who: makers with enough deposited assets

Consequences:

-

Inputs :

- \_borrowedOrderId id of the order which assets are borrowed
- \_borrowedQuantity quantity of assets borrowed from the order

Tasks:

- performs sanity checks
- checks if borrower has enough collateral
- if the borrower doesn't currently borrow from the order, a new borrowing position is created:
  - adds orderId to borrowFromIds array in users
  - adds position to positions array
  - adds positionId to positionIds array in orders
- updates borrowable list:
  - deletes order if its assets are now fully borrowed
  - removes all orders placed by the borrower from the borrowable list
- transfers ERC20 tokens to borrower
- emits event

```solidity
repayBorrowing(
    uint256 _repaidOrderId,
    uint256 _repaidQuantity
) external;
```

Who: borrowers

Consequences:

- releases collateral for the borrower
- may unlock removal of collateral
- more borrowable assets for other borrower

Inputs :

- \_borrowedOrderId id of the order which assets are borrowed
- \_borrowedQuantity quantity of assets borrowed from the order

Tasks:

- sanity checks
- update positions: decrease borrowed assets
- if borrowing is fully repaid, delete:
  - position in positions
  - positionId from positionIds in orders
  - if user is not a borrower anymore, include all his orders in the borrowable list
- transfers ERC20 tokens to borrower
- emits event

## Internal functions

```solidity
_evaluateNewOrder(
    uint256 targetPrice, // ideal price (price of removed order)
    uint256 closestPrice, // best price so far
    uint256 newPrice, // price of next order in order list
    address borrower, // borrower of displaced order
    bool isBuyOrder // type of removed order (buy or sell)
)
    internal
    returns (uint256 bestPrice)
```

```solidity
_displaceAssets(
  uint256 _fromOrderId, // order from which borrowing positions must be cleared
  uint256 _quantityToDisplace, // quantity removed or taken
  bool _liquidate // true if taking, false if removing
)
  internal
    returns (uint256 displacedQuantity)
```

Called by removeOrder() and takeOrder()

Scan orders in borrowable list to reposition the debt at least equal to quantity to be removed or taken:

- calls findNewPosition(): finds available orders:
- calls reposition(): relocate debt from removed order to available orders
- updates repositioned quantity
- stop when repositioned quantity >= quantity to be removed

```solidity
_findNewPosition(uint256 _positionId
)
  internal
  positionExists(_positionId)
  returns (uint256 bestOrderId)
```

Called by removeOrder() for each borrowing position to relocate
Scan buyOrderList or sellOrderList for alternative order

input: positionId: borrowing position to be relocated
output: returns newOrderId: the new order id if succesful or the removed order id if failuer

Tasks:

- compute maxIterations as the min between maxListSize and

```solidity
_reposition(
  uint256 _fromPositionId, // position id to be removed
  uint256 _toOrderId // order id to which the borrowing is relocated
)
  internal
  positionExists(_fromPositionId)
  orderExists(_toOrderId)
  returns (bool success)
```

Called by RemoveOrder(), once a new order has been found

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

```solidity
_liquidate(uint256 _positionId
)
  internal
  positionExists(_position[_positionId])
```