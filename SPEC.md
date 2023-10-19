# :book: Borrowable Limit Order Book - SPEC

## :family: Actors

- Makers:
  - place orders
  - receive interest
  - can make their order unborrowable
- Makers/borrowers:
  - place orders and borrow from other-side orders
  - pay interest
- Takers:
  - take orders on the book and exchange at limit price
- Liquidators:
  - liquidate borderline positions due to growing interest rate

## :card_index: Orders: type and status

- Limit buy order (or bid): order to buy the base token (e.g., ETH) at a price lower than current price in exchange of quote tokens (e.g., USDC)
- Limit sell order (or ask): order to sell the base token at a price higher than current price in exchange of quote tokens
- Collateral order: limit order which assets (quote token for a buy order, base token for a sell order) serve as collateral for a borrowed positions on the other side of the book (example: borrow ETH from a sell order by depositing USDC in a buy order)
- Borrowable order: order which assets can be borrowed
- Unborrowable order: order which asset cannot be borowed, either because the maker made it unborrowable or because the maker is a borrower

## :twisted_rightwards_arrows: Data Structure UML Overview

The UML diagram visually represents the relationships and structures of a Solidity contract's data model.

![](/Images/lendbook_ulm.png)

### Entities:

#### 1. **User**
Represents an individual or entity participating in the system.
- **Attributes**:
  - `mapping id: address`: A unique identifier for each user, which is their Ethereum address.
  - `depositIds: uint256[]`: An array storing the IDs of orders where the user has deposited assets.
  - `borrowFromIds: uint256[]`: An array keeping track of the IDs of orders from which the user has borrowed assets.

#### 2. **Order**
Represents a buy or sell order placed in the system.
- **Attributes**:
  - `mapping id: orderId`: A unique identifier for each order.
  - `maker: address`: The Ethereum address of the user who places the order.
  - `isBuyOrder: bool`: A flag to determine if the order is a buy (`true`) or sell (`false`).
  - `quantity: uint256`: The number of assets specified in the order.
  - `price: uint256`: The price set for the order.
  - `positionIds: uint256[]`: An array that lists the IDs of positions that have borrowed from this particular order.
- **Methods**:
  - `deposit()`: To place an order.
  - `increaseDeposit()`: To deposit assets for an order.
  - `withdraw()`: To withdraw assets from an order.
  - `take()`: To take or fulfill an order.
  - `borrow()`: To borrow against an order.
  - `repay()`: To repay the borrowed amount for an order.

#### 3. **Position**
Represents the assets borrowed from a specific order.
- **Attributes**:
  - `mapping id: positionId`: A unique identifier for each position.
  - `borrower: address`: The Ethereum address of the user who has borrowed the assets.
  - `orderId: uint256`: The ID linking back to the order from which the assets were borrowed.
  - `borrowedAssets: uint256`: The quantity of assets that have been borrowed.
- **Methods**:
  - `borrow()`: To initiate borrowing against an order.
  - `repay()`: To repay the borrowed assets.

### Relationships:

1. **User to Order**: 
A user can place multiple orders, and each order is associated with a specific user. This relationship is depicted by the line connecting `User` to `Order`.

2. **User to Position**: 
A user, in the capacity of a borrower, can open multiple positions. Each position is linked to a user as the borrower. This relationship is represented by the line connecting `User` to `Position`.

3. **Order to Position**: 
An order can be associated with multiple positions when different borrowers borrow assets from the same order. This relationship is shown by the line linking `Order` to `Position`.


## :scroll: Orderbook's rules

1. Taking an order liquidates all positions which borrow from it
2. Removing is limited to unborrowed assets, it cannot liquidate positions on the order book
3. Users cannot borrow assets from collateral orders (see definition supra)
4. Users whose assets are borrowed cannot use the same assets as collateral to borrow
5. Taking a collateral order has the effect of closing the maker's borrowing positions
6. Orders cannot be taken at a loss. A price oracle is pulled before any taking to check the condition

## Minimal deposit size and a minimal non-borrowable assets for orders

We want arbitragers to have minimal incentives to take an order when the limit price is crossed. This is not the case if 100\% of the order's assets are borrowed. A minimal part of the assets must be non-borrowable, and as a consequence, a minmal deposit size is necessary.

Example: in the ETH USDC market, a buy order must have at least 100 USDC available for a taker. If the minimal deposit is 100 USDC, the borrowable part of the order is y - 100 with y >= 100 USDC the deposited assests.

## Excess collateral

Users can be lenders in one side of the book and borrowers in the other side as long as their excess collateral is positive.

**Excess collateral** for a user and an asset $X$ is the sum of:

- her assets $X$ deposited in active orders 
- minus assets which collateralize her borrowing positions in $Y$
- minus assets that other users borrow from her orders

Excess collateral must be positive for all users at any time. It can be used to:

- borrow more assets $Y$
- let other users borrow more assets $X$ from the user

as long as it remains positive.

Removal is limited to excess collateral. To be fully removed, an order must satisfy:

- all positions borrowing from the order being repaid
- all positions collateralized by the order being repaid

Excess collateral increases when the user deposits more assets, repays a position, or other users repay their borrowing from the user's order. Conversely, a positive excess collateral can be used to remove assets, borrow more assets, or let other users borrow more assets from user's limit orders

Taking an order triggers the following actions:

- all positions borrowing from the order are liquidated (even if taking is partial)
- enough positions collateralized by the order are liquidated, so that excess collateral cannot become negative

Deposit more assets $X$ in the order book or repaying a position, or other borrowers repaying a position borrowing from the user's order increases excess collateral:

- more assets can be borrowed from order
- owner of order can borrow more assets