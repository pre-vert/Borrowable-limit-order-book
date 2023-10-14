# :clipboard: TO DO list

## 0. Things to do now

### 0.1 Borrow and lend based on excess collateral

Users can currently be lenders in one side of the book and borrowers in the other side but cannot be both borrowers and lenders on the same side. A more capital efficient way is to condition on excess collateral.

Excess collateral in X is total deposits of X minus collateral needed to provide liquidated assets, in the case all borrowing positions in Y are liquidated.

Let users:

- borrow based on their excess collateral
- borrow other's excess collateral

Removal is limited to excess collateral. To be fully removed, an order must satisfy:

- all positions borrowing from the order repaid
- all positions collateralized by the order repaid

Taking an order triggers the following actions:

- all positions borrowing from the order are liquidated (even if taking is partial)
- enough positions collateralized by the order are liquidated, so that excess collateral cannot become negative

Repaying a position borrowing from order increases excess collateral:

- more assets can be borrowed from order
- owner of order can borrow more assets

## 1. Things to do

### 1.1 Implement interest rate

The interest rate is chosen by makers when the order is placed.

- add a new attribute uint256 interest rate to orders
- modify placeOrder()
- compute accrued interest rate
- add a methof for makers to change the interest rate of an order. If the order is borrowed, the change takes effect after the order is repaid.
- allow maker to liquidate a loan after excess collateral has been exhausted by the interest load

### 1.2 Implement price feed

A price feed is pulled whenever a borrowed order is taken to check that the order is not taken at a loss.

### 1.3 getBookSize

Number of orders on both sides of the book.

### 1.4 Implement a minimal deposit size and a minimal non-borrowable size for orders

We want arbitragers to have minimal incentives to take an order when the limit price is crossed. This is not the case if 100\% of the order's assets are borrowed. A minimal part of the assets must be non-borrowable, and as a consequence, a minmal deposit size is necessary.

Example: in the ETH USDC market, a buy order must have at least 100 USDC available for a taker. If the minimal deposit is 100 USDC, the borrowable part of the order is y - 100 with y >= 100 USDC the deposited assests.

## 2. Lower priority

### 2.1 Change limit price

Implement changeLimitPrice(): allows Maker to change the limit price of their order. If the order is borrowed, the change takes effect after the borrowing is paid back.

### 2.2 Connect to a lending layer for a minimal return

Assets not borrowed, either because they don't mactch a loan demand or serve as collateral are deposited in a risk-free base layer, like Aave or Morpho Blue, to earn a minimal return.

### 2.3 Give users the choice to make their orders non borrowable

Makers can choose to make their order non borrowable when the order is placed or at any time during the life of the order.

If the order is made non-borrowable while its assets are borrowed, the order becomes non-borowable after the borrowing is repaid.

## Things that could be done

### 3.1 Self-replacing orders

Self-replacing orders are orders which, once filled, are automatically reposted in the order book at a limit price specified by the maker.

Example: Alice deposits 3800 USDC and places a buy order at 1900 USDC. She specifies a dual limit price at 2000 USDC. Once filled at 1900, the converted assets (2 ETH) are automatically reposted in a sell order at 2000 USDC. If the price reverts to 2000 and her sell order is taken, her profit is 4000 - 3800 = 200 USDC. The USDC are automatically reposted in a buy order at 1900.

When a user makes a new order, she specifies 2 limit prices.

- add a new attribute uint256 _dualPrice to orders
- when an order is taken, check if a dual price is specified and, if so, repost the assets accordingly.

### 3.2 Lenders' soft exit

To avoid situations in which lenders' assets are indefinitely stuck, lenders could soft exit the lending position by calling a method which triggers a gradually increasing interest rate:

$$
r = \max(r_0 - \text{exit_penalty} + (1 + \alpha)^t, R)
$$

- $r_0$ is the interest rate before the method is called.
- exit_penalty temporarily reduces the interest rate and ensures that borrowers get enough time to close their position before the interest rate becomes too high
- $R$ is a ceiling for the interest rate
- $\alpha$ is the instantaneous increase rate

### 3.3 Offsetting

Offsetting is the action for a lender at limit/liquidation price $p$ to borrow assets at the same limit price $p$, which is equivalent to removing assets from an order which is borrowed.

Suppose Alice and Carol both place a buy order at the same limit price 2000 for 1 ETH. Bob borrows 1 ETH from Alice's order. Normally, Alice cannot remove her 1 ETH. However, if Carol's interest rate is not higher than Alice's one, she can borrow 1 ETH from Carol without additional collateral requirement. This has the same effect as removing 1 ETH. Bob is now borrowing from Carol.


