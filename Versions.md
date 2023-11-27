## Borrowable Limit Order Book
## VERSIONING

### What's new in V0.1

- handle fixed point variables with WAD = 1e18 scaling
- add _reduceUserBorrow() and _closePosition()
- implement interest rate model (in progress):
  - add an appendix in wp explaining the model
  - add storage variables:
    - uint256 public lastTimeStampUpdate = block.timestamp; // # of periods since last time instant intrest rates have been updated
    - uint256 private quoteTimeWeightedRate = 0; // time-weighted average interest rate for the buy order market (quoteToken)
    - uint256 private baseTimeWeightedRate = 0; // time-weighted average interest rate for sell order market (baseToken)
    - uint256 public totalQuoteAssets = 0; // total quote assets deposited in buy order market
    - uint256 public totalQuoteBorrow = 0; // total quote assets borrowed in buy order market
    - uint256 public totalBaseAssets = 0; // total base assets deposited in sell order market
    - uint256 public totalBaseBorrow = 0; // total base assets borrowed in sell order market
  - add view functions:
    - quoteUtilizationRate()
    - baseUtilizationRate()
    - quoteInstantRate()
    - baseInstantRate()
  - add _updateInterestRate() (in progress)
  - more tests (TestInterestRate.t.sol)

### What's new in V0.2 ..


- implement interest rate model (see [Spec.md](Spec.md)):
  - utilization rates (UR) and interest rates (IR) in function of UR on both sides is updated every action (deposit, repay, take, borrow and repay)
  - borrower's IR is computed then added to borrowed quantity when the amount changes either because borrow is increased, decreased or partially liquidated
- more tests (essentially in TestLiquidate.t.sol and TestInterest.t.sol)
- code optimization
- remains to code: see [Todo.md](Todo.md)
