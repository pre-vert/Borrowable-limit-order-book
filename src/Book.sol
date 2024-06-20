// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

/// title A lending order book for ERC20 tokens (V1.0)
/// author Pré-vert
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
    /// - takeQuoteTokens: allow users to fill limit orders at limit price when profitable, may liquidate positions along the way
    /// - takeBaseTokens: allow users to fill limit orders at limit price, may close positions along the way
    /// - changePairedPrice: allow user to change order's paired limit price
    /// - liquidateUser: allow liquidators to liquidate borrowers close to undercollateralization
    /// - depositInCollateralAccount: desposit collateral assets in user's account
    /// - WithdrawFromAccount: withraw base or quote assets from user's account

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  CONSTANTS                                 */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    // Starting pool id for genesis buy orders
    // even id: pool of buy orders, odd id : pool of sell orders
    
    uint256 constant public GenesisPoolId = 1111111110;

    // How many orders a user can place in different pools on both sides of the order book
    uint256 constant public MAX_ORDERS = 6;
    // How many positions a user can open in different pools of buy orders
    uint256 constant public MAX_POSITIONS = 3; 
    // Minimum liquidation rounds after take() is called
    uint256 constant public MIN_ROUNDS = 3;
    // id for non existing order or position in arrays
    // uint256 constant private ABSENT = type(uint256).max;
    // applies to token type (ease reading in function attributes)
    bool constant private IN_QUOTE = true; 
    // // applies to position (true) or order (false) (ease reading in function attributes)
    // bool constant private TO_POSITION = true;
    // round up in conversions (ease reading in function attributes)
    bool constant private ROUNDUP = true; 
    // IRM parameter = 0.005
    uint256 public constant ALPHA = 5 * WAD / 1e3;
    // IRM parameter = 0.015
    uint256 public constant BETA = 15 * WAD / 1e3;
    // uint256 public constant GAMMA = 10 * WAD / 1e3; // IRM parameter =  0.01
    // ALTV = 98% = to put in the constructor
    // uint256 public constant ALTV = 98 * WAD / 100;
    // PHI = 90% with available liquidity = PHI * (sum deposits) - (sum borrows)
    uint256 public constant PHI = 9 * WAD / 10;
    // interest-based liquidation penalty for maker = 3%
    uint256 public constant LIQUIDATION_FEE = 3 * WAD / 100;
    // number of seconds in one year
    uint256 public constant YEAR = 365 days;
    // how negative uint256 following substraction are handled
    bool private constant RECOVER = true;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  STRUCT VARIABLES                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    // orders and borrows by users
    struct User {
        // collateral account for borrowers who don't want to sell at a limit price
        uint256 baseAccount;
        // quote account where quote assets go after a borrower's position is closed
        uint256 quoteAccount;
        // orders id in mapping orders
        uint256[MAX_ORDERS] depositIds;
        // positions id in mapping positions, only in quote tokens
        uint256[MAX_POSITIONS] borrowIds;
    }
    
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
        // # of seconds since last time instant interest rate has been updated in pool
        uint256 lastTimeStamp;
        // time-weighted average interest rate since inception of pool, applied to borrows
        uint256 timeWeightedRate;
        // time-weighted and UR-weighted average interest rate since inception of pool, applied to deposits
        uint256 timeUrWeightedRate;

        // ** queue management variables ** //

        // row index of orderId on top of orderIds mapping to add order id; starts at 0
        uint256 topOrder;
        // row index of last orderId deleted from orderIds mapping following take; starts at 0
        uint256 bottomOrder;
        // row index of positionId on the top of positionIds mapping to add position id; starts at 0
        uint256 topPosition;
        // row index of last positionId deleted from positionIds mapping; starts at 0
        uint256 bottomPosition;
    }
    
    struct Order {
        // pool id of order
        uint256 poolId;
        // address of maker
        address maker;
        // pool id of paired order
        uint256 pairedPoolId;
        // assets deposited (quote tokens for buy orders, base tokens for sell orders)
        uint256 quantity;
        // time-weighted and UR-weighted average interest rate for supply since initial deposit or reset
        // set to 1 at start and increments with time for buy orders
        uint256 orderWeightedRate;
    }

    // borrowing positions
    struct Position {
        // pool id in mapping orders, from which assets are borrowed
        uint256 poolId;
        // address of borrower
        address borrower;
        // quantity of quote assets borrowed
        uint256 borrowedAssets;
        // time-weighted average interest rate for position since creation or reset
        uint256 positionWeightedRate;
    }

    // *** MAPPINGS *** //

    // even numbers refer to buy order pools and odd numbers to sell order pools
    // pool index starts at GenesisPoolId >> 0 for first buy order pool in constructor
    // in UI, first order is assigned to pool[GenesisPoolId] if buy order or pool[GenesisPoolId + 1] if sell order

    mapping(uint256 poolId => Pool) public pools;

    // outputs pool's limit price
    // same limit price for adjacent buy orders' and sell orders' pools

    mapping(uint256 poolId => uint256) public limitPrice; 

    mapping(uint256 orderId => Order) public orders;
    mapping(address user => User) public users;
    mapping(uint256 positionId => Position) public positions;

    // *** VARIABLES *** //

    IERC20 immutable public quoteToken;
    IERC20 immutable public baseToken;
    // Price step for placing orders (defined in constructor)
    uint256 immutable public priceStep;
    // Minimum deposited base tokens (defined in constructor)
    uint256 immutable public minDepositBase;
    // Minimum deposited quote tokens (defined in constructor)
    uint256 immutable public minDepositQuote;
    // liquidation LTV (defined in constructor)
    uint256 immutable public liquidationLTV;
    // initial order id (0 for non existing orders)
    uint256 private lastOrderId = 1;
    // initial position id (0 for non existing positions)
    uint256 private lastPositionId = 1;
    // Oracle price (simulated)
    uint256 public priceFeed;

    // *** CONSTRUCTOR *** //
 
    constructor(
        address _quoteToken,
        address _baseToken,
        uint256 _startingLimitPrice,
        uint256 _priceStep,
        uint256 _minDepositBase,
        uint256 _minDepositQuote,
        uint256 _liquidationLTV
    ) {
        quoteToken = IERC20(_quoteToken);
        baseToken = IERC20(_baseToken);
        limitPrice[GenesisPoolId] = _startingLimitPrice;   // initial limit price for the genesis buy order pool
        priceStep = _priceStep;
        minDepositBase = _minDepositBase;
        minDepositQuote = _minDepositQuote;
        liquidationLTV = _liquidationLTV;
    }


    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  EXTERNAL FUNCTIONS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
    
    /// @notice lets users place orders in a pool, either of buy orders or sell orders
    /// @param _poolId id of pool in which user deposits, 
    /// @param _quantity quantity of assets deposited (quoteToken for buy orders, baseToken for sell orders)
    /// @param _pairedPoolId id of pool in which the assets taken are reposted (only for lenders)
    /// pool id at deployment starts at GenesisPoolId (buy order)
    /// if borrowers deposit collateral base assets:
    /// - pool id is specified by user = at which limit price position is closed (if any)
    ///   (if not specified, use instead depositInCollateralAccount())
    /// - paired pool id is hard coded to 0 => converted assets are deposited in user's quote account
    /// if lenders deposit quote assets:
    /// - specifying pool id is mandatory
    /// - by default, paired pool id is at the same limit price, or in advanced mode at user's discretion

    function deposit(
        uint256 _poolId,
        uint256 _quantity,
        uint256 _pairedPoolId // always equal to zero if deposits base assets
    )
        external
    {
        // console.log(" ");
        // console.log("*** Deposit ***");
        // console.log("Maker :", msg.sender);
        
        require(_quantity > 0, "Deposit zero");

        // _poolId is even => isBuyOrder = true, else false
        bool isBuyOrder = _isQuotePool(_poolId);
        
        // paired limit order in opposite token
        require(_isQuotePool(_pairedPoolId) != isBuyOrder, "Wrong paired pool");

        // pool has a calculated price 
        // or is adjacent to a pool id with a price and its price is calculated on the fly    
        require(_priceExists(_poolId), "Limit price too far");

        // minimal quantity deposited
        require(_quantity >= viewMinDeposit(isBuyOrder), "Not enough deposited");

        if (isBuyOrder) {

            // paired pool has a calculated price or is adjacent to a pool id with a price  
            require(_priceExists(_pairedPoolId), "Paired price too far");

            // limit price and paired limit price are in right order
            require(_consistent(_poolId, _pairedPoolId), "Inconsistent prices");

            // in buy order (borrowable) market, update pool's total borrow and total deposits
            // increment TWIR and TUWIR before accounting for changes in UR and future interest rate
            // needed before _createOrder()

            _addInterestRateToPoolBorrowAndDeposits(_poolId);
        }
        
        else require(_pairedPoolId == 0, "Non zero paired price");

        // pool must not be profitable to fill (ongoing or potential liquidation)
        require(!getIsProfitable(_poolId), "Ongoing liquidation");

        // check if maker already supplies in pool with same paired pool, even with zero quantity
        // return order id if found, else return id = zero

        uint256 orderId_ = getOrderIdInDepositIdsOfUser(msg.sender, _poolId, _pairedPoolId);

        // if new order:
        // add new orderId in depositIds[] in users
        // add new orderId on top of orderIds[] in pool
        // revert if max orders reached
        // increment topOrder
        // return new order id

        if (orderId_ == 0) orderId_ = _createOrder(_poolId, msg.sender, _pairedPoolId, _quantity);
        
        // if order already exists

        else {
            
            // if buy order, add interest rate to existing borrowable deposit
            // update TUWIR_t to TUWIR_T to reset interest rate to zero

            if (isBuyOrder) _addInterestRateToDeposit(orderId_);

            // add new quantity to existing deposit
            orders[orderId_].quantity += _quantity;
        }

        // add new quantity to total deposits in pool
        pools[_poolId].deposits += _quantity;

        // transfer quote or base tokens from supplier
        _transferFrom(msg.sender, _quantity, isBuyOrder);

        emit Deposit(msg.sender, _poolId, orderId_, _quantity, _pairedPoolId);

        // console.log("*** End Deposit");
    }

    /// @notice withdraw from any side of the book
    /// if lenders remove quote assets, check:
    /// - buy order +IR has enough liquidity
    /// - pool +IR has enough non borrowed liquidity
    /// if borrowers remove collateral base assets check :
    /// - sell order has enough liquidty
    /// - user's excess collateral remains positive after removal

    function withdraw(
        uint256 _orderId,
        uint256 _removedQuantity
    )
        external
    {
        // console.log(" ");
        // console.log("*** Wihdraw ***");
        // console.log("Remover :", msg.sender);
        // console.log("Removed quantity :", _removedQuantity / WAD);
        
        require(_removedQuantity > 0, "Remove zero");
        
        Order memory order = orders[_orderId];        // SLOAD: loads order's 5 children from storage
        
        // order must have funds to begin with
        require(order.quantity > 0, "No order");
        
        // funds removed only by owner
        require(order.maker == msg.sender, "Not maker");

        // _poolId is even => isBuyOrder = true, else false
        bool isBuyOrder = _isQuotePool(order.poolId);

        // console.log("Remove buy order :", isBuyOrder);

        // if lenders remove quote assets
        
        if (isBuyOrder) {
            
            // update pool's total borrow and total deposits
            // increment TWIR/TUWIR before calculating pool's availale assets
            _addInterestRateToPoolBorrowAndDeposits(order.poolId);

            // console.log("Total deposits after update Aggregates:", pools[order.poolId].deposits / WAD);

            // cannot withdraw more than available assets in pool
            // withdraw no more than full liquidity in pool or lets min deposit if partial

            require(getIsRemovableFromPool(orders[_orderId].poolId, _removedQuantity), "Remove too much_1");

            // console.log("Available assets in pool before withdraw :", viewPoolAvailableAssets(order.poolId) / WAD, "USDC");

            // add interest rate to existing deposit
            // reset deposit's interest rate to zero
            // updates how much assets can be withdrawn (used in getRemovableFromOrder() below)

            _addInterestRateToDeposit(_orderId);

            // console.log("Total deposits after adding interest rate to deposit:", orders[_orderId].quantity / WAD, "ETH");
        }

        // if borrower removes collateral assets 
        // check enough collateral remains compared to positions + IR

        else require(viewIsUserExcessCollateralPositive(msg.sender, _removedQuantity), "Remove too much_2");

        // withdraw no more than deposit net of min deposit if partial
        require(getRemovableFromOrder(_orderId, _removedQuantity), "Remove too much_3");

        // console.log("User deposits before substraction:", order.quantity / WAD, "ETH");

        // reduce quantity in order, possibly to zero
        orders[_orderId].quantity -= _removedQuantity;

        // console.log("User deposits after substraction:", orders[_orderId].quantity / WAD, "ETH");

        // console.log("Total deposits before substraction:", pools[order.poolId].deposits / WAD, "ETH");

        // reduce total deposits in pool
        pools[order.poolId].deposits -= _removedQuantity;

        // console.log("Total deposits after substraction:", pools[order.poolId].deposits / WAD, "ETH");

        // console.log("Utilization rate post withdraw 1e4:", 1e4 * viewUtilizationRate(order.poolId) / WAD);

        // transfer quote or base assets to withdrawer
        _transferTo(msg.sender, _removedQuantity, isBuyOrder);

        emit Withdraw(_orderId, _removedQuantity);

        // console.log("*** End Withdraw");
    }

    /// @notice Lets users borrow assets from pool (create or increase a borrowing position)
    /// Borrowers need to deposit enough collateral first in:
    /// - sell orders on the other side of the book if they opt for an automatically closed position in profit
    /// - base account
    /// pool is borrowable up to pool's available assets or user's excess collateral

    function borrow(
        uint256 _poolId,
        uint256 _quantity
    )
        external
    {
        // console.log(" ");
        // console.log("*** Borrow ***");
        // console.log("Borrower:", msg.sender);
        // console.log("borrowed assets :", _quantity / WAD, "USDC");
        // console.log("                        Pool id :", _poolId);
        
        require(_quantity > 0, "Borrow zero");

        // only quote tokens can be borrowed
        require(_isQuotePool(_poolId), "Cannot borrow_0");

        require(getHasPoolAssets(_poolId), "Pool_empty_1");
        
        // revert if pool is profitable to take (ie. liquidation is ongoing)
        // otherwise users could arbitrage the protocol by depositing cheap assets and borrowing more valuable assets

        require(!getIsProfitable(_poolId) , "Cannot borrow_1");

        // increment TWIR/TUWIR before calculation of pool's available assets
        // update pool's total borrow, total deposits
        _addInterestRateToPoolBorrowAndDeposits(_poolId);

        // cannot borrow more than available assets in pool to borrow
        require(_quantity <= viewPoolAvailableAssets(_poolId), "Borrow too much_2");

        // console.log("Borrowable assets in pool before borrow :", viewPoolAvailableAssets(_poolId) / WAD, "USDC");

        // how much collateral is needed to borrow _quantity?
        // _quantity is converted at limit price and inflated by LLTV

        uint256 scaledUpMinusCollateral = 
            _convert(_quantity, limitPrice[_poolId], IN_QUOTE, ROUNDUP).wDivUp(liquidationLTV);

        // console.log("Additional required collateral x 100:", 100 * scaledUpMinusCollateral / WAD, "ETH");

        // check borrowed amount is collateralized enough by borrower's own orders
        // if collateral needed to borrow X is deduced from existing collateral, is user still solvent?

        require(viewIsUserExcessCollateralPositive(msg.sender, scaledUpMinusCollateral), "Borrow too much_3");

        // check if user already borrows from pool even with zero quantity
        // return position id if found, else return id = zero

        uint256 positionId_ = getPositionIdInborrowIdsOfUser(msg.sender, _poolId);

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

        // console.log("Borrowable assets in pool after borrow :", viewPoolAvailableAssets(_poolId) / WAD, "USDC");

        // console.log("Utilization rate post borrow* 1e4:", 1e4 * viewUtilizationRate(_poolId) / WAD);

        // transfer quote assets to borrower
        _transferTo(msg.sender, _quantity, IN_QUOTE);

        emit Borrow(msg.sender, _poolId, positionId_, _quantity);

        // console.log("*** End Borrow ***");
    }

    /// @notice lets users decrease or close a borrowing position

    function repay(
        uint256 _positionId,
        uint256 _quantity
    )
        external
    {
        // console.log(" ");
        // console.log("*** Repay ***");
        // console.log("Repayer :", msg.sender);
        // console.log("Repayed quantity :", _quantity / WAD, "USDC");
        
        require(_quantity > 0, "Repay zero");
        
        Position memory position = positions[_positionId];

        // borrow to repay must be positive
        require(position.borrowedAssets > 0, "Not borrowing");
        
        // assets repaid by borrower, not someone else
        require(position.borrower == msg.sender, "Not Borrower");

        // repay must be in quote tokens
        require(_isQuotePool(position.poolId), "Non borrowable pool");

        // update pool's total borrow and total deposits
        // increment time-weighted rates with IR based on UR before repay

        _addInterestRateToPoolBorrowAndDeposits(position.poolId);

        // add interest rate to borrowed quantity
        // reset position accumulated interest rate to zero

        _addInterestRateToPosition(_positionId);

        // cannot repay more than borrowed assets
        require(_quantity <= positions[_positionId].borrowedAssets, "Repay too much");

        // decrease borrowed assets in position, possibly to zero
        positions[_positionId].borrowedAssets -= _quantity;

        // console.log("Borrowed assets + interest rate after repay :", positions[_positionId].borrowedAssets / WAD, "USDC");

        // decrease borrowed assets in pool's total borrow (check no asset mismatch)
        pools[position.poolId].borrows -= _quantity;

        // console.log("Utilization rate post repay* 1e4:", 1e4 * viewUtilizationRate(position.poolId) / WAD);

        // transfer quote assets from repayer
        _transferFrom(msg.sender, _quantity, IN_QUOTE);
        
        emit Repay(_positionId, _quantity);

        // console.log("*** End Repay ***");
    }

    // Let takers take (even for zero) buy orders in pool and exchange base assets against quote assets
    // - liquidates a number of positions borrowing from a given pool of buy orders
    // - seize collateral in users' account and/or sell orders for the exact amount of liquidated assets
    // - take available quote assets in exchange of base assets at pool's limit price
    // - repost assets in sell orders at a pre-specified limit price

    // _addInterestRateToPoolBorrowAndDeposits()      | update total borrows and deposits of taken pool with interest rate
    // _liquidatePositions()    | liquidate positions one after one
    //  ├── _closePosition()    |    liquidate one position in full
    //  └── _seizeCollateral()  |    seize collateral of the position for the exact amount liquidated, starting by user's account
    // _closeBuyOrders()        | close buy orders for amount of base assets received from taker and liquidated borrowers
    //  └── _repostLiquidity()  |    repost base tokens received to one sell order (same limit price by default)
    // _transferFrom()          | transfer base tokens from taker to contract
    // _transferTo()            | transfer quote tokens from contract to taker

    function takeQuoteTokens(
        uint256 _poolId,
        uint256 _takenQuantity
    )
        external
    {
        // console.log(" ");
        // console.log("*** Take quote tokens ***");
        // console.log("Taker :", msg.sender);
        // console.log("pool id taken :", _poolId);
        // console.log("quantity taken :", _takenQuantity / WAD, "USDC");
        
        // reverts if no assets to take
        require(getHasPoolAssets(_poolId), "Pool_empty_2");

        // only quote tokens can be taken
        require(_isQuotePool(_poolId), "Take base tokens");

        Pool storage pool = pools[_poolId];
        
        // taking non profitable buy orders reverts
        require(getIsProfitable(_poolId), "Not profitable");

        // update pool's total borrow and total deposits with interest rate
        _addInterestRateToPoolBorrowAndDeposits(_poolId);

        // pool's utilization rate (before debts cancelation)
        uint256 utilizationRate = viewUtilizationRate(_poolId);

        // console.log("utilizationRate :", 100 * utilizationRate / WAD, "%");

        // nothing to take if 100 % utilization rate
        require (utilizationRate < 1 * WAD, "Nothing to take");

        // console.log("pool.deposits :", pool.deposits / WAD, "USDC");
        // console.log("pool.borrows :", pool.borrows / WAD, "USDC");

        // cannot take more than pool's available assets
        require(_takenQuantity + pool.borrows <= pool.deposits, "Take too much");
        
        // buy orders can be closed for two reasons:
        // - filled by takers
        // - receive collateral from sell orders
        // total amount received in base tokens is posted in a sell order
        
        // min canceled debt (in quote assets) is scaled by _takenQuantity * UR / (1-UR)
        // _takenQuantity: quote assets received by taker, used to calculate the amount of liquidated quote assets
        // higher UR, higher liquidated quote assets per unit of taken assets
        // Examples:
        // - if UR = 0, min canceled debt is zero
        // - if UR = 50%, min canceled debt is 100%

        uint256 minCanceledDebt = _takenQuantity.mulDivUp(utilizationRate, WAD - utilizationRate);
        
        // console.log("minCanceledDebt :", minCanceledDebt / WAD, "USDC");

        // then, liquidate positions:
        // - delete borrow
        // - seize borrower's collateral
        // until:
        // - MIN_ROUNDS positions have been liquidated, and min canceled debt is reached
        // - or no more position to liquidate
        // returns total liquidated assets (expressed in quote tokens at limit price)

        uint256 liquidatedQuotes = 0;
        
        if (minCanceledDebt > 0) liquidatedQuotes = _liquidatePositions(_poolId, minCanceledDebt);

        // then close buy orders for exact amount of quote tokens
        // for every closed order:
        // - set deposit to zero
        // - repost assets in sell order
        // until exact amount of liquidated quote assets and taken quote quantity is reached

        uint256 closedAmount = _closeBuyOrders(_poolId, _takenQuantity + liquidatedQuotes);

        // would _takenQuantity have been set too high, despite safeguards, closedAmount < _takenQuantity + liquidatedQuotes 

        uint256 takenAssets = _substract(closedAmount, liquidatedQuotes, "err_01", !RECOVER);
        
        // console.log("Taken assets :", takenAssets / WAD);

        uint256 receivedAssets = _convert(takenAssets, limitPrice[_poolId], IN_QUOTE, !ROUNDUP);

        // console.log("pool.deposits after take :", pool.deposits / WAD, "USDC");
        // console.log("pool.borrows after take :", pool.borrows / WAD, "USDC");
        // console.log("Utilization rate after take* 1e4:", 1e4 * viewUtilizationRate(_poolId) / WAD);

        // transfer base assets from taker
        _transferFrom(msg.sender, receivedAssets, !IN_QUOTE);
        
        // transfer quote assets to taker
        _transferTo(msg.sender, takenAssets, IN_QUOTE);
        
        emit TakeQuoteTokens(msg.sender, _poolId, _takenQuantity);
    }
    
    // Let takers take sell orders in pool of base assets
    // - take available base assets in exchange of quote assets
    // - close positions and pay back makers with received quote assets

    // _takeSellOrders()        | take sell orders one after one
    // ├── _reduceUserDebt()    |    if order is collateral, repay debt with quote tokens received from taker, deposits remaining quote assets in user's account
    // └── _repostLiquidity()   |    if not, repost received quote tokens received in buy order at ??
    //  _transferFrom()         | transfer quote tokens from taker to contract
    //  _transferTo()           | transfer base tokens from contract to taker

    function takeBaseTokens(
        uint256 _poolId,
        uint256 _takenQuantity
    )
        external
    {
        // console.log(" ");
        // console.log("*** Take base tokens ***");
        // console.log("Taker :", msg.sender);
        // console.log("pool id taken :", _poolId);
        // console.log("quantity taken :", _takenQuantity / WAD, "ETH");
        
        require(_takenQuantity > 0, "Take zero");
        
        // reverts if no assets to take
        require(getHasPoolAssets(_poolId), "Pool_empty_3");
        
        // only base tokens can be taken
        require(!_isQuotePool(_poolId), "Take quotes");

        Pool storage pool = pools[_poolId];

        // cannot take more than pool's available assets
        require(_takenQuantity <= pool.deposits, "Take too much");
        
        // console.log("** _takeSellOrders() **");
        
        // take sell orders and, if collateral, close maker's positions in quote tokens
        // repost remaining assets in user's account or buy order

        uint256 takenAssets = _takeSellOrders(_poolId, _takenQuantity);

        uint256 receivedAssets = _convert(takenAssets, limitPrice[_poolId], !IN_QUOTE, !ROUNDUP);

        // console.log("pool.deposits after take :", pool.deposits / WAD, "ETH");
        // console.log("pool.borrows after take :", pool.borrows / WAD, "ETH");

        // transfer quote assets from taker
        _transferFrom(msg.sender, receivedAssets, IN_QUOTE);
        
        // transfer base assets to taker
        _transferTo(msg.sender, takenAssets, !IN_QUOTE);
        
        emit TakeBaseTokens(msg.sender, _poolId, _takenQuantity);
    }

    /// @notice Liquidate borrowing positions from users whose excess collateral is negative
    /// - iterate on borrower's positions and cancel positions one after one
    /// - seize equivalent amount of collateral tokens at discount
    /// Collateral is in user's account and possibly in multiple sell orders:
    ///  - start by user's account then, if not enough, iterate on borrower's sell orders to write off collateral
    ///  - stop when borrower's debt is fully canceled
    ///  - change internal balances

    /// @param _suppliedQuotes: quantity of quote assets supplied by liquidator in exchange of base collateral assets
    /// protection against dust needed ?

    function liquidateUser(
        address _user,
        uint256 _suppliedQuotes
    )
        external
    {      
        // console.log("*** Start Liquidate user ***");

        require(_suppliedQuotes > 0, "Supply zero");
        
        // borrower's excess collateral must be zero or negative
        // interest rate is added to all user's position before

        require(!viewIsUserExcessCollateralPositive(_user, 0), "Solvent");

        // reduce user's borrowing positions possibly as high as _suppliedQuotes
        uint256 reducedDebt = _reduceUserDebt(_user, _suppliedQuotes);

        // console.log("   reducedDebt :", reducedDebt / WAD, "USDC");

        // the lower exchange rate ETH/USDC: p* = p/(1+fee_rate), the higher liqidator receives against USDC
        // we want liquidator to buy ETH cheap against USDC: price p must be decreased by fee rate

        uint256 exchangeRate = priceFeed.wDivDown(WAD + LIQUIDATION_FEE); 

        // console.log("   exchangeRate * 100 :", 100 * exchangeRate / WAD);

        // liquidator provides X USDC and receives X/p* ETH = collateralToSeize
        // as p* < p the amount of ETH liquidators get against USDC is enhanced

        uint256 collateralToSeize = _convert(reducedDebt, exchangeRate, IN_QUOTE, !ROUNDUP);

        // console.log("   collateralToSeize * 100 :", 100 * collateralToSeize / WAD, "ETH");

        // seizedCollateral is borrower's collateral actually seized, which is at most collateralToSeize
        uint256 seizedCollateral = _seizeCollateral(_user, collateralToSeize);

        // console.log("   seizedCollateral * 100 :", 100 * seizedCollateral / WAD, "ETH");

        // transfer quote assets from liquidator
        _transferFrom(msg.sender, reducedDebt, IN_QUOTE);
        
        // transfer collateral to liquidator
        _transferTo(msg.sender, seizedCollateral, !IN_QUOTE);

        emit LiquidateBorrower(msg.sender, reducedDebt);

        // console.log("*** End Liquidate user ***");
    }

    /// let maker change the paired limit price of her order

    function changePairedPrice(
        uint256 _orderId,
        uint256 _newPairedPoolId
    )
        external
    {
        Order memory order = orders[_orderId];

        // paired price change by maker
        require(order.maker == msg.sender, "Only maker");
        
        // revert if position not found
        require(order.quantity > 0, "No order");

        // revert if new paired price is current paired price
        require(_newPairedPoolId != order.pairedPoolId, "Same price");

        // revert if limit price and new paired limit price are in wrong order
        require(_consistent(order.poolId, _newPairedPoolId), "Inconsistent prices");
        
        // newPoolId must have a price or be adjacent to a pool id with a price   
        require(_priceExists(_newPairedPoolId), "Paired price too far");

        orders[_orderId].pairedPoolId = _newPairedPoolId;
        
        emit ChangePairedPrice(_orderId, _newPairedPoolId);
    }

    /// @notice lets user deposit collateral asset in account outside the book and without limit price
    /// @param _quantity The quantity of base assets deposited

    function depositInCollateralAccount(
        uint256 _quantity
    )
        external
    {
        // console.log(" ");
        // console.log("*** Deposit in collateral account***");
        // console.log("Maker :", msg.sender);
        // console.log("Deposited quantity :", _quantity / WAD, "ETH");
        
        require(_quantity > 0, "Deposit zero");

        // console.log("Quantity before deposit :", users[msg.sender].baseAccount / WAD, "ETH");

        // add base assets in collateral account
        users[msg.sender].baseAccount += _quantity;

        // console.log("Qunatity after deposit :", users[msg.sender].baseAccount / WAD, "ETH");

        // transfer base assets from user
        _transferFrom(msg.sender, _quantity, !IN_QUOTE);

        emit DepositInCollateralAccount(msg.sender, _quantity);
    }

    /// @notice lets borrower withdraw his:
    /// - collateral assets after his position is closed manually
    /// - quote assets after his position is closed automatically
    /// before collateral assets are removed, check user's excess collateral remains positive

    function withdrawFromAccount(
        uint256 _quantity,
        bool _inQuote
    )
        external
    {
        // console.log(" ");
        // console.log("*** Wihdraw from account***");
        // console.log("Remover :", msg.sender);
        
        require(_quantity > 0, "Remove zero");

        // console.log("Is removed assets quote assets :", _inQuote);

        // if borrower removes collateral assets:
        
        if (!_inQuote) {

            // console.log("User deposits before removal:", users[msg.sender].baseAccount / WAD, "ETH");
            // console.log("Removed quantity :", _quantity / WAD, "ETH");

            // withdraw no more than deposited base assets
            require(users[msg.sender].baseAccount >= _quantity, "Remove too much_4");

            // check it doesn't break solvency
            require(viewIsUserExcessCollateralPositive(msg.sender, _quantity), "Remove too much_5");

            // reduce base assets in account, possibly to zero
            users[msg.sender].baseAccount -= _quantity;

            // console.log("User deposits after removal:", users[msg.sender].baseAccount / WAD, "ETH");
        }

        // if borrower removes quote assets, check quantity doesn't exceed deposit

        else {
            
            // console.log("User deposits before removal:", users[msg.sender].quoteAccount / WAD, "USDC");
            // console.log("Removed quantity :", _quantity / WAD, "USDC");
            
            // withdraw no more than deposited base assets
            require(users[msg.sender].quoteAccount >= _quantity, "Remove too much_6");

            // reduce base assets in account, possibly to zero
            users[msg.sender].quoteAccount -= _quantity;

            // console.log("User deposits after removal:", users[msg.sender].quoteAccount / WAD, "USDC");
        }

        // transfer quote or base assets to withdrawer
        _transferTo(msg.sender, _quantity, _inQuote);

        emit WithdrawFromAccount(msg.sender, _quantity, _inQuote);
    }


    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  INTERNAL FUNCTIONS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
    
    /// create new, buy or sell, order
    /// add new orderId in depositIds[] in users
    /// add new orderId on top of orderIds[] in pool
    /// @return newOrderId_ id of newly created order
    
    function _createOrder(
        uint256 _poolId,
        address _maker,
        uint256 _pairedPoolId,
        uint256 _quantity
    )
        internal
        returns (uint256 newOrderId_)
    {
        // only buy orders accrue interest rate
        // _addInterestRateToPoolBorrowAndDeposits() has been called before

        uint256 orderWeightedRate = _isQuotePool(_poolId) ? pools[_poolId].timeUrWeightedRate : 0;
        
        // seed new order
        Order memory newOrder = Order(
            _poolId,
            _maker,
            _pairedPoolId,
            _quantity,
            orderWeightedRate
        );

        newOrderId_ = lastOrderId;
        // console.log("                  ** New order created **");
        // console.log("                        New order id :", lastOrderId);
        // console.log("                        Pool id :", _poolId);
        // console.log("                        Order weighted rate :", orderWeightedRate);

        // create new order in orders
        orders[newOrderId_] = newOrder;
        // console.log("                        New order quantity :", orders[newOrderId_].quantity / WAD);
        // console.log("                        New order is buy order :", _isQuotePool(_poolId));

        lastOrderId ++;

        // add new orderId in depositIds[] in users
        // revert if max orders reached

        // console.log("                  Enter _insertOrderIdInDepositIdsInUser");
        _insertOrderIdInDepositIdsInUser(_maker, newOrderId_);
        // console.log("                  Exit _insertOrderIdInDepositIdsInUser()");

        // add new orderId on top of orderIds[] in pool
        // increment topOrder

        // console.log("                  Enter _addOrderIdToOrderIdsInPool()");
        _addOrderIdToOrderIdsInPool(_poolId, newOrderId_);
        // console.log("                  Exit _addOrderIdToOrderIdsInPool()");
    }

    /// @notice liquidate positions and seize collateral until minimum total liquidated assets are reached
    /// @param _minCanceledDebt minimum quote tokens to liquidate
    /// @return cumulLiquidatedQuotes_
    
    function _liquidatePositions(
        uint256 _poolId,
        uint256 _minCanceledDebt
    )
        internal
        returns (uint256 cumulLiquidatedQuotes_)
    {
        // console.log("   ** _liquidatePositions() **");

        Pool storage pool = pools[_poolId];
        
        // cumulated liquidated quote assets
        cumulLiquidatedQuotes_ = 0;

        // number of liquidation iterations
        uint256 rounds = 0;
        
        // iterate on position id in pool's positionIds from bottom to top and close positions
        
        // pool.topPosition is first available slot for positions in pool's positionIds
        // pool.bottomPosition is first possible slot for positions to be liquidated
        // pool.bottomPosition == pool.topPosition means that there is noting more to liquidate
        // Example: a first borrow is recorded at topPosition = 0; topPosition is incremented to 1
        // In a liquidation event, bottomPosition starts at 0 < 1, finds a position to close
        // then increments to 1 and stops as 1 == 1
        
        // console.log("      Enter loops over positions to be closed");
        
        for (uint256 row = pool.bottomPosition; row < pool.topPosition; row++) {

            // which position in pool is closed
            uint256 positionId = pool.positionIds[row];

            // console.log("         --> PositionId of next position to be closed: ", positionId);

            // check user has still borrowed assets in pool
            if (positions[positionId].borrowedAssets == 0) continue;

            rounds ++;

            // close position:
            // - cancel full debt (in quote assets)
            // - seize collateral (in base assets)

            uint256 liquidatedAssets = _closePosition(positionId);

            uint256 collateralToSeize = _convert(liquidatedAssets, limitPrice[_poolId], IN_QUOTE, ROUNDUP);
            
            // console.log("         collateralToSeize :", collateralToSeize / WAD, "ETH");

            // seize collateral in borrower's base account and sell orders for exact amount
            _seizeCollateral(positions[positionId].borrower, collateralToSeize);

            // add liquidated assets to cumulated liquidated assets
            cumulLiquidatedQuotes_ += liquidatedAssets;

            // if enough assets are liquidated by taker (given take's size), stop
            // can liquidate more than strictly necessary

            if (rounds > MIN_ROUNDS && cumulLiquidatedQuotes_ >= _minCanceledDebt) break;
        }

        // console.log("      Exit loops over positions to be closed");

        // update pool's bottom position (first row at which a position potentially exists)
        pool.bottomPosition += rounds;

        // console.log("   ** Exit _liquidatePositions **");
    }

    /// @notice cancel full debt of one position
    /// write off collateral assets for the exact amount
    /// @return liquidatedAssets_ 
    
    function _closePosition(uint256 positionId)
        internal
        returns (uint256 liquidatedAssets_)
    {
        // console.log("         * _closePosition *");

        uint256 poolId = positions[positionId].poolId;
        
        // add interest rate to borrowed quantity
        // update TWIR_t to TWIR_T to reset interest rate to zero
        _addInterestRateToPosition(positionId);

        liquidatedAssets_ = positions[positionId].borrowedAssets;

        // console.log("            Total borrowed assets in pool before liquidation :", pools[poolId].borrows / WAD, "USDC");
        // console.log("            liquidated borrowed assets (in full) :", liquidatedAssets_ / WAD, "USDC");

        // decrease borrowed assets in pool's total borrow
        pools[poolId].borrows = _substract(pools[poolId].borrows, liquidatedAssets_, "err_02", !RECOVER);

        // console.log("            Remaining assets in pool after liquidation :", pools[poolId].borrows / WAD, "USDC");

        // decrease borrowed assets to zero
        positions[positionId].borrowedAssets = 0;

        // console.log("         * Exit _closePosition *");
    }

    /// @notice close buy orders for exact amount of liquidated quote assets and taken quote quantity in same pool
    
    function _closeBuyOrders(
        uint256 _poolId,
        uint256 _amountToClose
    )
        internal
        returns (uint256 closedAmount_)    
    {
        // console.log("   ** _closeOrders **");
        
        Pool storage pool = pools[_poolId];
        
        // console.log("      Amount in buy orders to close :", _amountToClose / WAD, "USDC");
        
        // remaining (quote) assets to redeem against canceled debt
        uint256 remainingToClose = _amountToClose;

        // number of closing iterations
        uint256 closingRound = 0;

        // iterate on order id in pool's orderIds from bottom to top
        // pool.topOrder is first available slot for orders in pool's orderIds
        // pool.bottomOrder is first possible slot for orders to be seized
        // pool.bottomOrder == pool.topOrder means that there is noting more to seize

        for (uint256 row = pool.bottomOrder; row < pool.topOrder; row++) {

            // console.log("      Enter loop over buy orders to close");
            
            closingRound ++;
            // console.log("         closingRound :", closingRound);
            
            // which order in pool is closed
            uint256 orderId = pool.orderIds[row];

            // console.log("         orderId :", orderId);

            uint256 orderSize = orders[orderId].quantity;

            // console.log("         orderSize :", orderSize / WAD, "USDC");

            // if user has no deposits in pool, skip
            if (orderSize == 0) continue;

            // add interest rate to deposit, reset interest rate to zero (check update aggregates has been called)
            _addInterestRateToDeposit(orderId);

            // collect assets from deposit against debt deletion or taker's demand
            
            // if deposit exceeds remaining to close, some assets will remain in deposit
            // otherwise, deposit' assets are fully depleted

            uint256 closedAssets = remainingToClose.minimum(orderSize);

            // console.log("         closedAssets :", closedAssets / WAD, "USDC");

            remainingToClose -= closedAssets;

            // console.log("         pools.deposits before closing assets :", pools[_poolId].deposits / WAD, "USDC");

            // decrease pool's total deposits (check no asset mismatch)
            pools[_poolId].deposits -= closedAssets;

            // console.log("         pools.deposits after closing assets :", pools[_poolId].deposits / WAD, "USDC");

            // decrease assets in order, possibly down to zero
            orders[orderId].quantity -= closedAssets;

            // base assets received by maker
            uint256 makerReceivedAssets = _convert(closedAssets, limitPrice[_poolId], IN_QUOTE, !ROUNDUP);
        
            // console.log("         maker received assets after conversion :", makerReceivedAssets / WAD, "ETH");

            // Place base assets in a sell order on behalf of maker
            _repostLiquidity(orders[orderId].maker, _poolId, orderId, makerReceivedAssets);

            // exit iteration on orders if all debt has been redeemed and take size is fully filled
            if (remainingToClose == 0) break;

            // console.log("      Exit loop over orders to close");
        }

        // update pool's bottom order (first row at which an order potentially exists)
        pool.bottomOrder += closingRound - 1;

        closedAmount_ = _amountToClose - remainingToClose;

        // console.log("      total amount closed :", closedAmount_ / WAD, "USDC");

        // console.log("   ** Exit _closeOrders **");
    }

    /// when a pool in base tokens is taken, orders are taken in batches
    /// for every sell order taken, if serves as collateral, close borrowing positions for equivalent amount
    /// _reduceUserDebt(): if order is collateral, repay debt with quote tokens received from taker, deposit remaining quote assets in user's account
    /// _repostLiquidity(): if not, repost received quote tokens received in buy order at ??
    
    function _takeSellOrders(
        uint256 _poolId,
        uint256 _takenQuantity
    )
        internal
        returns (uint256 totalTaken_)
    {
        // remaining base assets to take until exact amount of reduced deposits is reached
        uint256 remainingAssetsToTake = _takenQuantity;

        // number of closing iterations
        uint256 closingRound = 0;

        // iterate on order id in pool's orderIds from bottom to top

        for (uint256 row = pools[_poolId].bottomOrder; row < pools[_poolId].topOrder; row++) {

            closingRound ++;

            // console.log("   Closing round: ", closingRound);
            
            // which sell order in pool is closed
            uint256 orderId = pools[_poolId].orderIds[row];

            // console.log("   Closed order id: ", orderId);

            uint256 orderSize = orders[orderId].quantity;

            // console.log("   Size * 100 of closed order: ", 100 * orderSize / WAD, " ETH");

            address user = orders[orderId].maker;

            // check user has still deposits in pool
            if (orderSize == 0) continue;

            uint256 takenAssets = remainingAssetsToTake.minimum(orderSize);

            // console.log("   Taken assets * 100: ", 100 * takenAssets / WAD, " ETH");

            remainingAssetsToTake -= takenAssets;

            // decrease pool's total deposits
            pools[_poolId].deposits -= takenAssets;

            // decrease assets in order, possibly down to zero
            orders[orderId].quantity -= takenAssets;

            // quote assets received by maker of sell order *before* debt repayment
            uint256 makerReceivedAssets = _convert(takenAssets, limitPrice[_poolId], !IN_QUOTE, !ROUNDUP);
            
            // when a sell order is taken, the quote assets received serve in priority to pay back maker's own borrow
            
            // check if user has borrowing psotion(s)
            // then reduce position(s) possibly as low as zero and as high as makerReceivedAssets

            uint256 repaidDebt = _reduceUserDebt(user, makerReceivedAssets);

            // console.log("   repaid debt: ", repaidDebt / WAD, " USDC");

            // place quote assets in:
            // - buy order on behalf of maker if pure lender (identified by repaid debt = 0)
            // - user's account if borrower

            if (repaidDebt == 0) _repostLiquidity(user, _poolId, orderId, makerReceivedAssets);

            else users[user].quoteAccount += makerReceivedAssets - repaidDebt;

            // exit loop if take size is fully filled
            if (remainingAssetsToTake == 0) break;
        }

        // update pool's bottom order (first row at which an order potentially exists)
        pools[_poolId].bottomOrder += closingRound - 1;

        // totalTaken might be less than _takenQuantity once all sell orders in pool are taken
        totalTaken_ = _takenQuantity - remainingAssetsToTake;
    }

    /// @notice Repost converted assets on the other side of the book
    /// applies to all buy orders and sell orders originating from lenders
    /// never used for borrowers
    /// @param _poolId: origin pool before replacement
    /// @param _orderId: origin order before replacement
    /// @param _quantity: amount reposted in destination order
    
    function _repostLiquidity(
        address _user,
        uint256 _poolId,
        uint256 _orderId,
        uint256 _quantity
    )
        internal
    {
        // type of destination limit order (opposite to origin order)
        bool isBuyOrder = !_isQuotePool(_poolId);

        // console.log("            * _repostLiquidity *");
        // console.log("            Is new order a buy order:", isBuyOrder);

        uint256 pairedPoolId = orders[_orderId].pairedPoolId;
        
        // in buy order market, update pool's total borrow and total deposits
        // increment TWIR and TUWIR before accounting for changes in UR and future interest rate

        if (isBuyOrder) _addInterestRateToPoolBorrowAndDeposits(_poolId);
        
        // check if an identical order to reposted order exists with same paired pool id
        // if so increase deposit, else create
        // if several deposits in same paired pool id exists with different opposite pool id, take the first one
        // here paired pool id of reposted order is set to zero, which is handled in the call

        uint256 pairedOrderId_ = getOrderIdInDepositIdsOfUser(_user, pairedPoolId, 0);

        // console.log("               Paired order id found :", pairedOrderId_);

        // if new order id, create sell order

        if (pairedOrderId_ == 0) {
        
            // add new orderId in depositIds[] in users
            // add new orderId on top of orderIds[] in pool
            // increment topOrder
            // return new order id

            // console.log("               ** _createOrder **");
            // console.log("                  Destination pool id :", pairedPoolId);
            
            // erreur ? isBuyOrder? _poolId - 3 : _poolId + 3,
            
            pairedOrderId_ = _createOrder(pairedPoolId, _user, _poolId, _quantity);

            // console.log("               ** Exit _createOrder **");
        }
        
        // if order exists (even with zero quantity)
        
        else {

            // if buy order market, add interest rate to existing deposit
            // update TUWIR_t to TUWIR_T to reset interest rate to zero (check for update aggregates)

            if (isBuyOrder) _addInterestRateToDeposit(pairedOrderId_);
            
            // add new quantity to existing deposit
            orders[pairedOrderId_].quantity += _quantity;
        }

        // increase pool's total deposits (double check asset type before)

        // console.log("               total deposit in paired pool before order quantity update:", pools[orders[pairedOrderId_].poolId].deposits / WAD);

        pools[orders[pairedOrderId_].poolId].deposits += _quantity;

        // console.log("               total deposit in paired pool after order quantity update:", pools[orders[pairedOrderId_].poolId].deposits / WAD);
        // console.log("            * Exit _repostLiquidity *");
    }
    
    /// When a buy order is taken, all positions which borrow from it are closed
    /// For every closed position, an exact amount of collateral is seized
    /// Collateral is in user's account and possibly in multiple sell orders:
    ///  - start by user's account then iterate on borrower's sell orders to write off collateral
    ///  - stop when borrower's debt is fully canceled
    ///  - change internal balances
    /// ex: Bob deposits 1 ETH in two sell orders to borrow 4000 from Alice's buy order (p = 2000)
    /// Alice's buy order is taken => seized Bob's collateral is 4000/p = 2 ETH spread over 2 orders
    /// interest rate has been added to position before callling _seizeCollateral
    /// returns seized collateral in base tokens which is normally equal to collateral to seize

    function _seizeCollateral(
        address _borrower,
        uint256 _collateralToSeize
    )
        internal
        returns (uint256 seizedAmount_)
    {
        // console.log("         * _seizeCollateral *");
        
        uint256 remainingToSeize = _collateralToSeize;
        
        uint256 seizedCollateral = remainingToSeize.minimum(users[_borrower].baseAccount);

        users[_borrower].baseAccount -= seizedCollateral;

        remainingToSeize -= seizedCollateral;

        // if amount to seize is larger than collateral in user's account, start looking for in sell orders
        
        if (remainingToSeize > 0) {

            uint256[MAX_ORDERS] memory depositIds = users[_borrower].depositIds;

            for (uint256 j = 0; j < MAX_ORDERS; j++) {

                // console.log("            Enter loop over borrower's sell orders to seize");
                
                uint256 orderId = depositIds[j];
                // console.log("               next order id to seize assets :", orderId);

                if (
                    orders[orderId].quantity > 0 &&
                    _isQuotePool(orders[orderId].poolId) != IN_QUOTE
                )
                {
                    // console.log("               collateral in order before seizing :", orders[orderId].quantity / WAD, "ETH");
                    
                    seizedCollateral = remainingToSeize.minimum(orders[orderId].quantity);
                    // console.log("               seizedCollateral :", seizedCollateral / WAD, "ETH");

                    orders[orderId].quantity -= seizedCollateral;
                    // console.log("               remaining collateral in order after seizing :", orders[orderId].quantity / WAD, "ETH");

                    remainingToSeize -= seizedCollateral;

                    // console.log("               pool.deposits before seizing :", pools[orders[orderId].poolId].deposits / WAD, "ETH");
                    pools[orders[orderId].poolId].deposits -= seizedCollateral;
                    // console.log("               pool.deposits after seizing :", pools[orders[orderId].poolId].deposits / WAD, "ETH");
                }

                if (remainingToSeize == 0) break;
            }
        }

        // console.log("            Exit loop over borrower's sell orders");
        
        seizedAmount_ = _collateralToSeize - remainingToSeize;
        // console.log("            seizedAmount_ (total amount seized) :", seizedAmount_ / WAD, "ETH");

        // console.log("         Exit _seizeCollateral()");
    }

    /// reduce user's borrowing positions possibly as high as _maxReduce
    /// - iterate on user's borrowing positions
    /// - close positions as they come
    /// - stop when all positions have been closed or _maxReduced is reached
    /// - change internal balances in quote tokens
    /// @return reducedUserDebt_ : total amount of reduced debt <= _maxReduce
    
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
                // update total borrows and deposits of pool where debt is reduced with interest rate
                _addInterestRateToPoolBorrowAndDeposits(position.poolId);

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

    /// @notice  tranfer ERC20 from contract to user/taker/borrower

    function _transferTo(
        address _to,
        uint256 _quantity,
        bool _isBuyOrder
    )
        internal
    {
        if (_isBuyOrder) quoteToken.safeTransfer(_to, _quantity);
        else baseToken.safeTransfer(_to, _quantity);
    }
    
    /// @notice transfer ERC20 from user/taker/repayBorrower to contract

    function _transferFrom(
        address _from,
        uint256 _quantity,
        bool _inQuote
    )
        internal
    {
        if (_inQuote) quoteToken.safeTransferFrom(_from, address(this), _quantity);
        else baseToken.safeTransferFrom(_from, address(this), _quantity);
    }

    /// @notice add new orderId in depositIds[] in users
    /// take the first available slot in array
    /// revert if max orders reached

    function _insertOrderIdInDepositIdsInUser(
        address _user,
        uint256 _orderId
    )
        internal
    {
        bool fillRow = false;
        
        // console.log("                     Enter loop for first available slot in user's depositIds[]");
        
        for (uint256 i = 0; i < MAX_ORDERS; i++) {

            uint256 orderId = users[_user].depositIds[i];

            if (orders[orderId].quantity == 0) {
                users[_user].depositIds[i] = _orderId;
                // console.log("                        First row available in depositIds[] :", i, "over", MAX_ORDERS);
                fillRow = true;
                break;
            }
        }

        // console.log("                     Exit loop");
        
        if (!fillRow) revert("Max orders reached");
    }

    /// @notice add position id in borrowIds[] in mapping users
    /// reverts if user's max number of positions reached

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

    /// @notice add order id on top of orderIds in pool
    /// make sure order id does not already exist in ordersIds

    function _addOrderIdToOrderIdsInPool(
        uint256 _poolId,
        uint256 _orderId
    )
        internal
    {
        // console.log("                     top order of pool before insertion:", pools[_poolId].topOrder);
        // console.log("                     order id inserted in pool's orderIds[]:", _orderId);

        pools[_poolId].orderIds[pools[_poolId].topOrder] = _orderId;
        pools[_poolId].topOrder ++;
        // console.log("                     pool's top order after insertion:", pools[_poolId].topOrder);
    }

    /// @notice add position id to borrowIds[] in users
    /// add position id to borrows[] in pools
    /// revert if max position
    /// @param _poolId: pool id from which assets are borrowed
    /// return newPositionId_ existing or new position id
    
    function _createPosition(
        uint256 _poolId,
        address _borrower,
        uint256 _quantity
    )
        internal
        returns (uint256 newPositionId_)
    {
        uint256 subWeightedRate = 1;

        if (_isQuotePool(_poolId)) subWeightedRate = pools[_poolId].timeWeightedRate;
        
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
    
    /// @notice update pool's total borrow and total deposits by adding respective interest rates
    /// pool is necessarily in quote tokens
    /// increment TWIR for borrow rate and TUWIR for lending rate to update interest rates for next call
    /// general sequencing of any function calling addInterestRateToPoolBorrowAndDeposits:
    /// - update quantities by adding interest rate based on UR valid before call
    /// - update quantities following function execution (deposit, withdraw, borrow, repay, take, repost ...)

    function _addInterestRateToPoolBorrowAndDeposits(uint256 _poolId)
        internal
    {
        // console.log("Enter _addInterestRateToPoolBorrowAndDeposits()");

        // TWIR_{t-1} time-weighted interest rate from inception to present (in WAD)
        // TWIR_{t-2} = IR_0 n_1/N + IR_1 (n_2 - n_1)/N + ... + IR_{t-1} (n_{t-2} - n_{t-1})/N
        // TWIR_{t-1} = IR_0 n_1/N + IR_1 (n_2 - n_1)/N + ... + IR_{t-2} (n_{t-1} - n_{t-2})/N + IR_{t-1} (n_t - n_{t-1})/N
        
        // console.log("   pools[_poolId].lastTimeStamp : ", pools[_poolId].lastTimeStamp);
        
        uint256 _getPoolDeltaTimeWeightedRate = getPoolDeltaTimeWeightedRate(_poolId);
        
        pools[_poolId].timeWeightedRate += _getPoolDeltaTimeWeightedRate;

        // console.log("   updated pools[_poolId].timeWeightedRate :  ", _getPoolDeltaTimeWeightedRate);

        // add interest rate to time- and UR-weighted interest rate
        pools[_poolId].timeUrWeightedRate += _getPoolDeltaTimeWeightedRate.wMulDown(viewUtilizationRate(_poolId));

        // console.log("   updated pools[_poolId].timeUrWeightedRate :", pools[_poolId].timeUrWeightedRate);

        // add interest rate exp[ (n_t - n_{t-1}) * IR_{t-1} / N ] - 1 to total borrow in pool

        uint256 poolBorrow = pools[_poolId].borrows;

        pools[_poolId].borrows = poolBorrow + _getPoolDeltaTimeWeightedRate.wTaylorCompoundedUp().wMulDown(poolBorrow);

        // console.log("   update pools[_poolId].borrows : ", pools[_poolId].borrows);

        // add interest rate to total deposits in pool

        uint256 poolDeposit = pools[_poolId].deposits;

        uint256 deltaTimeUrWeightedRate = 
            _getPoolDeltaTimeWeightedRate.wMulDown(viewUtilizationRate(_poolId));

        pools[_poolId].deposits = poolDeposit + deltaTimeUrWeightedRate.wTaylorCompoundedUp().wMulDown(poolDeposit);

        // console.log("   updated pools[_poolId].deposits : ", pools[_poolId].deposits / WAD);

        // reset clock
        pools[_poolId].lastTimeStamp = block.timestamp;

        // console.log("Exit _addInterestRateToPoolBorrowAndDeposits()");
    }

    /// @notice calculate and add accrued interest rate to borrowed quantity
    /// update TWIR_t to TWIR_T to reset cumulated interest rate to zero
    /// _addInterestRateToPoolBorrowAndDeposits() has been called before
    
    function _addInterestRateToPosition(uint256 _positionId)
        internal
    {
        // console.log("borrowed amount before interest rate:", positions[_positionId].borrowedAssets / WAD, "USDC");
        
        // multiply interest rate with borrowed quantity and add to borrowed quantity
        positions[_positionId].borrowedAssets = viewUserBorrow(_positionId);

        // console.log("borrowed amount + interest rate :", positions[_positionId].borrowedAssets / WAD, "USDC");

        // update TWIR_t to TWIR_T in position to reset borrowing interest rate to zero
        // assumes timeWeightedRate has been updated before
        
        positions[_positionId].positionWeightedRate = pools[positions[_positionId].poolId].timeWeightedRate;
    }
    
    /// @notice calculate accrued interest rate and add to deposit
    /// update TUWIR_t to TUWIR_T to reset interest rate to zero
    /// _addInterestRateToPoolBorrowAndDeposits() has been called before
    
    function _addInterestRateToDeposit(uint256 _orderId)
        internal
    {
        // console.log("Enter _addInterestRateToDeposit");
        // console.log("   Order size before interest rate :", orders[_orderId].quantity / WAD, " USDC");
        
        // add interest rate multiplied by existing quantity to deposit
        orders[_orderId].quantity = viewUserQuoteDeposit(_orderId);

        // console.log("   Order size after interest rate :", orders[_orderId].quantity / WAD, " USDC");

        // update TUWIR_t to TUWIR_T to reset interest rate to zero
        // assumes timeUrWeightedRate has been updated before

        orders[_orderId].orderWeightedRate = pools[orders[_orderId].poolId].timeUrWeightedRate;

        // console.log("Exit _addInterestRateToDeposit");
    }
    
    // /// @notice update user's orders by adding interest rate to deposits before calculating required collateral
    // /// as quote assets in eligible buy orders may count as collateral
    // /// only deposits in buy orders accrue interest rate
    
    // function _addInterestRateToUserDeposits(address _user)
    //     internal
    // {
    //     uint256[MAX_ORDERS] memory orderIds = users[_user].depositIds;
    //     for (uint256 i = 0; i < MAX_ORDERS; i++) {

    //         uint256 orderId = orderIds[i];      // position id from which user borrows assets

    //         // look for buy order deposits to calculate interest rate
    //         if (_isQuotePool(orders[orderId].poolId) && orders[orderId].quantity > 0) {

    //             // update pool's total borrow and total deposits
    //             // increment TWIR/TUWIR before changes in pool's UR and calculating user's excess collateral
    //             _addInterestRateToPoolBorrowAndDeposits(orders[orderId].poolId);
                
    //             // add interest rate to deposit, update TWIR_t to TWIR_T to reset interest rate to zero
    //             _addInterestRateToDeposit(orderId);
    //         }
    //     }
    // }

    // function _addInterestRateToUserPositions(address _borrower)
    //     internal
    // {
    //     uint256[MAX_POSITIONS] memory borrowIds = users[_borrower].borrowIds;

    //     for (uint256 i = 0; i < MAX_POSITIONS; i++) {

    //         Position memory position = positions[borrowIds[i]];
            
    //         // look for borrowing positions to calculate required collateral
    //         if (position.borrowedAssets > 0) {

    //             // update pool's total borrow and total deposits
    //             // increment TWIR/TUWIR before changes in pool's UR and calculating user's excess collateral
    //             _addInterestRateToPoolBorrowAndDeposits(position.poolId);
                
    //             // add interest rate to borrowed quantity, update TWIR_t to TWIR_T to reset interest rate to zero
    //             _addInterestRateToPosition(borrowIds[i]);
    //         }
    //     }
    // }

    /// @notice check if pool has a price
    /// return priceExists_
    /// If no price, generate one on the fly if not too far from an existing pool (stepMax left and right)
    /// else return false
    
    function _priceExists(uint256 _poolId)
        internal
        returns (bool priceExists_)
    {
        // console.log("check _poolId in priceExists() : ", _poolId);
        // console.log("limitPrice[_poolId] before creation: ", limitPrice[_poolId] / WAD);

        // max number of price steps to create a new pool
        uint256 stepMax = 5;
               
        // if no defined price for the pool, search left and right further and further away
  
        if (limitPrice[_poolId] == 0) {
            for (uint256 step = 1; step <= stepMax; step++) {
                if (limitPrice[_poolId - step] > 0) {
                    for (uint256 i = step; i > 0; i--) {
                        if ((_poolId - i + 1) % 2 == 0) {
                            limitPrice[_poolId - i + 1] = limitPrice[_poolId - i].wMulDown(priceStep);
                        } else {
                            limitPrice[_poolId - i + 1] = limitPrice[_poolId - i];
                        }  
                    }
                    break;
                }
                else if (limitPrice[_poolId + step] > 0) {
                    for (uint256 i = step; i > 0; i--) {
                        if ((_poolId + i) % 2 == 0) {
                            limitPrice[_poolId + i - 1] = limitPrice[_poolId + i].wDivDown(priceStep);
                        } else {
                            limitPrice[_poolId + i - 1] = limitPrice[_poolId + i];
                        }  
                    }
                    break;
                }
            }
        }

        priceExists_ = (limitPrice[_poolId] > 0);

        // console.log("limitPrice[_poolId] after creation: ", limitPrice[_poolId] / WAD);
    }


    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  INTERNAL VIEW FUNCTIONS                   */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
    
    /// @notice check that taking assets in pool is profitable
    /// if buy order, price feed must be lower than limit price
    /// if sell order, price feed must be higher than limit price
    
    function getIsProfitable(uint256 _poolId)
        internal view
        returns (bool)
    {
        // console.log("priceFeed in profitable() :", priceFeed / WAD);
        
        if (_isQuotePool(_poolId)) return (priceFeed < limitPrice[_poolId]);
        else return (priceFeed > limitPrice[_poolId]);
    }

    /// @notice check asset type of pool by checking asset type of bottom order in the queue with positiove assets

    function getHasPoolAssets(uint256 _poolId)
        internal view
        returns (bool)
    {
        return (pools[_poolId].deposits > 0);
    }

    /// @return false if desired quantity cannot be withdrawn
    /// @notice removed quantity must be either full deposit + interest rate if quote assets
    /// or not too large to keep min deposit and avoid dust

    function getRemovableFromOrder(
        uint256 _orderId,
        uint256 _quantity // removed quantity
    )
        internal view
        returns (bool)
    {
        // console.log("Enter removableFromOrder");
        
        bool isBuyOrder = _isQuotePool(orders[_orderId].poolId);
        uint256 available = isBuyOrder ? viewUserQuoteDeposit(_orderId) : orders[_orderId].quantity;
        
        // console.log("   Quantity available in order   :", available);
        // console.log("   Quantity withdrawn from order :", _quantity);
        // console.log("   _quantity == available :", _quantity == available);
        // console.log("   _quantity + viewMinDeposit(isBuyOrder) < available :", _quantity + viewMinDeposit(isBuyOrder) < available);
        // console.log((_quantity == available) || (_quantity + viewMinDeposit(isBuyOrder) < available));

        // console.log("Exit removableFromOrder");

        if (_quantity == available || _quantity + viewMinDeposit(isBuyOrder) < available) return true;
        else return false;
    }

    /// @return false if desired quantity cannot be withdrawn from pool
    /// @notice removed quantity must be either full liquidity in pool + interest rate if quote assets
    /// or not too large to keep min deposit and allow take

    function getIsRemovableFromPool(
        uint256 _poolId,
        uint256 _removedQuantity
    )
        internal view
        returns (bool)
    {
        if (pools[_poolId].borrows == 0 || _removedQuantity <= viewPoolAvailableAssets(_poolId))
            return true;
        else return false;
    }

    /// @notice return orderId_ if order with same paired pool exists in pool, even with zero quantity
    /// returns 0 if doesn't exist
    /// Search for an existing order may be in buy order pools or sell order pools
    /// maker can create several deposits in same pool with different paired price,
    /// but only one deposit with same pool id and paired pool id (to check)
    /// when used to replace order, no paired pool id is defined in new order,
    /// in this case, _pairedPoolId is set to 0
    /// then search for a first deposit with any opposite paired pool id and select the first one
    
    function getOrderIdInDepositIdsOfUser(
        address _user,
        uint256 _poolId,
        uint256 _pairedPoolId
    )
        internal view
        returns (uint256 orderId_)
    {
        orderId_ = 0;
        uint256[MAX_ORDERS] memory depositIds = users[_user].depositIds;

        for (uint256 i = 0; i < MAX_ORDERS; i++) {
            Order memory order = orders[depositIds[i]];
            if (
                _poolId == order.poolId && (_pairedPoolId == 0 || _pairedPoolId == order.pairedPoolId) 
            ){
                orderId_ = depositIds[i];
                break;
            }
        }
    }

    /// @notice get position id from borrowIds[] in user, even if has zero quantity
    /// return positionId_ which is 0 if not found

    function getPositionIdInborrowIdsOfUser(
        address _borrower,
        uint256 _poolId
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
    
    /// @notice compute pool's cumulated borrowing interest rate between t and T
    /// 1$ borrowed accumulates (exp(TWIR_T - TWIR_t) - 1) interest rate between t and T
    /// exp(TWIR_T - TWIR_t) - 1 is computed using a 3rd order Taylor approximation

    function getPoolDeltaTimeWeightedRate(uint256 _poolId)
        internal view
        returns (uint256)
        {
        
        // console.log("         Enter getPoolDeltaTimeWeightedRate(_poolId)");
        // console.log("            block.timestamp: ", block.timestamp);
        // console.log("            pools[_poolId].lastTimeStamp) : ", pools[_poolId].lastTimeStamp);
        // console.log("            Time passed in second :", (block.timestamp - pools[_poolId].lastTimeStamp).maximum(0));

        // compute (n_t - n_{t-1}) * IR_{t-1} / N
        // (n_t - n_{t-1}) number of seconds since last update, N number of seconds in a year (integer)
        // IR_{t-1} annual interest rate, IR_{t-1} / N instant rate

        uint256 elapsedTime = (block.timestamp - pools[_poolId].lastTimeStamp).maximum(0);

        // console.log("         Exit getPoolDeltaTimeWeightedRate(_poolId)");
        
        return elapsedTime.mulDivUp(viewBorrowingRate(_poolId), YEAR);
    }
        
    /// @notice compute pool's cumulated lending interest rate between t and T

    function getPoolDeltaTimeUrWeightedRate(uint256 _poolId)
        internal view
        returns (uint256)
    {        
        // returns IR_{t-1} (n_t - n_{t-1})/N * UR_{t-1}
        
        return getPoolDeltaTimeWeightedRate(_poolId).wMulDown(viewUtilizationRate(_poolId));
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  PUBLIC VIEW FUNCTIONS                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
  
    // /// @return user.depositIds the fixed-size array of user's order id
    
    // function viewUserDepositIds(address _user)
    //     public view
    //     returns (uint256[MAX_ORDERS] memory)
    // {
    //     User memory user = users[_user];
    //     return (user.depositIds);
    // }
    
    // /// @return user.borrowIds the fixed-size array of user's position id
    
    // function viewUserBorrowIds(address _user)
    //     public view
    //     returns (uint256[MAX_POSITIONS] memory)
    // {
    //     User memory user = users[_user];
    //     return (user.borrowIds);
    // }
    
    /// @return pool's available assets left to borrow
    /// @notice pool's available assets are sum deposits, scaled down by PHI - sum of borrow
    
    function viewPoolAvailableAssets(uint256 _poolId)
        public view
        returns (uint256)
    {
        return (PHI.wMulDown(pools[_poolId].deposits) - pools[_poolId].borrows).maximum(0);
    }

    /// @notice UR = total borrow / total net assets in pool (in WAD)
    /// should be called before any viewUserExcessCollateral()
    /// utilization rate is necessarily zero at first otherwise, lenders start accumulate non-existent rewards

    function viewUtilizationRate(uint256 _poolId)
        public view
        returns (uint256 utilizationRate_)
    {
        uint256 poolDeposits = pools[_poolId].deposits;
        if (poolDeposits == 0) utilizationRate_ = 0;
        else utilizationRate_ = pools[_poolId].borrows.mulDivUp(WAD, poolDeposits);

        // console.log("      viewutilizationRate 1e4 : ", 1e4 * utilizationRate_ / WAD);
    }

    // view current annualized borrowing interest rate for pool

    function viewBorrowingRate(uint256 _poolId)
        public view
        returns (uint256)
    {
        return ALPHA + BETA.wMulDown(viewUtilizationRate(_poolId));
    }

    // view annualized lending rate for pool, which is borrowing interest rate multiplied by UR
    // if zero borrow, UR is marked as 0.5 for computing interest rate but lending rate must be zero

    function viewLendingRate(uint256 _poolId)
        public view
        returns (uint256)
    {
        if (pools[_poolId].borrows > 0)
            return viewBorrowingRate(_poolId).wMulDown(viewUtilizationRate(_poolId));
        else return 0;
    }

    /// add interest rate exp[ (n_t - n_{t-1}) * IR_{t-1} / N ] - 1 to pool's total borrow
    
    function viewPoolBorrow(uint256 _poolId)
        public view
        returns (uint256)
    {
        uint256 poolBorrow = pools[_poolId].borrows;
        return poolBorrow + getPoolDeltaTimeWeightedRate(_poolId).wTaylorCompoundedUp().wMulDown(poolBorrow);
    }

    function viewPoolDeposit(uint256 _poolId)
        public view
        returns (uint256)
    {
        uint256 poolDeposit = pools[_poolId].deposits;

        uint256 deltaTimeUrWeightedRate = 
            getPoolDeltaTimeWeightedRate(_poolId).wMulDown(viewUtilizationRate(_poolId));

        return poolDeposit + deltaTimeUrWeightedRate.wTaylorCompoundedUp().wMulDown(poolDeposit);
    }
    
    /// @notice compute interest rate since start of borrowing position between t and T
    /// assumes pools[_poolId].timeWeightedRate is up to date 
    /// 1$ borrowed accumulates (exp(TWIR_T - TWIR_t) - 1) interest rate between t and T
    /// exp(TWIR_T - TWIR_t) - 1 is computed using a 3rd order Taylor approximation
    /// pool's timeWeightedRate is not necessarily up-to-date
    
    function viewUserBorrow(uint256 _positionId)
        public view
        returns (uint256)
    {
        uint256 _poolId = positions[_positionId].poolId;
        
        uint256 rateDiff = pools[_poolId].timeWeightedRate
            + getPoolDeltaTimeWeightedRate(_poolId)
            - positions[_positionId].positionWeightedRate;

        // multiply interest rate with borrowed quantity and add to borrowed quantity

        uint256 userBorrow = positions[_positionId].borrowedAssets;
        return userBorrow + rateDiff.wTaylorCompoundedUp().wMulUp(userBorrow);
    }

    /// @notice compute interest rate since start of lending position between t and T
    /// assumes pools[_poolId].timeUrWeightedRate is up to date
    /// 1$ lent accumulates (exp(TUWIR_T - TUWIR_t) - 1) interest rate between t and T
    /// exp(TUWIR_T - TUWIR_t) - 1 is computed using a 3rd order Taylor approximation
    /// pool's timeUrWeightedRate not necessarily up-to-date

    function viewUserQuoteDeposit(uint256 _orderId)
        public view
        returns (uint256)
    {
        // console.log("   Enter viewUserQuoteDeposit(uint256 _orderId)");
        
        uint256 _poolId = orders[_orderId].poolId;
        
        // console.log("         pools[_poolId].timeUrWeightedRate :", pools[_poolId].timeUrWeightedRate);
        // console.log("         orders[_orderId].orderWeightedRate :", orders[_orderId].orderWeightedRate);

        uint256 rateDiff = pools[_poolId].timeUrWeightedRate
            + getPoolDeltaTimeUrWeightedRate(_poolId)
            - orders[_orderId].orderWeightedRate;

        // multiply interest rate with deposit and add to deposit

        // console.log("   Exit viewUserQuoteDeposit(uint256 _orderId)");
        
        uint256 userQuoteDeposit = orders[_orderId].quantity;
        return userQuoteDeposit + rateDiff.wTaylorCompoundedDown().wMulUp(userQuoteDeposit);
    }

    // sum all assets deposited by a given user in quote or base token in orders and user's account
    // remark : several deposits with different paired pool id can be in the same pool 
    // (not true for borrowers, unclear for lenders)

    function viewUserTotalDeposits(
        address _user,
        bool _inQuote
    )
        public view
        returns (uint256 totalDeposit_)
    {
        uint256[MAX_ORDERS] memory depositIds = users[_user].depositIds;

        if (!_inQuote) totalDeposit_ = users[_user].baseAccount;
        
        for (uint256 i = 0; i < MAX_ORDERS; i++) {

            if (_isQuotePool(orders[depositIds[i]].poolId) == _inQuote) {

                totalDeposit_ = _inQuote
                    ? viewUserQuoteDeposit(depositIds[i])
                    : orders[depositIds[i]].quantity;
            }   
        }
    }

    /// @notice aggregate required collateral over all borrowing positions
    /// composed of borrows + borrowing rate, converted at limit prices
    /// returns required collateral in base assets needed to secure user's debt in quote assets 

    function viewUserRequiredCollateral(address _borrower)
        public view
        returns (uint256 requiredCollateral_)
    {
        // console.log("      Enter __userRequiredCollateral()");
        
        requiredCollateral_ = 0;

        uint256[MAX_POSITIONS] memory borrowIds = users[_borrower].borrowIds;

        for (uint256 i = 0; i < MAX_POSITIONS; i++) {

            uint256 id = borrowIds[i];
            
            // look for borrowing positions to calculate required collateral
            if (positions[id].borrowedAssets > 0) {

                // console.log("         Borrowed assets of position i: ", positions[id].borrowedAssets / WAD, "USDC");
                
                // how much required collateral in base assets for borrowed amount in quote assets
                requiredCollateral_ += _convert(
                    viewUserBorrow(id),
                    limitPrice[positions[id].poolId],
                    IN_QUOTE,
                    ROUNDUP
                );

                // console.log("         Sum of required collateral x 100 so far: ", 100 * requiredCollateral_ / WAD, "ETH");
            }
        }

        // console.log("      Exit __userRequiredCollateral()");
    }

    /// @notice return excess collateral (EC) in base tokens after deduction of _minusCollateral (MC)
    /// Solvency means total collateral (TC) > (required collateral (RC) from total borrow) / LLTV
    /// EC must stay positive after MC is deduced
    /// MC can originate from withdraw collateral assets or borrow more quote assets
    /// If withdraw collateral :     EC = (TC - MC) - RC/LLTV > 0
    /// If borrow more quote assets: EC = TC - (RC + MC)/LLTV = TC - RC/LLTV - MC' = (TC - MC') - RC/LLTV > 0
    /// In last case, MC' is scaled up by LLTV before getUserCollateral() is called
    /// RC, if any, is computed with interest rate added to borrow, 
    /// which is done before call, no need to call _addInterestRateToPoolBorrowAndDeposits() before
    /// @return isPositive_ is true if user is solvent and false if insolvent
    /// @return excessCollateral_ is always a non-negative number and gives excess or gap in solvency (careful!)

    function viewUserExcessCollateral(
        address _user,
        uint256 _minusCollateral
    )
        public view
        returns (
            bool isPositive_,
            uint256 excessCollateral_
        )
    {
        // console.log("   Enter viewUserExcessCollateral()");

        // net collateral in base (collateral) tokens :
        // sum all user's deposits in collateral (base) tokens (on accruing interest rate)

        uint256 netCollateral = viewUserTotalDeposits(_user, !IN_QUOTE) - _minusCollateral;
        uint256 userRequiredCollateral = viewUserRequiredCollateral(_user).wDivUp(liquidationLTV);

        // console.log("      Scaled up total required collateral e02: ", 100 * userRequiredCollateral / WAD, "ETH");
        // console.log("      (Total deposit - reduced collateral) e02 :", 100 * netCollateral / WAD, "ETH");
        // console.log("      Post-action required collateral e02:", 100 * userRequiredCollateral / WAD, "ETH");

        // is user EC > 0 return EC, else return - EC
        if (netCollateral >= userRequiredCollateral) {
            isPositive_ = true;
            excessCollateral_ = netCollateral - userRequiredCollateral;
        }
        else excessCollateral_ = userRequiredCollateral - netCollateral;

        // console.log("      Is excess collateral positive:", isPositive_);
        // console.log("      Final excess collateral e02:", 100 * excessCollateral_ / WAD, "ETH");
        // console.log("   Exit viewUserExcessCollateral()");
    }

    // 
    
    function viewIsUserExcessCollateralPositive(
        address _user,
        uint256 _minusCollateral
    )
        public view
        returns (bool isPositive_)
    {
        (isPositive_,) = viewUserExcessCollateral(_user, _minusCollateral);
    }

    function viewMinDeposit(bool _isBuyOrder)
        public view
        returns (uint256)
    {
        return _isBuyOrder == true ? minDepositQuote : minDepositBase;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  INTERNAL PURE FUNCTIONS                   */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
    
    // return true if order and pool have same asset type, or pool is empty (no asset type)
    // asset type of pool refers to first order's asset type
    // pool not empty ahs been checked before

    /// @notice check whether the pool is in quote or base token
    /// _poolId is even => buy order / odd => sell order
    /// update bottomOrder if necessary
    
    function _isQuotePool(uint256 _poolId) 
        internal pure
        returns (bool)
    {
        return _poolId % 2 == 0 ? true : false;
    }
    
    // check that pools have correct and well ordered limit prices
    // if buy order pool, paired pool must in base tokens and limit price must be strictly lower than paired limit price
    // if sell order pool, paired pool must be in quote limit price must be strictly higher than paired limit price
    
    // substract an uint256 to another one in a third one with checks anr recovery option

    function _substract(
        uint256 _a,
        uint256 _b,
        string memory _errCode,
        bool _recover
    )
        internal pure
        returns (uint256)
    {
        if (_a >= _b) {return _a - _b;}
        else {
            if (_recover) return 0;
            else revert(_errCode);
        }
    }
    
    function _consistent(
        uint256 _poolId,
        uint256 _pairedPoolId
    )
        internal pure
        returns (bool)
    {
        return _isQuotePool(_poolId) ? _pairedPoolId >= _poolId : _pairedPoolId <= _poolId;
    }
    
    function _convert(
        uint256 _quantity,
        uint256 _price,
        bool _inQuote, // type of the asset to convert to (quote or base token)
        bool _roundUp // round up or down
    )
        internal pure
        returns (uint256 convertedQuantity)
    {
        require(_price > 0, "Price is zero");
        
        if (_roundUp) convertedQuantity = _inQuote ? _quantity.wDivUp(_price) : _quantity.wMulUp(_price);
        else convertedQuantity = _inQuote ? _quantity.wDivDown(_price) : _quantity.wMulDown(_price);
    }

    /////**** Functions used in tests ****//////

    function setPriceFeed(uint256 _newPrice)
        public
    {
        priceFeed = _newPrice;
    }
    
    // Add manual getter for depositIds for User, used in setup.sol for tests
    // doesn't include user's account

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

}