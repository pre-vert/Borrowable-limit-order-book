# :book: Borrowable Limit Order Book - FUNCTIONS

## Core functions

```solidity
deposit(
    uint256 _quantity,
    uint256 _price,
    bool _isBuyOrder
) external;
```

Who: Maker

Consequences:

- increases excess collateral:
  - more borrowing capacity for the maker
  - more borrowable assets for other borrower

Inputs :

- quantity deposited
- limit price
- type: buy order or sell order


Tasks:

- performs guard checks
- calls increaseDeposit() is an order already exists, or stores a new one in orders
- updates orders and users
- transfers tokens to the pool
- emits event

```solidity
function increaseDeposit(
    uint256 _orderId,
    uint256 _increasedQuantity
) external;
```

Who: Maker

Consequences:

- increases excess collateral:
  - more borrowing capacity for the maker
  - more borrowable assets for other borrower

Inputs :

- order id
- quantity added to the order


Tasks:

- performs guard checks
- updates quantity in orders
- transfers tokens to the pool
- emits event

```solidity
withdraw(
    uint256 _removedOrderId,
    uint256 _quantityToRemove
) external;
```

Who: Maker (remover)

Consequences:

- less excess collateral:
  - less borrowing capacity for the remover
  - less borrowable assets for other borrowers
- if removal is full, the order is deleted in orders (quantity is set to zero)

Inputs :

- removed order id
- quantity to be removed (can be partial)

Tasks:

- performs guard checks
- compute removable assets as total assets in order - asset lent - minimum deposit
- updates orders (reduce quantity, possibly to zero)
- transfers tokens to remover (full or partial)
- emits event

```solidity
function take(
    uint256 _takenOrderId,
    uint256 _takenQuantity
) external;
```

Who: anyone (including the maker and borrowers of the order)

Consequences:

- all borrowing positions are liquidated, even if $1 is taken from order
- maker's excess collateral is:
  - reduced as maker has less deposits
  - increased as lent assets are liquidated
  - increased as sufficient maker's orders are closed out
- less orders and assets in the book

Inputs :

- \_takenOrderId id of the order to be taken
- \_takenQuantity quantity of assets taken from the order

Tasks:

- performs guard checks
- taking can be
  - full (total assets - borrowed assets)
  - partial (< total assets - borrowed assets - minimum deposit)
- liquidates all borrowing positions (calls \_liquidateAssets())
- updates orders (reduce quantity, possibly to zero)
- transfers ERC20 tokens between taker and maker
- emits event

```solidity
borrow(
    uint256 _borrowedOrderId,
    uint256 _borrowedQuantity
) external;
```

Who: makers

Consequences:

-

Inputs :

- \_borrowedOrderId id of the order which assets are borrowed
- \_borrowedQuantity quantity of assets borrowed from the order

Tasks:

- performs guard checks
- checks if:
  - borrowed assets don't exceed available assets
  - maker has enough excess collateral
  - borrower has enough excess collateral
- if the borrower doesn't currently borrow from the order, a new borrowing position is created:
  - adds orderId to borrowFromIds array in users
  - adds position to positions array
  - adds positionId to positionIds array in orders
- transfers ERC20 tokens to borrower
- emits event

```solidity
repay(
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

- guard checks
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
