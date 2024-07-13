# :clipboard: TO DO list

## 1. Things to do

- deux pentes IRM
- oracles chainlink
- liquidation fees

progressive liquidation costs (high for low amount)

adaptative curve
https://docs.morpho.org/concepts/morpho-blue/core-concepts/irm/

replacement
https://discord.com/channels/1159035200001540198/1231138149632184320/1231139864590680135

trade fees

### 1.1 Connect to a lending layer for a minimal return

Assets deposited as collateral, are relocated in a risk-free base layer, like Aave or Morpho Blue, to earn a minimal return.

Suppose Alice and Carol both place a buy order at the same limit price 2000 for 1 ETH. Bob deposits 1 ETH and borrows 2000 USDC from Alice's order. Normally, Alice cannot remove her 2000 USDC. However, there exists three complementary ways to set Alice's order free.

### 1.2 Implement a break on interest variations

$$
R_t = \phi R^* + (1-\phi) R_{t-1}
$$

Espcially important at start when liquidity and borrows are low





