// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

/// @title A lending order book for ERC20 tokens (V1.0)
/// @author Pré-vert
/// @notice Allows users to place limit orders, take orders, and borrow quote assets
/// @dev A money market for the pair base/quote is handled by a single contract
/// which manages both order book and lending/borrowing operations

import {IERC20} from "../lib/openZeppelin/IERC20.sol";
import {SafeERC20} from "../lib/openZeppelin/SafeERC20.sol";
import {IBook} from "./interfaces/IBook.sol";
import {MathLib, WAD} from "../lib/MathLib.sol";
import {console} from "forge-std/Test.sol";

contract Book is IBook {
    using MathLib for uint256;
    using SafeERC20 for IERC20;

    /// @notice the contract has 8 external functions:
    /// - deposit: deposit assets in pool in base or quote tokens
    /// - withdraw: remove assets from pool in base or quote tokens
    /// - borrow: borrow quote tokens from buy order pools
    /// - repay: pay back borrow in buy order pools
    /// - take: allow users to fill limit orders at limit price when profitable, may liquidate positions along the way
    /// - changeLimitPrice: allow user to change order's limit price
    /// - changePairedPrice: allow user to change order's paired limit price
    /// - liquidateBorrower: allow users to liquidate borrowers close to undercollateralization
    
    IERC20 public quoteToken;
    IERC20 public baseToken;

    // *** CONSTANTS *** //

    // How many orders a user can place in different pools
    uint256 constant public MAX_ORDERS = 5;

    // How many positions a user can open in different pools
    uint256 constant public MAX_POSITIONS = 5; 

    // Minimum liquidation rounds
    uint256 constant public MIN_ROUNDS = 5;

    // Minimum deposited base tokens
    uint256 constant public MIN_DEPOSIT_BASE = 2 * WAD;

    // Minimum deposited quote tokens
    uint256 constant public MIN_DEPOSIT_QUOTE = 100 * WAD;

    // Price step for placing orders: +/- 10%
    uint256 constant public PRICE_STEP = 11 * WAD / 10;

    // id for non existing order or position in arrays
    uint256 constant private ABSENT = type(uint256).max;

    // applies to token type (ease reading in function attributes)
    bool constant private IN_QUOTE = true; 

    // // applies to position (true) or order (false) (ease reading in function attributes)
    // bool constant private TO_POSITION = true;

    // round up in conversions
    bool constant private ROUNDUP = true; 

    // IRM parameter = 0.005
    uint256 public constant ALPHA = 5 * WAD / 1000;

    // IRM parameter = 0.015
    uint256 public constant BETA = 15 * WAD / 1000;

    // uint256 public constant GAMMA = 10 * WAD / 1000; // IRM parameter =  0.01

    // max LTV = 99%
    uint256 public constant MAX_LTV = 99 * WAD / 100;

    // interest-based liquidation penalty for maker =  0.05 ((%)
    uint256 public constant PENALTY = 5 * WAD / 100;

    // number of seconds in one year
    uint256 public constant YEAR = 365 days;

    // how negative uint256 following substraction are handled
    bool private constant RECOVER = true;

    // pool's type of asset
    enum PoolIn {quote, base, none}

    // *** STRUCT VARIABLES *** //

    struct Pool {

        // index => order id in pool
        mapping(uint256 => uint256) orderIds;

        // index => position id in pool
        mapping(uint256 => uint256) positionIds;

        // total assets deposited in pool
        uint256 deposits;

        // total assets borrowed from pool
        uint256 borrows;

        // ** interest rate model ** //

        // # of periods since last time instant interest rate has been updated in pool
        uint256 lastTimeStamp;

        // time-weighted average interest rate since inception of pool, applied to borrows
        uint256 timeWeightedRate;

        // time-weighted and UR-weighted average interest rate since inception of pool, applied to deposits
        uint256 timeUrWeightedRate;

        // ** queue management variables ** //

        // row index of orderId on top of orderIds mapping to add order id; starts at 0
        uint256 topOrder;

        // row index of last orderId deleted from orderIds mapping; starts at 0
        uint256 bottomOrder;

        // row index of positionId on the top of positionIds mapping to add position id; starts at 0
        uint256 topPosition;

        // row index of last positionId deleted from positionIds mapping; starts at 0
        uint256 bottomPosition;
    }
    
    // orders and borrows by users
    struct User {

        // orders id in mapping orders
        uint256[MAX_ORDERS] depositIds;

        // positions id in mapping positions, only in quote tokens
        uint256[MAX_POSITIONS] borrowIds;
    }
    
    struct Order {
        
        // pool id of order
        int24 poolId;

        // address of maker
        address maker;

        // pool id of paired order
        int24 pairedPoolId;

        // assets deposited (quote tokens for buy orders, base tokens for sell orders)
        uint256 quantity;

        // time-weighted and UR-weighted average interest rate for supply since initial deposit
        uint256 orderWeightedRate;

        // buy orders or sell orders
        bool isBuyOrder;
    }

    // borrowing positions
    struct Position {

        // pool id in mapping orders, from which assets are borrowed
        int24 poolId;

        // address of borrower
        address borrower;

        // quantity of quote assets borrowed
        uint256 borrowedAssets;

        // time-weighted average interest rate for position since its creation
        uint256 positionWeightedRate;
    }

    // *** MAPPINGS *** //

    // int24: integers between -8,388,608 and 8,388,607
    mapping(int24 poolId => Pool) internal pools;

    mapping(int24 poolId => uint256) internal limitPrice; 

    mapping(uint256 orderId => Order) internal orders;

    mapping(address user => User) internal users;

    mapping(uint256 positionId => Position) internal positions;

    // *** VARIABLES *** //

    uint256 private lastOrderId = 1; // initial order id (0 for non existing orders)
    uint256 private lastPositionId = 1; // initial position id (0 for non existing positions)
    uint256 public priceFeed;
 
    constructor(address _quoteToken, address _baseToken, uint256 _startingLimitPrice) {
        quoteToken = IERC20(_quoteToken);
        baseToken = IERC20(_baseToken);
        limitPrice[0] = _startingLimitPrice; // initial limit price for the first pool
    }

    modifier poolHasAssets(int24 _poolId) {
        require(_poolHasAssets(_poolId), "Pool has no orders");
        _;
    }

    modifier moreThanZero(uint256 _var) {
        require(_var > 0, "Must be positive");
        _;
    }

    /// @inheritdoc IBook

    function deposit(
        int24 _poolId,
        uint256 _quantity,
        int24 _pairedPoolId,
        bool _isBuyOrder
    )
        external
        moreThanZero(_quantity)
    {
        // A minimal quantity must be deposited
        require(_quantity >= minDeposit(_isBuyOrder), "Not enough deposited");
        
        // in quote or base tokens, or none if pool empty
        PoolIn poolType = _poolType(_poolId);

        // asset deposited must not be profitable to take (profitable: ongoing liquidation)
        require(!_profitable(_poolId), "Price at loss");
        
        // asset deposited must be of same type as pool's type, or pool must be empty
        require(_sameType(_isBuyOrder, poolType), "Type mismatch");

        // limit price and paired limit price are in right order
        require(_consistent(_poolId, _pairedPoolId, _isBuyOrder), "Inconsistent limit prices");

        // _poolId or _pairedPoolId have a price or are adjacent to a pool id with a price        
        require(_nearBy(_poolId), "Limit price too far");
        require(_nearBy(_pairedPoolId), "Paired price too far");
        
        // in buy order (borrowable) market, update pool's total borrow and total deposits
        // increment TWIR and TUWIR before accounting for changes in UR and future interest rate
        if (_isBuyOrder) _updateAggregates(_poolId);

        // return order id if maker already supplies in pool, even with zero quantity, if not return zero
        uint256 orderId_ = _getOrderIdInDepositIdsInUsers(msg.sender, _poolId, _isBuyOrder);

        // if new order:
        // add new orderId in depositIds[] in users
        // add new orderId on top of orderIds[] in pool
        // increment topOrder
        // return new order id
        if (orderId_ == 0) orderId_ = _createOrder(_poolId, msg.sender, _pairedPoolId, _quantity, _isBuyOrder);
        
        // if existing order:
        else {
            // if buy order market, add interest rate to existing borrowable deposit
            // update TUWIR_t to TUWIR_T to reset interest rate to zero
            if (_isBuyOrder) _addInterestRateToDeposit(orderId_);

            // add new quantity to existing deposit
            orders[orderId_].quantity += _quantity;
        }

        // add new quantity to total deposits in pool (double check asset type before)
        pools[_poolId].deposits += _quantity;

        _transferFrom(msg.sender, _quantity, _isBuyOrder);

        emit Deposit(msg.sender, _poolId, orderId_, _quantity, _pairedPoolId, _isBuyOrder);
    }

    /// @inheritdoc IBook

    function withdraw(
        uint256 _orderId,
        uint256 _removedQuantity
    )
        external
        moreThanZero(_removedQuantity)
    {
        Order memory order = orders[_orderId];

        // order must have funds from start
        require(order.quantity > 0, "No order");

        // if withdraw quote (borrowable) tokens, check if pool has enough available liquidity

        if (order.isBuyOrder) {
        
            // update pool's total borrow, total deposits
            // increment TWIR/TUWIR before calculating pool's availale assets
            _updateAggregates(order.poolId);

            // withdraw no more than available assets in pool
            require(_removedQuantity <= _poolAvailableAssets(order.poolId), "Remove too much_2");

            // add interest rate to existing deposit
            // reset deposit's interest rate to zero
            // updates how much assets can be withdrawn (used in _removable() infra)
            _addInterestRateToDeposit(_orderId);
        }

        // if withdraw base (collateral) tokens,
        // check that withdrawal does not undercollateralize maker's positions

        else
        {
            // update borrower's positions with accrued interest rate in all pools in which he borrows
            // updates borrower's required collateral and excess collateral
            _addInterestRateToUserPositions(msg.sender);

            // excess collateral must remain positive after removal
            require(positiveExcessCollateral(msg.sender, _removedQuantity), "Remove too much_3");
        }

        // withdraw no more than deposit net of min deposit if partial
        require(_removable(_orderId, _removedQuantity), "Remove too much_1");

        // reduce quantity in order, possibly to zero
        orders[_orderId].quantity -= _removedQuantity;

        // reduce total deposits in pool
        pools[order.poolId].deposits -= _removedQuantity;

        _transferTo(msg.sender, _removedQuantity, order.isBuyOrder);

        emit Withdraw(_orderId, _removedQuantity);
    }

    /// @inheritdoc IBook

    function borrow(
        int24 _poolId,
        uint256 _quantity
    )
        external
        moreThanZero(_quantity)
        poolHasAssets(_poolId)
    {
        // pool's asset type, revert if no assets
        bool inQuote = _isQuote(_poolType(_poolId));

        // only quote tokens can be borrowed
        require(inQuote, "Cannot borrow_01");
        
        // pool is not profitable to take (no liquidation is ongoing)
        // otherwise users could arbitrage the protocol by depositing cheap assets and borrowing more valuable assets
        require(!_profitable(_poolId) , "Cannot borrow_02");

        // increment TWIR/TUWIR before calculation of pool's available assets
        // update pool's total borrow, total deposits
        _updateAggregates(_poolId);

        // cannot borrow more than available assets in pool
        require(_quantity <= _poolAvailableAssets(_poolId), "Borrow too much_1");

        // update borrower's positions with accrued interest rate in all pools in which he borrows
        // updates borrower's required collateral and excess collateral
        _addInterestRateToUserPositions(msg.sender);

        // required collateral (in base tokens) to borrow _quantity i(n quote tokens)
        uint256 requiredCollateral = _convert(_quantity, limitPrice[_poolId], inQuote, ROUNDUP);

        // check borrowed amount is collateralized enough by borrower's own orders
        require(positiveExcessCollateral(msg.sender, requiredCollateral), "Borrow too much_2");

        // find if borrower has already a position in pool
        uint256 positionId_ = getPositionId(msg.sender, _poolId);

        // if position already exists
        if (positionId_ != 0) {

            // add interest rate to borrowed quantity and reset interest rate to zero
            _addInterestRateToPosition(positionId_);

            // add additional borrow to borrowed quantity
            positions[positionId_].borrowedAssets += _quantity;
        }

        // if position is new, create
        // add position id to borrowIds[] in user
        // add position id to positionIds[] in pool
        // revert if max positions reached
        // returns id of new position or updated existing one

        else positionId_ = _createPosition(_poolId, msg.sender, _quantity);

        // add _quantity to pool's total borrow
        pools[_poolId].borrows += _quantity;

        _transferTo(msg.sender, _quantity, inQuote);

        emit Borrow(msg.sender, _poolId, positionId_, _quantity, inQuote);
    }

    /// @inheritdoc IBook

    function repay(
        uint256 _positionId,
        uint256 _quantity
    )
        external
        moreThanZero(_quantity)
    {
        Position memory position = positions[_positionId];

        // repay must be in quote tokens
        require(_isQuote(_poolType(position.poolId)), "Non borrowable pool");

        // user is borrower from start
        require(position.borrowedAssets > 0, "No active position");

        // update pool's total borrow and total deposits
        // increment time-weighted rates with IR based on UR before repay
        _updateAggregates(position.poolId);

        // add interest rate to borrowed quantity
        // reset interest rate to zero
        _addInterestRateToPosition(_positionId);

        // cannot repay more than borrowed assets
        require(_quantity <= position.borrowedAssets, "Repay too much");

        // decrease borrowed assets in position, possibly to zero
        positions[_positionId].borrowedAssets -= _quantity;

        // decrease borrowed assets in pool's total borrow (check no asset mismatch)
        pools[position.poolId].borrows -= _quantity;

        _transferFrom(msg.sender, _quantity, IN_QUOTE);
        
        emit Repay(_positionId, _quantity);
    }

    /// @inheritdoc IBook

    // take()
    // _updateAggregates()               | update pool's total borrow and total deposits with interest rate
    //  ├── Take quote tokens            | if take borrowable quote tokens
    //  │   ├── _liquidatePositions()    | liquidate positions one after one
    //  │   |   ├── _closePosition()     | liquidate one position
    //  │   |   └── _seizeCollateral()   | seize collateral for the exact amount liquidated
    //  │   └── _closeOrders()           | close orders for amount of base assets received from taker and liquidated borrowers
    //  │       └── _repostLiquidity()   | repost base tokens received by lenders in sell orders
    //  ├── Take base tokens             | if take collateral base tokens
    //  │   └── _takeOrders()            | take orders one after one
    //  │       ├── _reduceUserDebt()    | if order is collateral, repay debt with quote tokens received from taker
    //  │       └── _repostLiquidity()   | repost quote tokens received by lenders in buy order
    //  ├── _transferFrom()              | transfer base or quote tokens from taker to contract
    //  └── _transferTo()                | transfer  tokens of opposit teype from contract to taker

    function take(
        int24 _poolId,
        uint256 _takenQuantity
    )
        external
        poolHasAssets(_poolId)
    {
        // pool's asset type, revert if no assets
        bool inQuote = _isQuote(_poolType(_poolId));
        Pool storage pool = pools[_poolId];
        
        // taking is allowed for profitable trades only
        require(_profitable(_poolId), "Trade not profitable");

        // if buy order market, update pool's total borrow and total deposits with interest rate
        if (inQuote) _updateAggregates(_poolId);

        // cannot take more than pool's available assets
        require(_takenQuantity <= pool.deposits - pool.borrows, "Too much taken");

        // assets actually taken at the end
        uint256 takenAssets;

        // Quote tokens: can be borrowed but cannot serve as collateral
        if (inQuote) {

            // pool's utilization rate (before debts cancelation)
            uint256 utilizationRate = getUtilizationRate(_poolId);

            // nothing to take if 100 % utilization rate
            require (utilizationRate < 1 * WAD, "Nothing to take");
            
            // min canceled debt is scaled by taken quantity * UR / (1-UR), which can be zero if UR = 0
            // _takenQuantity: quote assets received by taker, used to calculate the amount of liquidated quote assets
            // higher UR, higher liquidated quote assets per unit of taken assets

            uint256 minCanceledDebt = _takenQuantity.mulDivDown(utilizationRate, WAD - utilizationRate);

            // then, liquidate positions:
            // - delete borrow
            // - seize borrower's collateral
            //  until:
            // - MIN_ROUNDS positions have been liquidated, and min canceled debt is reached
            // - or no more position to liquidate
            // returns total liquidated assets (quote tokens)

            uint256 liquidatedQuotes = 0;
            
            if (minCanceledDebt > 0) liquidatedQuotes = _liquidatePositions(_poolId, minCanceledDebt);

            // for every closed order with quote tokens:
            // - set deposits to zero
            // - repost assets in a sell order
            // until exact amount of liquidated quote assets and taken quote quantity is reached

            uint256 closedAmount = _closeOrders(_poolId, _takenQuantity + liquidatedQuotes);

            // if _takenQuantity has been set to high, closedAmount < _takenQuantity + liquidatedQuotes 

            takenAssets = _substract(closedAmount, liquidatedQuotes, "err 01", !RECOVER);
        }

        // Base tokens can serve as collateral but cannot be borrowed
        else {

            require(_takenQuantity > 0, "Must be positive");
            
            // take sell orders and, if collateral, close maker's positions in quote tokens
            // repost remaining assets in a buy order

            takenAssets = _takeOrders(_poolId, _takenQuantity);
        }

        uint256 receivedAssets = _convert(takenAssets, limitPrice[_poolId], inQuote, !ROUNDUP);

        _transferFrom(msg.sender, receivedAssets, !inQuote);
        
        _transferTo(msg.sender, takenAssets, inQuote);
        
        emit Take(msg.sender, _poolId, _takenQuantity, inQuote);
    }

    /// @inheritdoc IBook

    function liquidateBorrower(
        address _borrower,
        uint256 _suppliedQuotes
    )
        external
    {
        // update borrower's positions with accrued interest rate in all pools in which he borrows
        // updates borrower's required collateral and excess collateral
        _addInterestRateToUserPositions(_borrower);
        
        // borrower's excess collateral must be negative
        require(!positiveExcessCollateral(msg.sender, 0), "Positive net wealth");

        // reduce user's borrowing positions possibly as high as _suppliedQuotes
        uint256 reducedDebt = _reduceUserDebt(_borrower, _suppliedQuotes);

        // the lower exchange rate ETH/USDC: p* = p/(1+penalty), the higher liqidator receives against USDC
        uint256 exchangeRate = WAD.mulDivDown(priceFeed, WAD + PENALTY); 

        // liquidator provides X USDC and receives X/p* ETH
        uint256 amountToSeize = _convert(reducedDebt, exchangeRate, IN_QUOTE, !ROUNDUP);

        // return borrower's collateral actually seized, which is at most amountToSeize
        uint256 seizedCollateral = _seizeCollateral(_borrower, amountToSeize);

        _transferFrom(msg.sender, reducedDebt, IN_QUOTE);
        
        _transferTo(msg.sender, seizedCollateral, !IN_QUOTE);

        emit LiquidateBorrower(msg.sender, reducedDebt);
    }

    /// @inheritdoc IBook

    function changeLimitPrice(
        uint256 _orderId,
        int24 _newPoolId
    )
        external
    {
        Order memory order = orders[_orderId];

        // reverts if position is not found
        require(order.quantity > 0, "No order");

        // revert if new limit price and paired limit price in wrong order
        require(_consistent(_newPoolId, order.pairedPoolId, order.isBuyOrder), "Inconsistent limit prices");

        require(!_profitable(_newPoolId), "New price at loss");

        // asset type of new pool must be the same as asset type of previous pool, or of no type if empty
        require(_sameType(order.isBuyOrder, _poolType(_newPoolId)), "asset type mismatch_2");
        
        // newPoolId must have a price or be adjacent to a pool id with a price        
        require(_nearBy(_newPoolId), "New price too far");

        orders[_orderId].poolId = _newPoolId;

        emit ChangeLimitPrice(_orderId, _newPoolId);
    }

    /// @inheritdoc IBook
    function changePairedPrice(
        uint256 _orderId,
        int24 _newPairedPoolId
    )
        external
    {
        Order memory order = orders[_orderId];

        // reverts if position is not found
        require(order.quantity > 0, "No order");

        // revert if new limit price and paired limit price are in wrong order
        require(_consistent(order.poolId, _newPairedPoolId, order.isBuyOrder), "Inconsistent limit prices");
        
        // newPoolId must have a price or be adjacent to a pool id with a price        
        require(_nearBy(_newPairedPoolId), "New price too far");

        orders[_orderId].pairedPoolId = _newPairedPoolId;
        
        emit ChangeLimitPrice(_orderId, _newPairedPoolId);
    }


    ///////******* Internal functions *******///////
    
    // create new order and return order id
    // add new orderId in depositIds[] in users
    // add new orderId on top of orderIds[] in pool
    
    function _createOrder(
        int24 _poolId,
        address _maker,
        int24 _pairedPoolId,
        uint256 _quantity,
        bool _isBuyOrder
    )
        internal
        returns (uint256 newOrderId_)
    {
        uint256 orderWeightedRate = 1 * WAD;
        if (_isBuyOrder) orderWeightedRate = pools[_poolId].timeUrWeightedRate;
        
        // create new order in orders
        Order memory newOrder = Order(
            _poolId,
            _maker,
            _pairedPoolId,
            _quantity,
            orderWeightedRate,
            _isBuyOrder
        );
        newOrderId_ = lastOrderId;
        orders[newOrderId_] = newOrder;
        lastOrderId ++;

        // add new orderId in depositIds[] in users
        // revert if max orders reached
        _insertOrderIdInDepositIdsInUser(_maker, newOrderId_);

        // add new orderId on top of orderIds[] in pool
        // increment topOrder
        _addOrderIdToOrderIdsInPool(_poolId, newOrderId_);
    }

    // liquidate positions and seize collateral until minimum total liquidated assets are reached
    // min canceled debt: how much to at least liquidate
    
    function _liquidatePositions(
        int24 _poolId,
        uint256 _minCanceledDebt
    )
        internal
        returns (uint256 liquidatedQuoteAssets_)
    {
        Pool storage pool = pools[_poolId];
        
        // cumulated liquidated quote assets
        liquidatedQuoteAssets_ = 0;

        // number of liquidation iterations
        uint256 rounds = 0;
        
        //*** iterate on position id in pool's positionIds from bottom to top ***//
        
        // pool.topPosition is first available slot for positions in pool's positionIds
        // pool.bottomPosition is first possible slot for positions to be liquidated
        // pool.bottomPosition == pool.topPosition means that there is noting more to liquidate
        // Example: a first borrow is recorded at topPosition = 0; topPosition is incremented to 1
        // In a liquidation event, bottomPosition starts at 0 < 1, finds a position to close
        // then increments to 1 and stops as 1 == 1
        
        for (uint256 row = pool.bottomPosition; row < pool.topPosition; row++) {

            // which position in pool is closed
            uint256 positionId = pool.positionIds[row];

            // check user has still borrowed assets in pool
            if (positions[positionId].borrowedAssets == 0) continue;

            rounds ++;

            // close position: cancel full debt and seize collateral
            uint256 liquidatedAssets = _closePosition(positionId);

            uint256 collateralToSeize = _convert(liquidatedAssets, limitPrice[_poolId], IN_QUOTE, ROUNDUP);

            // seize collateral in borrower's collateral orders for exact amount  collateralToSeize

            _seizeCollateral(positions[positionId].borrower, collateralToSeize);

            // add liquidated assets to cumulated liquidated assets
            liquidatedQuoteAssets_ += liquidatedAssets;

            // if enough assets are liquidated by taker (given take's size), stop
            // can liquidate more than strictly necessary
            if (rounds > MIN_ROUNDS && liquidatedQuoteAssets_ >= _minCanceledDebt) break;
        }

        // update pool's bottom position (first row at which a position potentially exists)
        pool.bottomPosition += rounds;
    }

    // cancel full debt of one position
    // seize collateral assets for the exact amount
    // return liquidated assets
    
    function _closePosition(uint256 positionId)
        internal
        returns (uint256 liquidatedAssets_)
    {
        int24 poolId = positions[positionId].poolId;
        
        // add interest rate to borrowed quantity
        // update TWIR_t to TWIR_T to reset interest rate to zero
        _addInterestRateToPosition(positionId);

        liquidatedAssets_ = positions[positionId].borrowedAssets;

        // decrease borrowed assets in pool's total borrow (check no asset mismatch)
        pools[poolId].borrows -= liquidatedAssets_;

        // decrease borrowed assets to zero
        positions[positionId].borrowedAssets = 0;
    }

    // close deposits for exact amount of liquidated quote assets and taken quote quantity
    
    function _closeOrders(
        int24 _poolId,
        uint256 _amountToClose
    )
        internal
        returns (uint256 closedAmount)    
    {
        Pool storage pool = pools[_poolId];
        
        // remaining (quote) assets to redeem against canceled debt
        uint256 remainingToClose = _amountToClose;

        // number of closing iterations
        uint256 closingRound = 0;

        // iterate on order id in pool's orderIds from bottom to top
        // pool.topOrder is first available slot for orders in pool's orderIds
        // pool.bottomOrder is first possible slot for orders to be seized
        // pool.bottomOrder == pool.topOrder means that there is noting more to seize

        for (uint256 row = pool.bottomOrder; row < pool.topOrder; row++) {

            closingRound ++;
            
            // which order in pool is closed
            uint256 orderId = pool.orderIds[row];

            uint256 orderSize = orders[orderId].quantity;

            // if user has no deposits in pool, skip
            if (orderSize == 0) continue;

            // add interest rate to deposit
            // update TUWIR_t to TUWIR_T to reset interest rate to zero
            _addInterestRateToDeposit(orderId);

            // collect assets from deposit against debt deletion or taker's demand
            
            // if deposit exceeds remaining to close, some assets will remain in deposit
            // otherwise, deposit' assets are fully depleted

            uint256 closed = remainingToClose.minimum(orderSize);

            remainingToClose -= closed;

            // decrease pool's total deposits (check no asset mismatch)
            pools[_poolId].deposits -= closed;

            // decrease assets in order, possibly down to zero
            orders[orderId].quantity -= closed;

            // base assets received by maker
            uint256 makerReceivedAssets = _convert(closedAmount, limitPrice[_poolId], IN_QUOTE, !ROUNDUP);
        
            // Place base assets in a sell order on behalf of maker
            _repostLiquidity(orders[orderId].maker, _poolId, orderId, makerReceivedAssets, !IN_QUOTE);

            // exit iteration on orders if all debt has been redeemed and take size is fully filled
            if (remainingToClose == 0) break;
        }

        // update pool's bottom order (first row at which an order potentially exists)
        pool.bottomOrder += closingRound - 1;

        return closedAmount = _amountToClose - remainingToClose;
    }

    // when a limit pool in base tokens is taken, orders are taken in batches
    // for every taken order, close as much borrowing positions as taken assets if order serves as collateral
    
    function _takeOrders(
        int24 _poolId,
        uint256 _takenQuantity
    )
        internal
        returns (uint256 totalTaken_)
    {
        // remaining base assets to take until exact amount of reduced deposits is reached
        uint256 remainingAssets = _takenQuantity;

        // number of closing iterations
        uint256 closingRound = 0;

        // iterate on order id in pool's orderIds from bottom to top

        for (uint256 row = pools[_poolId].bottomOrder; row < pools[_poolId].topOrder; row++) {

            closingRound ++;
            
            // which sell order in pool is closed
            uint256 orderId = pools[_poolId].orderIds[row];

            uint256 orderSize = orders[orderId].quantity;

            // check user has still deposits in pool
            if (orderSize == 0) continue;

            uint256 takable = remainingAssets.minimum(orderSize);

            remainingAssets -= takable;

            // decrease pool's total deposits (check no asset mismatch)
            pools[_poolId].deposits -= takable;

            // decrease assets in order, possibly down to zero
            orders[orderId].quantity -= takable;

            // quote assets received by maker before debt repayment
            uint256 makerReceivedAssets = _convert(takable, limitPrice[_poolId], !IN_QUOTE, !ROUNDUP);
            
            // when a sell order is taken, the quote assets received serve in priority to pay back maker's own borrow
            
            // reduce user's borrowing positions possibly as high as makerReceivedAssets
            uint256 repaidDebt = _reduceUserDebt(orders[orderId].maker, makerReceivedAssets);

            // quote assets kept by maker after debt repayment
            uint256 remainingMakerAssets = makerReceivedAssets - repaidDebt;

            // place quote assets in a buy order on behalf of maker
            _repostLiquidity(orders[orderId].maker, _poolId, orderId, remainingMakerAssets, IN_QUOTE);

            // exit iteration if take size is fully filled
            if (remainingAssets == 0) break;
        }

        // update pool's bottom order (first row at which an order potentially exists)
        pools[_poolId].bottomPosition += closingRound - 1;

        totalTaken_ = _takenQuantity - remainingAssets;
    }

    // Place assets in another order the other side of the book
    // _quantity: amount reposted in destination order
    // _poolId: origin pool before replacement
    // _orderId: origin order before replacement
    // _isBuyOrder: asset type of _quantity
    
    function _repostLiquidity(
        address _user,
        int24 _poolId,
        uint256 _orderId,
        uint256 _quantity,
        bool _isBuyOrder
    )
        internal
    {
        // in buy order (borrowable) market, update pool's total borrow and total deposits
        // increment TWIR and TUWIR before accounting for changes in UR and future interest rate
        if (_isBuyOrder) _updateAggregates(_poolId);
        
        // check if an identical order exists on the other side of the book
        // if so increase deposit, else create
        // pairedPoolId: paired pool with sell orders, higher pool id and higher price

        uint256 pairedOrderId_ = _getOrderIdInDepositIdsInUsers(
            _user,
            orders[_orderId].pairedPoolId,
            _isBuyOrder
        );

        // if new, create sell order

        if (pairedOrderId_ == 0) {

            int24 newPoolId = _isBuyOrder? _poolId + 1 : _poolId - 1;
        
            // add new orderId in depositIds[] in users
            // add new orderId on top of orderIds[] in pool
            // increment topOrder
            // return new order id

            pairedOrderId_ = _createOrder(
                newPoolId,
                _user,
                _poolId,
                _quantity,
                _isBuyOrder
            );
        }
        
        // if order exists (even with zero quantity):
        else {

            // if buy order market, add interest rate to existing borrowable deposit
            // update TUWIR_t to TUWIR_T to reset interest rate to zero
            if (_isBuyOrder) _addInterestRateToDeposit(pairedOrderId_);
            
            // add new quantity to existing deposit
            orders[pairedOrderId_].quantity += _quantity;
        }

        // increase pool's total deposits (double check asset type before)
        pools[orders[pairedOrderId_].poolId].deposits += _quantity;
    }
    
    // When a buy order is taken, all positions which borrow from it are closed
    // For every closed position, an exact amount of collateral must be seized
    // As multiple sell orders may collateralize a closed position:
    //  - iterate on collateral orders by borrower
    //  - seize collateral orders as they come, stop when borrower's debt is fully canceled
    //  - change internal balances
    // ex: Bob deposits 1 ETH in two sell orders to borrow 4000 from Alice's buy order (p = 2000)
    // Alice's buy order is taken => seized Bob's collateral is 4000/p = 2 ETH spread over 2 orders
    // interest rate has been added to position before callling _seizeCollateral
    // returns seized collateral in base tokens which is normally equal to collateral to seize

    function _seizeCollateral(
        address _borrower,
        uint256 _amountToSeize
    )
        internal
        returns (uint256 seizedAmount_)
    {
        uint256 remainingToSeize = _amountToSeize;

        uint256[MAX_ORDERS] memory depositIds = users[_borrower].depositIds;

        for (uint256 j = 0; j < MAX_ORDERS; j++) {

            uint256 orderId = depositIds[j];

            if (
                orders[orderId].quantity > 0 &&
                orders[orderId].isBuyOrder == !IN_QUOTE
            )
            {
                uint256 seizedCollateral = remainingToSeize.minimum(orders[orderId].quantity);
                orders[orderId].quantity -= seizedCollateral;
                remainingToSeize -= seizedCollateral;
                pools[orders[orderId].poolId].deposits -= seizedCollateral;
            }
            if (remainingToSeize == 0) break;
        }

        return seizedAmount_ = _amountToSeize - remainingToSeize;
    }

    
    // reduce user's borrowing positions possibly as high as _maxReduce
    // - iterate on maker's borrowing positions
    // - close positions as they come
    // - stop when all positions have been closed or _maxReduced is reached
    // - change internal balances in quote tokens
    // return total amount of reduced debt <= _maxReduce
    
    function _reduceUserDebt(
        address _borrower,
        uint256 _maxReduce
    )
        internal
        returns (uint256 reducedUserDebt_)
    {
        uint256 remainingToReduce = _maxReduce;

        uint256[MAX_POSITIONS] memory borrowIds = users[_borrower].borrowIds;

        // iterate on position ids, pay back position one by one
        for (uint256 i = 0; i < MAX_POSITIONS; i++) {

            Position memory position = positions[borrowIds[i]];

            if (position.borrowedAssets > 0)
            {
                // update pool's total borrow and total deposits with interest rate
                _updateAggregates(position.poolId);

                // add interest rate to borrowed quantity
                // update TWIR_t to TWIR_T to reset interest rate to zero
                _addInterestRateToPosition(borrowIds[i]);
                
                // debt repaid = min(remaining to reduce, assets in position)
                uint256 reducedDebt = remainingToReduce.minimum(position.borrowedAssets);

                // revise remaining cash down, possibly to zero
                remainingToReduce -= reducedDebt;

                // decrease borrowed assets in position, possibly to zero
                positions[borrowIds[i]].borrowedAssets -= reducedDebt;

                // decrease borrowed assets in pool
                pools[position.poolId].borrows -= reducedDebt;
            }

            if (remainingToReduce == 0) break;
        }
        reducedUserDebt_ = _maxReduce - remainingToReduce;
    }

    // tranfer ERC20 from contract to user/taker/borrower
    function _transferTo(
        address _to,
        uint256 _quantity,
        bool _isBuyOrder
    )
        internal
        moreThanZero(_quantity)
    {
        if (_isBuyOrder) quoteToken.safeTransfer(_to, _quantity);
        else baseToken.safeTransfer(_to, _quantity);
    }
    
    // transfer ERC20 from user/taker/repayBorrower to contract

    function _transferFrom(
        address _from,
        uint256 _quantity,
        bool _inQuote
    )
        internal
        moreThanZero(_quantity)
    {
        if (_inQuote) quoteToken.safeTransferFrom(_from, address(this), _quantity);
        else baseToken.safeTransferFrom(_from, address(this), _quantity);
    }

    // add new orderId in depositIds[] in users 
    // revert if max orders reached

    function _insertOrderIdInDepositIdsInUser(
        address _user,
        uint256 _orderId
    )
        internal
    {
        bool fillRow = false;
        
        for (uint256 i = 0; i < MAX_ORDERS; i++) {

            uint256 orderId = users[_user].depositIds[i];

            if (orders[orderId].quantity == 0) {
                users[_user].depositIds[i] = _orderId;
                fillRow = true;
                break;
            }
        }
        if (!fillRow) revert("Max orders reached");
    }

    // add position id in borrowIds[] in mapping users
    // reverts if user's max number of positions reached

    function _insertPositionIdInBorrowIdsInUser(
        address _borrower,
        uint256 _positionId
    )
        internal
    {
        bool fillRow = false;

        for (uint256 i = 0; i < MAX_POSITIONS; i++)
        {
            uint256 positionId = users[_borrower].borrowIds[i];

            if (positions[positionId].borrowedAssets == 0)
            {
                users[_borrower].borrowIds[i] = _positionId;
                fillRow = true;
                break;
            }
        }
        if (!fillRow) revert("Max positions reached");
    }

    // add order id on top of orderIds in pool
    // make sure order id does not already exist in ordersIds

    function _addOrderIdToOrderIdsInPool(
        int24 _poolId,
        uint256 _orderId
    )
        internal
    {
        pools[_poolId].orderIds[pools[_poolId].topOrder] = _orderId;
        pools[_poolId].topOrder ++;
    }

    // add position id to borrowIds[] in users
    // add position id to borrows[] in pools
    // returns existing or new position id
    // revert if max position
    // _poolId: pool id from which assets are borrowed
    
    function _createPosition(
        int24 _poolId,
        address _borrower,
        uint256 _quantity
    )
        internal
        returns (uint256 newPositionId_)
    {
        uint256 subWeightedRate = 1;

        if (_isQuote(_poolType(_poolId))) subWeightedRate = pools[_poolId].timeWeightedRate;
        
        // create position in positions, return new position id
        Position memory newPosition = Position(
            _poolId,
            _borrower,
            _quantity,
            subWeightedRate // initialize interest rate
        );

        newPositionId_ = lastPositionId;
        positions[newPositionId_] = newPosition;
        lastPositionId++;

        // add new position id to borrowIds[] in users, 
        // revert if user has too many open positions (max position reached)
        _insertPositionIdInBorrowIdsInUser(msg.sender, newPositionId_);

        // add new position id on top of positionIds[] in pool
        // make sure position id does not already exist in positionIds
        pools[_poolId].positionIds[pools[_poolId].topPosition] = newPositionId_;
        pools[_poolId].topPosition ++;
    }

    function _substract(
        uint256 _a,
        uint256 _b,
        string memory _errCode,
        bool _recover
    )
        internal view
        returns (uint256)
    {
        if (_a >= _b) {return _a - _b;}
        else {
            if (_recover) {
                console.log("Error code: ", _errCode); 
                return 0;
            }
            else {revert(_errCode);}
        }
    }

    // update pool's total borrow and total deposits
    // increment TWIR and TUWIR

    function _updateAggregates(int24 _poolId)
        internal
    {
        // compute n_t - n_{t-1} elapsed time since last change
        uint256 elapsedTime = block.timestamp - pools[_poolId].lastTimeStamp;
        if (elapsedTime == 0) return;

        // compute (n_t - n_{t-1}) * IR_{t-1} / N
        // IR_{t-1} annual interest rate
        // N number of seconds in a year, elapsed in seconds (intergers)
        // and IR_{t-1} / N instant rate
        uint256 borrowRate = elapsedTime * getInstantRate(_poolId);

        // add IR_{t-1} (n_t - n_{t-1})/N to TWIR_{t-2} in pool
        // => get TWIR_{t-1} the time-weighted interest rate from inception to present (in WAD)
        // TWIR_{t-2} = IR_0 n_1/N + IR_1 (n_2 - n_1)/N + ... + IR_{t-1} (n_{t-2} - n_{t-1})/N
        // TWIR_{t-1} = IR_0 n_1/N + IR_1 (n_2 - n_1)/N + ... + IR_{t-1} (n_{t-2} - n_{t-1})/N + (n_t - n_{t-1})/N
        // pool can be either in quote or base tokens, depending on market price
        pools[_poolId].timeWeightedRate += borrowRate;

        // add interest rate exp[ (n_t - n_{t-1}) * IR_{t-1} / N ] - 1 to total borrow in pool
        pools[_poolId].borrows += borrowRate.wTaylorCompoundedUp().wMulDown(pools[_poolId].borrows);

        // deposit interest rate is borrow rate scaled scaled down by UR
        uint256 depositRate = borrowRate.mulDivDown(WAD, getUtilizationRate(_poolId));

        // add interest rate to time- and UR-weighted interest rate
        pools[_poolId].timeUrWeightedRate += depositRate;

        // add interest rate to total deposits in pool
        pools[_poolId].deposits += depositRate.wTaylorCompoundedDown().wMulDown(pools[_poolId].deposits);

        pools[_poolId].lastTimeStamp = block.timestamp;
    }

    // calculate accrued interest rate for borrowable deposit
    // update TUWIR_t to TUWIR_T to reset interest rate to zero
    // add interest rate to borrowable deposit
    // add interest rate to pool's total deposit
    // note: increasing total borrow and total deposit by interest rate does not chang pool's EL, as expected
    // however, it changes UR a bit upward
    
    function _addInterestRateToDeposit(uint256 _orderId)
        internal
    {
        Order memory order = orders[_orderId];

        // add interest rate multiplied by existing quantity to deposit
        orders[_orderId].quantity += depositInterestRate(order.poolId, _orderId).wMulDown(order.quantity);

        // update TUWIR_t to TUWIR_T to reset interest rate to zero
        orders[_orderId].orderWeightedRate = pools[order.poolId].timeUrWeightedRate;
    }

    // calculate accrued interest rate for borrowed quantity
    // add accrued interest rate to borrowed quantity
    // assume borrowInterestRate is accurate as _updateAggregate() has been called before
    // update TWIR_t to TWIR_T to reset interest rate to zero
    
    function _addInterestRateToPosition(uint256 _positionId)
        internal
    {
        Position memory position = positions[_positionId];

        // multiply interest rate with borrowed quantity and add to borrowed quantity
        positions[_positionId].borrowedAssets += 
            borrowInterestRate(position.poolId, _positionId).wMulUp(position.borrowedAssets);

        // update TWIR_t to TWIR_T in position to reset interest rate to zero
        positions[_positionId].positionWeightedRate = pools[position.poolId].timeWeightedRate;
    }

    // update borrow by adding interest rate to debt in all pool user borrows before calculating required collateral
    // required collateral in base assets needed to secure a user's debt in quote assets

    function _addInterestRateToUserPositions(address _borrower)
        internal
    {
        uint256[MAX_POSITIONS] memory borrowIds = users[_borrower].borrowIds;
        for (uint256 i = 0; i < MAX_POSITIONS; i++) {

            uint256 positionId = borrowIds[i]; // position id from which user borrows assets

            // look for borrowing positions to calculate required collateral
            if (positions[positionId].borrowedAssets > 0) {

                // update pool's total borrow and total deposits
                // increment TWIR/TUWIR before changes in pool's UR and calculating user's excess collateral
                _updateAggregates(positions[positionId].poolId);
                
                // add interest rate to borrowed quantity, update TWIR_t to TWIR_T to reset interest rate to zero
                _addInterestRateToPosition(positionId);
            }
        }
    }

    // check whether the pool is in quote token, base token or has not assets
    // update bottomOrder if necessary
    
    function _poolType(int24 _poolId) 
        internal
        returns (PoolIn poolType_)
    {
        Pool storage pool = pools[_poolId];
        poolType_ = PoolIn.none; // default

        for (uint256 row = pool.bottomOrder; row < pool.topOrder; row++) {
            uint256 orderId = pool.orderIds[row];
            if (orders[orderId].quantity > 0) {
                poolType_ = orders[orderId].isBuyOrder ? PoolIn.quote : PoolIn.base;
                pool.bottomOrder = row;
                break;
            }
        }
    }

    // check that taking assets in pool is profitable
    // if buy order, price feed must be lower than limit price
    // if sell order, price feed must be higher than limit price
    
    function _profitable(int24 _poolId)
        internal
        returns (bool)
    {
        if (_poolType(_poolId) == PoolIn.quote) return (priceFeed <= limitPrice[_poolId]);
        else if (_poolType(_poolId) == PoolIn.base) return (priceFeed >= limitPrice[_poolId]);
        else return false;
    }

    // check asset type of pool by checking asset type of bottom order in the queue with positiove assets
    function _poolHasAssets(int24 _poolId)
        internal
        returns (bool)
    {
        return (_poolType(_poolId) != PoolIn.none);
    }

    function _nearBy(int24 _poolId)
        internal
        returns (bool)
    {
        if (limitPrice[_poolId] > 0) return true;
        else if (limitPrice[_poolId - 1] > 0) {
            limitPrice[_poolId] = limitPrice[_poolId - 1] * PRICE_STEP;
            return true;
        }
        else if (limitPrice[_poolId + 1] > 0) {
            limitPrice[_poolId] = limitPrice[_poolId + 1] / PRICE_STEP;
            return true;
        }
        else return false;
    }

    //////////********* Public View functions *********/////////

    // excess collateral (EC), in base token, must always be positive
    // EC = max_LTV * total deposits - required collateral (RC):
    // return true if reducing deposit or increasing RC by _quantity keeps user's EC > 0 
    // RC is computed with interest rate previously added to borrowed assets

    function positiveExcessCollateral(
        address _user,
        uint256 _quantity
    )
        public view
        returns (bool)
    {
        uint256 deposits = getUserTotalDeposits(_user, !IN_QUOTE);
        uint256 collateral = getUserRequiredCollateral(_user);
        if (MAX_LTV.wMulDown(deposits) > collateral + _quantity) return true;
        else return false;
    }
    
    // get user's excess collateral in base token
    // excess collateral = max_LTV * total deposits - needed collateral must always be positive
    // needed collateral is computed with interest rate added to borrowed assets

    function getUserExcessCollateral(address _user)
        public view
        returns (uint256)
    {
        uint256 deposits = getUserTotalDeposits(_user, !IN_QUOTE);
        uint256 collateral = getUserRequiredCollateral(_user);

        if (MAX_LTV.wMulDown(deposits) > collateral) return deposits - collateral;
        else return 0;
    }
    
    // required collateral needed to secure user's debt in quote assets

    function getUserRequiredCollateral(address _borrower)
        public view
        returns (uint256 requiredCollateral_)
    {
        requiredCollateral_ = 0;
        uint256[MAX_POSITIONS] memory borrowIds = users[_borrower].borrowIds;

        for (uint256 i = 0; i < MAX_POSITIONS; i++) {

            Position memory position = positions[borrowIds[i]];

            if (position.borrowedAssets > 0)
                requiredCollateral_ += _convert(position.borrowedAssets, limitPrice[position.poolId], IN_QUOTE, ROUNDUP);
        }
    }
    
    // get UR = total borrow / total net assets in pool (in WAD)

    function getUtilizationRate(int24 _poolId)
        public view
        returns (uint256 utilizationRate_)
    {
        Pool storage pool = pools[_poolId];
        if (pool.deposits == 0) utilizationRate_ = 5 * WAD / 10;
        else if (pool.borrows >= pool.deposits) utilizationRate_ = 1 * WAD;
        else utilizationRate_ = pool.borrows.mulDivUp(WAD, pool.deposits);
    }
    
    // get instant rate r_t (in seconds) for pool
    // must be multiplied by 60 * 60 * 24 * 365 / WAD to get annualized rate

    function getInstantRate(int24 _poolId)
        public view
        returns (uint256 instantRate)
    {
        uint256 annualRate = ALPHA + BETA.wMulDown(getUtilizationRate(_poolId));
        instantRate = annualRate / YEAR;
    }

    // sum all assets deposited by user in quote or base token
    function getUserTotalDeposits(
        address _user,
        bool _inQuote
    )
        public view
        returns (uint256 totalDeposit)
    {
        uint256[MAX_ORDERS] memory depositIds = users[_user].depositIds;
        totalDeposit = 0;
        for (uint256 i = 0; i < MAX_ORDERS; i++) {
            if (orders[depositIds[i]].isBuyOrder == _inQuote) {
                totalDeposit += orders[depositIds[i]].quantity;
            }   
        }
    }

    function minDeposit(bool _isBuyOrder)
        public pure
        returns (uint256)
    {
        if (_isBuyOrder == true) return MIN_DEPOSIT_QUOTE;
        else return MIN_DEPOSIT_BASE;
    }

    //////////********* Internal View functions *********/////////

    // compute interest rate since start of deposit between t and T
    // exp(TWIR_T - TWIR_t) - 1 is computed using a 3rd order Taylor approximation

    // return false if desired quantity cannot be withdrawn
    function _removable(
        uint256 _orderId,
        uint256 _quantity // removed quantity
    )
        internal view
        returns (bool)
    {
        uint256 available = orders[_orderId].quantity;

        if (_quantity == available || _quantity + minDeposit(orders[_orderId].isBuyOrder) < available) return true;
        else return false;
    }

    function _poolAvailableAssets(int24 _poolId)
        internal view
        returns (uint256)
    {
        Pool storage pool = pools[_poolId];

        return _substract(pool.deposits, pool.borrows, "err 010", !RECOVER);
    }

    // return false if desired quantity is not possible to take
    function _takable(
        int24 _poolId,
        uint256 _takenQuantity,
        uint256 _minDeposit
    )
        internal view
        returns (bool)
    {
        uint256 availableAssets = _poolAvailableAssets(_poolId);
        
        if (_takenQuantity == availableAssets || _takenQuantity + _minDeposit <= availableAssets) return true;
        else return false;
    }
    
    function depositInterestRate(
        int24 _poolId,
        uint256 _orderId
    )
        internal view
        returns (uint256)
    {
        uint256 rateDiff = pools[_poolId].timeUrWeightedRate - orders[_orderId].orderWeightedRate;
        if (rateDiff > 0) return rateDiff.wTaylorCompoundedDown();
        else return 0;
    }
    
    // compute interest rate since start of borrowing position between t and T
    // assumes pools[_poolId].timeWeightedRate is up to date with _updateAggregate() previously called
    // exp(TWIR_T - TWIR_t) - 1 is computed using a 3rd order Taylor approximation

    function borrowInterestRate(
        int24 _poolId,
        uint256 _positionId
    )
        internal view
        returns (uint256)
    {
        uint256 rateDiff = pools[_poolId].timeWeightedRate - positions[_positionId].positionWeightedRate;
        if (rateDiff > 0) return rateDiff.wTaylorCompoundedUp();
        else return 0;
    }

    // returns order id if order exists in pool, even with zero quantity
    // by assumption, maker can create only one deposit in a pool and therefore can only choose one paired price
    // CHECK THIS ASSUMPTION ACTUALLY HOLD
    // returns 0 if doesn't exist
    
    function _getOrderIdInDepositIdsInUsers(
        address _user,
        int24 _poolId,
        bool _isBuyOrder
    )
        internal view
        returns (uint256 orderId_)
    {
        orderId_ = 0;
        uint256[MAX_ORDERS] memory depositIds = users[_user].depositIds;

        for (uint256 i = 0; i < MAX_ORDERS; i++) {
            Order memory order = orders[depositIds[i]];
            if (
                order.poolId == _poolId && 
                order.isBuyOrder == _isBuyOrder
            ){
                orderId_ = depositIds[i];
                break;
            }
        }
    }

    // get position id from borrowIds[] in user, even if has zero quantity
    // returns 0 if not found

    function getPositionId(
        address _borrower,
        int24 _poolId
    )
        internal view
        returns (uint256 positionId_)
    {
        positionId_ = 0;
        uint256[MAX_POSITIONS] memory positionIds = users[_borrower].borrowIds;
        for (uint256 i = 0; i < MAX_POSITIONS; i++) {
            if (positions[positionIds[i]].poolId == _poolId)
            {
                positionId_ = positionIds[i];
                break;
            }
        }
    }

    //////////********* Pure functions *********/////////
    
    // return true if order and pool have same asset type, or pool is empty (no asset type)
    // asset type of pool refers to first order's asset type
    
    function _sameType(
        bool _isBuyOrder,
        PoolIn _token
    )
        internal pure
        returns (bool)
    {
        if(
            (_isBuyOrder && _token != PoolIn.base) ||
            (!_isBuyOrder && _token != PoolIn.quote)
        )
        return true;
        else return false;
    }
    
    // check that order has consistent limit prices
    // if buy order, limit price must be lower than limit paired price
    // if sell order, limit price must be higher than limit paired price
    
    function _consistent(
        int24 _poolId,
        int24 _pairedPoolId,
        bool _inQuote
    )
        internal pure
        returns (bool)
    {
        if (_inQuote) return (_pairedPoolId >= _poolId);
        else return (_pairedPoolId <= _poolId);
    }
    
    function _convert(
        uint256 _quantity,
        uint256 _price,
        bool _inQuote, // type of the asset to convert to (quote or base token)
        bool _roundUp // round up or down
    )
        internal pure
        moreThanZero(_price)
        returns (uint256 convertedQuantity)
    {
        if (_roundUp) convertedQuantity = _inQuote ? _quantity.wDivUp(_price) : _quantity.wMulUp(_price);
        else convertedQuantity = _inQuote ? _quantity.wDivDown(_price) : _quantity.wMulDown(_price);
    }

    function _isQuote(PoolIn _poolToken)
        internal pure
        returns (bool)
    {
        if (_poolToken == PoolIn.quote) return true;
        else if (_poolToken == PoolIn.base) return false;
        else revert("Pool has no orders");
    }

    /////**** Functions used in tests ****//////

    function setPriceFeed(uint256 _newPrice)
        public
    {
        priceFeed = _newPrice;
    }
    
    // Add manual getter for depositIds for User, used in AX_ORDERSreachedsetup.sol for tests
    function getUserDepositIds(address _user)
        public view
        returns (uint256[MAX_ORDERS] memory)
    {
        return users[_user].depositIds;
    }

    // Add manual getter for borroFromIds for User, used in setup.sol for tests
    function getUserBorrowFromIds(address _user)
        public view
        returns (uint256[MAX_POSITIONS] memory)
    {
        return users[_user].borrowIds;
    }

    // used in tests
    function countOrdersOfUser(address _user)
        public view
        returns (uint256 count)
    {
        count = 0;
        uint256[MAX_ORDERS] memory depositIds = users[_user].depositIds;
        for (uint256 i = 0; i < MAX_ORDERS; i++) {
            if (orders[depositIds[i]].quantity > 0) count ++;
        }
    }

}