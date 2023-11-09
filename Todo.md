# :clipboard: TO DO list

## 1. Things to do

### 1.1 Implement price feed

A price feed is pulled when:
- a borrowed order is taken to check that the order is not taken at a loss
- a user creates a new order to check that the price is in the money for takers
- a borrower is liquidated

### 1.2 Implement interest rate

The interest rate is chosen by makers when the order is placed.

- add a new attribute uint256 interest rate to orders
- modify deposit()
- compute accrued interest rate
- add a method for makers to change the interest rate of an order. If the order is borrowed, the change takes effect after the order is repaid.
- allow maker to liquidate a loan after excess collateral has been exhausted by the interest load

### 1.3 Implement interest rate-based liquidation

Borrowing positions are closed out when the limit oder from which assets are borrowed is taken, with one exception: when the borrower runs out of collateral to pay a growing interest load.

When all remaining collateral is exhausted by the interest load, the maker/lender can seize the collateral and collect a 1% fee.




## 2. Lower priority

### 2.1.a Change limit price

Implement changeLimitPrice(orderId, newPrice): allows Maker to change the limit price of their order. If the order is borrowed, the change takes effect after the borrowing is paid back. Only allows replacing further from current price.

### 2.1.b Change stop price

Implement changeStopPrice(orderId, newPrice): allows borrowers to change the stop (or closing) price of their order.

### 2.2 Connect to a lending layer for a minimal return

Assets not borrowed, either because they don't mactch a loan demand or serve as collateral are deposited in a risk-free base layer, like Aave or Morpho Blue, to earn a minimal return.

### 2.3 Give users the choice to make their orders non borrowable

Makers can choose to make their order non borrowable when the order is placed or at any time during the life of the order.

If the order is made non-borrowable while its assets are borrowed, the order becomes non-borowable after the borrowing is repaid.

### 2.4 Self-replacing orders

Self-replacing orders are orders which, once filled, are automatically reposted in the order book at a limit price specified by the maker.

Example: Alice deposits 3800 USDC and places a buy order at 1900 USDC. She specifies a dual limit price at 2000 USDC. Once filled at 1900, the converted assets (2 ETH) are automatically reposted in a sell order at 2000 USDC. If the price reverts to 2000 and her sell order is taken, her profit is 4000 - 3800 = 200 USDC. The USDC are automatically reposted in a buy order at 1900.

When a user makes a new order, she specifies 2 limit prices.

- add a new attribute uint256 _dualPrice to orders
- when an order is taken, check if a dual price is specified and, if so, repost the assets accordingly.

### 2.5 Implement custom errors

https://soliditylang.org/blog/2021/04/21/custom-errors/

## Things that could be done

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


