# :book: Borrowable Limit Order Book - VERSIONING

## What's new in V0.1

- handle fixed point variables with WAD = 1e18 scaling
- add _reduceUserBorrow() and closePosition()
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
