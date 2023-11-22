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

- `_quantity`: quantity deposited
- `_price`: order's limit price
- `_isBuyOrder`: buy order or sell order


Tasks:

- performs guard checks
- calls increaseDeposit() is an order already exists, or stores a new one in orders
- updates orders and users
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

- `_removedOrderId`: removed order id
- `_quantityToRemove`: quantity to be removed (can be partial)

Tasks:

- performs guard checks
- compute removable assets as total assets in order - asset lent - minimum deposit
- updates orders (reduce quantity, possibly to zero)
- transfers tokens to remover (full or partial)
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

- `_borrowedOrderId`: id of the order which assets are borrowed
- `_borrowedQuantity`: quantity of assets borrowed from the order

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
    uint256 _positionId,
    uint256 _repaidQuantity
) external;
```

Who: borrowers

Consequences:

- releases excess collateral for borrower
- unlock removal of collateral
- more borrowable assets for other borrowers

Inputs :

- `_positionId`: position id describing the position
- `_borrowedQuantity`: quantity of assets borrowed from the order

Tasks:

- sanity checks
- update positions: decrease borrowed assets
- transfers ERC20 tokens from borrower to contract
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

- `_takenOrderId`: id of the order to be taken
- `_takenQuantity`: quantity of assets taken from the order

Tasks:

- performs guard checks
- taking can be
  - full (total assets - borrowed assets)
  - partial (< total assets - borrowed assets - minimum deposit)
- liquidates all borrowing positions (calls \_liquidateAssets())
- updates orders (reduce quantity, possibly to zero)
- transfers ERC20 tokens between taker and maker
- emits event

## Internal functions

```solidity
function _liquidatePosition(uint256 _positionId)
  internal
  positionExists(_positionId)
  returns (bool)
```

Called by: liquidateAssets()

Consequences:

- Change borrower excess collateral: if quote (base) tokens are taken:
  - reduce borrower's borrowed assets in quote (base) tokens (EC is increased)
  - reduce borrower's collateral assets in base (quote) tokens (EC is decreased)
- borrower's EC does not change as liquidated assets are just equal to written off debt

Input :

- `_positionId`: position id to be liquidated

Tasks:

- guard checks
- update positions: decrease borrowed assets
- transfers ERC20 tokens from borrower to contract
- emits event