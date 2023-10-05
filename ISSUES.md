# :microscope: Borrowable Limit Order Book - POTENTIAL ISSUES

### Issue [1](#1). The liquidation of a borrowing position following the removal of an order would need a swap in an external AMM

Example:

- Alice deposits 3600 USDC and places a buy order at price 1800 for 2 ETH
- Bob deposits 1 ETH and places a sell order at price 2200 USDC
- Bob borrows 1800 USDC from Alice's buy order
- At current price $p \in (1800, 2200)$, Alice removes her order and claims 3600 USDC
- If Bob's position cannot be relocated, he's liquidated, but his collateral is in ETH, not USDC

:pill: Solutions:

- The protocol takes enough ETH from Bob, swaps them for 1800 USDC and gives Alice the proceeds (if the proceeds is less than 1800 USDC, the swap is canceled and Alice is given 1 ETH)
- Alice is prevented from removing the part of assets which would liquidate the borrowing positions

I have a preference for the second solution. The first one relies on the protocole being able to programmatically execute a swap on an external AMM at a satisfactory rate, which could be challenging.

### Issue [2](#2) (critical). A maker takes her own limit order instead of cancelling it. This hurts the borrowing positions

Example:

- Alice deposits 3600 USDC and places a buy order at price 1800 for 2 ETH
- Bob deposits 1 ETH and places a sell order at price 2200 USDC
- With the collateral, he borrows 1800 USDC from Alice's buy order
- At current price $p \in (1800, 2200)$, Alice takes her own buy order for 1 ETH and receives 1800 USDC
- If Bob's position cannot be relocated, this forces Bob to exchange his collateral (1 ETH) against 1800 USDC
- Bob has lost $p - 1800$ USDC. Alice profits.

Relocating the debt to another buy order avoids Bob's liquidation and prevents the attack but won't be always feasible.

:pill: Solution: pulling the price of an oracle before any taking to forbid snapping an order at a loss.

### Issue [3](#3). When collateral orders (orders which serve as collateral for borrowing positions) are taken, an asset mismatch appears.

Example:

- Alice deposits 1800 USDC and places a buy order at price 1800 for 1 ETH
- Bob deposits 1 ETH and places a sell order at price 1900 USDC
- With the collateral, he borrows 1800 USDC from Alice's buy order
- Market price increases to 1900 USDC, Bob's order is taken
- Bob's collateral is now 1900 USDC instead of 1 ETH.
- If the price reverts and decreases to 1800 USDC, Alice claims 1 ETH but could only obtain 1900 USDC

:pill: Two solutions:

- Bob's borrowing position is closed when his own order is taken first
  - the protocol uses the 1900 USDC to pay back his borowing position of 1800 USDC
  - Alice's order can now be taken for 1800 USDC by a taker if the price decreases to 1800 USDC
  - Bob makes a profit of 100 USDC, which comes from holding 1 ETH which pric has appreciated
- Bob's borrowing position is kept intact when his own order is taken first
  - Bob has to close out his position by himself
  - If the price reverts and decreases to 1800 USDC, Alice's buy order cannot be filled for 1 ETH
  - In compensation she gets 1900 USDC instead of 1800 USDC

The first solution is more in line with what Alice and Bob intended when she placed a buy order and he borrowed from it.

### Issue [4](#4). Maker borrows her own order.

?
