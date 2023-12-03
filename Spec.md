# :book: Borrowable Limit Order Book - SPEC

## :family: Actors

- Makers/lenders:
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
  - `pairedPrice: uint256`: The price set for the paired order.
  - `isBorrowable: bool`: Whether the order can be borrowed.
  - `positionIds: uint256[]`: An array that lists the IDs of positions that have borrowed from this particular order.
- **Methods**:
  - `deposit()`: To place an order.
  - `withdraw()`: To withdraw assets from an order.
  - `take()`: To take or fulfill an order.
  - `changeBorrowable()`: Switch order between borrowable and non borrowable.

#### 3. **Position**
Represents the assets borrowed from a specific order.
- **Attributes**:
  - `mapping id: positionId`: A unique identifier for each position.
  - `borrower: address`: The Ethereum address of the user who has borrowed the assets.
  - `orderId: uint256`: The ID linking back to the order from which the assets were borrowed.
  - `borrowedAssets: uint256`: The quantity of assets that have been borrowed.
  - `timeWeightedRate` : Time-weighted average interest rate for the position
- **Methods**:
  - `borrow()`: To initiate borrowing against an order.
  - `repay()`: To repay the borrowed assets.
  - `liquidate()`: Liquidate a position becoming insolvent.

### Relationships:

1. **User to Order**: 
A user can place multiple orders, and each order is associated with a specific user. This relationship is depicted by the line connecting `User` to `Order`.

2. **User to Position**: 
A user, in the capacity of a borrower, can open multiple positions. Each position is linked to a user as the borrower. This relationship is represented by the line connecting `User` to `Position`.

3. **Order to Position**: 
An order can be associated with multiple positions when different borrowers borrow assets from the same order. This relationship is shown by the line linking `Order` to `Position`.


## Orderbook's rules

See [white paper](llob_wp.pdf) for explanations.

1. Taking an order liquidates all positions which borrow from it
2. Removing is limited to unborrowed assets, it cannot liquidate positions on the order book
3. Users cannot borrow assets from orders which serve as collateral
4. Users whose assets are borrowed cannot use the same assets as collateral to borrow
5. Taking a collateral order has the effect of closing the maker's borrowing positions
6. Orders cannot be taken at a loss. A price oracle is pulled before any taking to check the condition
7. Orders which assets are taken are automatically replaced the opposite side of the order book.

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

## Interest rate model

### General model with examples

- Alice deposits a buy order with 6000 USDC (p = 2000)
- Bob deposits a sell order with 3 ETH (p = 2100)
- Bob borrows 4000 USDC from Alice at date t, interest rate is 10%
- 1 year later, Bob's Borrow is 4400

#### Case 1. Bob repays his position

- repays 4400 USDC, can take back his 3 ETH from his sell order

#### Case 2. Alice's buy order is taken first for 2000

- Bob's position is liquidated for 4400
- Alice receives (2000 + 4400)/p = 1 + 2.2 ETH
- Bob's sell order is reduced by 2.2 ETH

#### Case 3. Bob's sell order is taken first for 3 ETH

- Bob receives 3*p = 6300
- from which 4400 are used to repay his loan

#### Case 4. Bob increases his borrowing

- increase borrowing position by 400 at date t'
- restarts R_t to R_{t'}

### Calculation

The interest rates in the buy and sell markets are set according to a linear function of utilization rates: $r_t = \alpha + (\beta + \gamma) \text{UR}_t + \gamma \text{UR}_t^*$, with $\text{UR}_t^*$ the utilization rate of the opposite market.

### Steps

When a user deposits, withdraws, borrows, repays or liquidates a loan, the protocol:

- call _incrementTimeWeightedRates()
  - pull current block.timestamp $n_t$ (in seconds) and computes elapsed time $n_t - n_{t-1}$ since last update
  - increment time-weighted rates since origin $\text{TWIR}_t = n_1 IR_0 + (n_2 - n_1) IR_1 + ... + (n_t - n_{t-1}) IR_{t-1}$
  - use $IR_{t-1}$ based on UR valid between $t-1$ and $t$, according to the linear formula
- update total deposits and total borrowings in the affected market
  - $UR_t$ and $UR_t^*$ will be used to determine $IR_t$ in the next iteration

In addition, when a user borrows from a limit order, the protocol:

- store the updated $\text{TWIR}_t$ in borrowing position struct

When a borrower repays or closes his loan, or he's liquidated at date $T$, the protocol:

- calculate $DR_t = TWIR_T - TWIR_t = (n_{t+1} - n_t) IR_t + ... + (n_T - n_{T-1}) IR_{T-1}$
- compute interest rate $e^{DR_t} - 1$ thanks to Taylor approximation.

#### Decrease borrowing

Bob borrows 2000 at 10%. One year later, he pays back 1000:

- interest rate is added to his loan which becomes 2200
- $\text{TWIR}_t$ of his borrowing position is updated to TWIR$_T$
- pays 1000 from 2200
- debt is now 1200

#### Increase borrowing

Bob borrows 2000 at 10%. One year later, he borrows 1000 more:

- interest rate is added to his loan which becomes 2200
- $\text{TWIR}_t$ of his borrowing position is updated to $\text{TWIR}_T$
- 1000 is added to 2200
- debt is now 2200

#### Liqudation

Bob borrows 2000 at 10%. One year later, his position is liquidated:

- interest rate is added to his loan which becomes 2200
- debt is now 2200
- his collateral is seized for 2200/p

#### Partial closing

Bob borrows 2000 at 10%. One year later, his own limit order which serves as collatera is taken. His position is reduced by 1000 

- interest rate is added to his loan which becomes 2200
- debt is now 2200
- part of the collateral taken is seized for 1000/p to reduce his debt by 1000

### Interest-based liquidation

Positions can be liquidated when the price hasn't crossed the limit price if the accumulated interest rate exhausts borrower's excess collateral, see [white paper](llob_wp.pdf) for details

- check that the order is not profitable, if so call take() instead of liquidate()
- check liquidate() is called by maker
- check borrower's excess collateral is zero or negative
- pull price feed to calculate how much collateral to seize and transfer to maker

## Self-replacing orders

Orders which assets are taken are automatically replaced on the other side of the book.

The new limit price is chosen by the maker and by default is set + 10% if the order is a buy order and - 9% if a sell order. The paired price is necessarily higher (lower) than the current limit price if the order is a buy order (sell order).

For orders which assets are not borrowed, the replacement applies to the part of the assets taken. If orders have part of their assets borrowed, the associated collateral is replaced in the paired order, after all borrowing positions have been liquidated.

A (non) borrowable order filled and replaced on the other side of the book is still (non) borrowable.

Consider the case of someone who has a borrowing position B in token X collateralized by an order A in token Y. If order A is filled, position B is first closed before any token X received in exchange of Y from the filling can be replaced in the other side of the book.