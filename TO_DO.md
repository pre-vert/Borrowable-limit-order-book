# :clipboard: TO DO list

## Things to do

### 1. Give users the choice to make their orders non borrowable

Makers can choose to make their irder non borrowable when the order is placed or at any time during the life of the order.

If the order is made non-borrowable while its assets are borrowed, the order becomes non-borowable after the borrowing is repaid.

### 2. Implement interest rate

The interest rate is chosen by makers when the order is placed.

- add a new attribute uint256 interest rate to orders
- modify placeOrder()
- compute accrued interest rate
- add a methof for makers to change the interest rate of an order. If the order is borrowed, the change takes effect after the order is repaid.
- allow maker to liquidate a loan after excess collateral has been exhausted by the interest load

### 3. Implement price feed

A price feed is pulled whenever a borrowed order is taken to check that the order is not taken at a loss.

### 4. Implement getBookSize

Number of orders on both sides of the book.

## Things to be done with low priority

### 5. Implement changeLimitPrice()

Allows Maker to change the limit price of their order. If the order is borrowed, the change takes effect after the borrowing is paid back.

### 6. Gives the possibility to borrow or lend based on excess collateral

Users can currently be lender in one side of the book and borrower in the other side but cannot be both borrower and lender on the same side. A more capital efficient way is to condition on excess collateral.

Excess collateral in X is total deposits of X minus collateral needed to provide liquidated assets, were all borrowing positions in Y were liquidated.

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

## Things which could be done

### 7. Implement offsetting

Offsetting is the action for a lender at limit/liquidation price $p$ to borrow assets at the same limit price $p$, which is equivalent to removing assets from an order which is borrowed.

Suppose Alice and Carol both place a buy order at the same limit price 2000 for 1 ETH. Bob borrows 1 ETH from Alice's order. Normally, Alice cannot remove her 1 ETH. However, if Carol's interest rate is not higher than Alice's one, she can borrow 1 ETH from Carol without additional collateral requirement. This has the same effect as removing 1 ETH. Bob is now borrowing from Carol.

### 8. Implement self-replacing orders

Self-replacing orders are orders which, once filled, are automatically reposted in the order book at a limit price specified by the maker.

Example: Alice deposits 3800 USDC and places a buy order at 1900 USDC and specifies a dual limit price at 2000 USDC. Once filled at 1900, the converted assets (2 ETH) are automatically reposted in a sell order at 2000 USDC. If the price reverts to 2000 and her sell order is taken, the 4000 USDC are automatically reposted in a buy order at 1900.

When a user makes a new order, she specifies 2 limit prices.

- add a new attribute uint256 _dualPrice to orders
- when an order is taken, check if a dual price is specified and, if so, repost the assets accordingly.

### 9. Implement lenders' soft exit

To avoid situations in which lenders' assets are indefinitely stuck, lenders could soft exit the lending position by calling a method which triggers a gradually increasing interest rate:
$$
r = \max(r_0 - \text{exit_penalty} + (1 + \alpha)^t, R)
$$

- $r_0$ is the interest rate before the method is called.
- exit_penalty temporarily reduces the interest rate and ensures that borrowers get enough time to close their position before the interest rate becomes too high
- $R$ is a ceiling for the interest rate
- $\alpha$ is the instantaneous increase rate


