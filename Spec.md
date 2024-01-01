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

We want arbitragers to have minimal incentives to take an order when the limit price is crossed. Available assets to take are deposited assets minus borrowed assets. Available assets should always be at least equal to minmal deposit. Reducing available assets in an order can be done three ways, each under different conditions:

withdraw:
- Has order lent assets?
  - No: is withdraw full?
    - Yes: no condition
    - No: remaining assets >= minimum deposit
  - Yes: remaining assets >= minimum deposit

borrow:
- remaining assets >= minimum deposit
  
take:
- Are all available assets taken?
  - Yes: no condition
  - No: remaining assets >= minimum deposit

## Price feed

A price feed is pulled when:
- a borrowed order is taken to check that the order is not taken at a loss
- a borrower is liquidated

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

On the quote side of the book, lenders earn an interest rate on the borrowable part of their deposits, regardless this part actually borrowed, partially or fully.

They don't earn an interest on the non borrowable part, whether a minimum non borrowable deposit or more as chosen by the depositor.

On the base side of the book, deposits serve as collateral and do not earn an interest.

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

### Calculation

The interest rates in the buy and sell markets are set according to a linear function of utilization rates: $r_t = \alpha + \beta \text{UR}_t.

### Increase deposit at date T after a deposit at date t

1. Call _incrementWeightedRates(): increment time-weighted and UR-weighted rates:
  - pull current block.timestamp $n_t$ (in seconds) and computes elapsed time $n_t - n_{t-1}$ since last update
  - add $(n_T - n_{T-1}) IR_{T-1}$ to TWIR_{T-1}
  - add $(n_T - n_{T-1}) IR_{T-1} UR_{T-1}$ to TUWIR_{T-1}
  - use $IR_{T-1}$ based on UR_{T-1} valid between $T-1$ and $T$, according to the linear formula
2. Add interest rate to existing deposit
  - compute average past interest rate thanks to Taylor expansion, including $IR_{T-1} UR_{T-1}$
  - multiply UR-weighted interest rate by quantity = accrued interest rate
  - update TWIR_t to TWIR_T to reset interest rate in deposit to zero
  - add accrued interest rate to existing deposit
  - add accrued interest rate to pool's total deposit => update UR_T
3. Add new deposit to existing one
4. Add new deposit to pool's total deposit => update UR_T

Note: $UR_T$ will be used to determine $IR_{T+1}$ in the next iteration

### Decrease borrowing position at date T after a first borrow at date t

Steps 1. and 2. are the same
3. Substract withdraw from existing quantity
4. Substract withdraw from pool's total deposit => update UR_T

### Increase borrowing position at date T after a first borrow at date t

Step 1.is the same

2. Add interest rate to existing borrowed quantity
  - compute average past interest rate thanks to Taylor expansion, including $IR_{T-1}$
  - multiply interest rate by quantity = accrued interest rate
  - update TWIR_t to TWIR_T to reset interest rate in borrow to zero
  - add accrued interest rate to borrowed quantity
  - add accrued interest rate to pool's total borrow => update UR_T
3. Add new borrow to existing quantity
4. Add new borrow to pool's total borrow => update UR_T

### Decrease borrowing position at date T after a first borrow at date t

Steps 1. and 2. are the same
3. Substract repay to existing quantity
4. Substract repay to pool's total borrow => update UR_T


### Interest-based liquidation

Borrowing positions is closed out when the limit order from which assets are borrowed is taken, but also when the borrower runs out of collateral to pay a growing interest rate. See [white paper](llob_wp.pdf) for details.

When all remaining collateral is exhausted by the interest rate, the maker/lender can seize the collateral and collect a 2% fee.

Example: Bob borrows 2000 at 10%. One year later, his position is liquidated:

- interest rate is added to his loan which becomes 2200
- debt is now 2200
- his collateral is seized for 2200/p

Steps:

- check that the order is not profitable, if so call take() instead of liquidate()
- check liquidate() is called by maker
- check borrower's excess collateral is zero or negative
- pull price feed to calculate how much collateral to seize and transfer to maker

## Self-replacing orders

Orders which assets are taken are automatically replaced on the other side of the book.

The new limit price is chosen by the maker and by default is set + 10% if the order is a buy order and - 9% if a sell order. The paired price is necessarily higher (lower) than the current limit price if the order is a buy order (sell order).

When a user makes a new order, she specifies 2 limit prices: current limit price and a new attribute uint256 _pairedPrice. When order is taken, liquidity receives by maker (from taking and liquidations) after deduction of liquidty used to close maker's own position, is automatically reposted in a new order, the other side of the book and for which limit price is previous paired price and paired price is previous limit price.

Example: Alice deposits 3800 USDC and places a buy order at 1900 USDC. She specifies a dual limit price at 2000 USDC. Once filled at 1900, the converted assets (2 ETH) are automatically reposted in a sell order at 2000 USDC. If the price reverts to 2000 and her sell order is taken, her profit is 4000 - 3800 = 200 USDC. The USDC are automatically reposted in a buy order at 1900.

For orders which assets are not borrowed, the replacement applies to the part of the assets taken. If orders have part of their assets borrowed, the associated collateral is replaced in the paired order, after all borrowing positions have been liquidated.

A (non) borrowable order filled and replaced on the other side of the book is still (non) borrowable.

Consider the case of someone who has a borrowing position B in token X collateralized by an order A in token Y. If order A is filled, position B is first closed before any token X received in exchange of Y from the filling can be replaced in the other side of the book.

## Change limit price

Allows Maker to change the limit price of their order

If the order is borrowed, the change takes effect after the borrowing is paid back. Only allows replacing further away from current price.

## Non borrowable orders

 Users are given the choice to make their orders non borrowable

Makers can choose to make their order non borrowable when the order is placed or at any time during the life of the order. If the order is made non-borrowable while its assets are borrowed, the order becomes non-borowable after the borrowing is repaid.


