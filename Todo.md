# :clipboard: TO DO list

## 1. Things to do

### 1.1 Implement excess collateral protection against sudden interesrt-based liquidation

### 1.2 Term spread

## 2. Lower priority

### 2.1 Connect to a lending layer for a minimal return

Assets not borrowed, either because they don't mactch a loan demand or serve as collateral are deposited in a risk-free base layer, like Aave or Morpho Blue, to earn a minimal return.

### 2.2 Debt substituion

Suppose Alice and Carol both place a buy order at the same limit price 2000 for 1 ETH. Bob deposits 1 ETH and borrows 2000 USDC from Alice's order. Normally, Alice cannot remove her 2000 USDC. However, there exists three complementary ways to set Alice's order free.

#### 2.2.1 Borrower hops to another limit order

Bob switches his debt from Alice to Clair.

##### 2.2.2 Offsetting: Maker whose assets are borrowed borrows herself from another position ()

Offsetting is the action for a lender at limit/liquidation price $p$ to borrow assets at the same limit price $p$, which is equivalent to removing assets from an order which is borrowed.

Alice borrows 2000 USDC from Carol without additional collateral requirement. This has the same effect as removing 2000 USDC for Alice. After, internal accounts updated, Bob is now borrowing 2000 USDC from Carol.

It is beneficial for Alice if she wants to withdraw her assets from the buy order and beneficial to Bob and Clair

Rem 1: The protocol should check that Carol's interest rate is not higher than Alice's one, but this is normally not possible as the base interest rate is common to all positions and the term spread makes Clair's asset borrowable at a better term.

### 2.2.3 Borrow stealing

Clair pays back Alice with her USDC and replaces Alice by taking Bob's position 

It is profitable for Alice if Bob's interest rate is higher than current rate, especially if the term premium gets large.

Contentious

## 3. Things that could be done

### 3.1 Implement a break on interest variations

$$
R_t = \phi R^* + (1-\phi) R_{t-1}
$$

Espcially important at start when liquidity and borrows are low

### 3.2 Lenders' soft exit

To avoid situations in which lenders' assets are indefinitely stuck, lenders could soft exit the lending position by calling a method which triggers a gradually increasing interest rate:

$$
r = \max(r_0 - \text{exit_penalty} + (1 + \alpha)^t, R)
$$

- $r_0$ is the interest rate before the method is called.
- exit_penalty temporarily reduces the interest rate and ensures that borrowers get enough time to close their position before the interest rate becomes too high
- $R$ is a ceiling for the interest rate
- $\alpha$ is the instantaneous increase rate

### 3.3 Implement custom errors

https://soliditylang.org/blog/2021/04/21/custom-errors/



