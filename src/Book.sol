// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

/// @title A lending order book for ERC20 tokens
/// @author Pré-vert
/// @notice Allows users to place limit orders on the book, take orders, and borrow assets
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

    /// @notice provides core public functions (deposit, withdraw, take, borrow, repay, changePrice, liquidate, ...)
    /// + internal functions (_closeNPositions, _closePosition, _liquidate, _repayUserDebt, ...) + view functions
    
    IERC20 public quoteToken;
    IERC20 public baseToken;
    uint256 constant public MAX_ORDERS = 5; // How many orders can a user place in different pools
    uint256 constant public MAX_POSITIONS = 5; // How many positions can a user open in different pools
    uint256 constant public MAX_OPERATIONS = 2; // How many max liquidated positions for every min deposit taken
    uint256 constant public MAX_GAS = 2000000; // 
    uint256 constant public MIN_DEPOSIT_BASE = 2 * WAD; // Minimum deposited base tokens to be received by takers
    uint256 constant public MIN_DEPOSIT_QUOTE = 100 * WAD; // Minimum deposited quote tokens to be received by takers
    uint256 constant public PRICE_STEP = 11 * WAD / 10; // Price step for placing orders = 1.1
    uint256 constant private ABSENT = type(uint256).max; // id for non existing order or position in arrays
    bool constant private TO_POSITION = true; // applies to position or or order
    bool constant private ROUNDUP = true; // round up in conversions
    uint256 public constant ALPHA = 5 * WAD / 1000; // IRM parameter = 0.005
    uint256 public constant BETA = 15 * WAD / 1000; // IRM parameter = 0.015
    uint256 public constant GAMMA = 10 * WAD / 1000; // IRM parameter =  0.010
    uint256 public constant FEE = 20 * WAD / 1000; // interest-based liquidation fee for maker =  0.020 (2%)
    uint256 public constant YEAR = 365 days; // number of seconds in one year
    bool private constant RECOVER = true; // how negative uint256 following substraction are handled
    enum PoolIn {quote, base, none}

    struct Pool {
        mapping(uint256 => uint256) orderIds;  // index => order id in the pool
        mapping(uint256 => uint256) positionIds;  // index => position id in the pool
        uint256 deposits; // assets deposited in the pool
        uint256 nonBorrowables; // min deposits, non borrowable assets and locked collateral
        uint256 borrows; // assets borrowed from the pool
        uint256 lastTimeStamp; // # of periods since last time instant interest rate has been updated in the pool
        uint256 timeWeightedRate; // time-weighted average interest rate since inception of the pool, applied to borrows
        uint256 timeUrWeightedRate; // time-weighted and UR-weighted average interest rate since inception of the pool, applied to deposits
        uint256 topOrder; // row index of orderId on the top of orderIds mapping
        uint256 bottomOrder; // row index of last orderId deleted from orderIds mapping
        uint256 topPosition; // row index of positionId on the top of positionIds mapping
        uint256 bottomPosition; // row index of last positionId deleted from positionIds mapping
    }
    
    // orders and borrows by users
    struct User {
        uint256[MAX_ORDERS] depositIds; // orders id in mapping orders
        uint256[MAX_POSITIONS] borrowIds; // positions id in mapping positions
    }
    
    struct Order {
        int24 poolId; // pool id of order
        address maker; // address of maker
        int24 pairedPoolId; // pool id of paired order
        uint256 quantity; // assets deposited (quoteToken for buy orders, baseToken for sell orders)
        uint256 orderWeightedRate; // time-weighted and UR-weighted average interest rate for the supply since deposit
        bool isBuyOrder; // true for buy orders, false for sell orders
        bool isBorrowable; // true if order's assets can be borrowed
    }

    // borrowing positions
    struct Position {
        int24 poolId; // pool id in mapping orders, from which assets are borrowed
        address borrower; // address of the borrower
        uint256 borrowedAssets; // quantity of assets borrowed (quoteToken for buy orders, baseToken for sell orders)
        uint256 positionWeightedRate; // time-weighted average interest rate for the position since its creation
        bool inQuote; // asset's type
    }

    mapping(int24 poolId => Pool) public pools;  // int24: integers between -8,388,608 and 8,388,607
    mapping(uint256 orderId => Order) public orders;
    mapping(address user => User) internal users;
    mapping(uint256 positionId => Position) public positions;
    mapping(int24 poolId => uint256) public limitPrice;

    uint256 public lastOrderId = 1; // initial order id (0 for non existing orders)
    uint256 public lastPositionId = 1; // initial position id (0 for non existing positions)
    uint256 public priceFeed;
 
    constructor(address _quoteToken, address _baseToken, uint256 _startingLimitPrice) {
        quoteToken = IERC20(_quoteToken);
        baseToken = IERC20(_baseToken);
        limitPrice[0] = _startingLimitPrice; // initial limit price for the first pool
    }

    modifier orderHasAssets(uint256 _orderId) {
        require(_orderHasAssets(_orderId), "Order has zero assets");
        _;
    }

    modifier poolHasAssets(int24 _poolId) {
        require(_poolHasAssets(_poolId), "Pool has zero assets");
        _;
    }

    modifier poolHasOrders(int24 _poolId) {
        require(_poolHasOrders(_poolId), "Pool has no orders");
        _;
    }

    modifier positionHasBorrowedAssets(uint256 _positionId) {
        require(_hasBorrowedAssets(_positionId), "Position has not assets");
        _;
    }

    modifier moreThanZero(uint256 _var) {
        require(_var > 0, "Must be positive");
        _;
    }

    modifier isBorrowable(uint256 _orderId) {
        require(_orderIsBorrowable(_orderId), "Order non borrowable");
        _;
    }

    modifier onlyMaker(uint256 _orderId) {
        _onlyMaker(_orderId);
        _;
    }

    modifier onlyBorrower(uint256 _positionId) {
        _onlyBorrower(_positionId);
        _;
    }
    

    /// @inheritdoc IBook
    function deposit(
        uint256 _quantity,
        int24 _poolId,
        int24 _pairedPoolId,
        bool _isBuyOrder,
        bool _isBorrowable
    )
        external
        moreThanZero(_quantity)
    {
        PoolIn poolType = _poolType(_poolId); // in quote or base tokens, or none if the pool is empty
        bool profit = profitable(_poolId); // whether filling orders from pool is profitable for takers
        
        // deposit becomes take if profitable, which may liquidate positions
        if (!_sameType(_isBuyOrder, poolType) && profit) take(_poolId, _quantity);

        // deposit only if (1) order's and pool's asset type match and (2) order can't be immediately taken
        else if (_sameType(_isBuyOrder, poolType) && !profit) {
            uint256 orderId = _deposit(_quantity, _poolId, _pairedPoolId, _isBuyOrder, _isBorrowable);
            emit Deposit(msg.sender, _poolId, orderId, _quantity, limitPrice[_poolId], _pairedPoolId, limitPrice[_pairedPoolId], _isBuyOrder, _isBorrowable);
        }

        // revert if deposit is immediately profitable for takers (protection)
        else revert("Limit price at loss");
    }

    /// @inheritdoc IBook
    function withdraw(
        int24 _poolId,
        uint256 _quantity
    )
        external
        moreThanZero(_quantity)
        poolHasAssets(_poolId)
        poolHasOrders(_poolId)
    {
        Pool memory pool = pools[_poolId];
        bool inQuote = convertToInQuote(_poolType(_poolId));
        
        // from which order in pool user can withdraw 
        uint256 orderId_ = getUserOrderIdInPool(msg.sender, _poolId, inQuote);

        // order's asset type must match pool's asset type
        require(orders[orderId].isBuyOrder == inQuote, "asset mismatch_6");

        // update pool's TWIR and TUWIR before changes in pool's UR and calculating user's excess collateral
        _incrementWeightedRates(_poolId);

        // add interest rate to existing deposit
        // update TUWIR_t to TUWIR_T to reset interest rate to zero
        // add interest rate to deposit and pool's total borrow
        _addInterestRateTo(_poolId, !TO_POSITION, orderId_);

        // withdraw no more than deposit net of non-borrowed assets and min deposit if partial
        require(_removable(orderId_, _quantity), "Remove too much_1");

        // cannot withdraw more than available assets in the pool
        require(_quantity <= _poolAvailableAssets(_poolId), "Remove too much_2");

        // update user's excess collateral with accrued interest rate
        // excess collateral must remain positive after removal
        require(_quantity <= _getUserExcessCollateral(msg.sender, inQuote), "Remove too much_3");

        // reduce quantity in order, possibly to zero
        _decreaseOrderBy(orderId, _quantity);

        // decrease total deposits in pool
        _decreasePoolDepositsBy(_poolId, _quantity, inQuote);

        // decrease non borrowables by min deposit if full withraw or quantity if non borrowable
        _decreasePoolNonBorrowablesBy(_poolId, _quantity, inQuote);

        _transferTo(msg.sender, _quantity, inQuote);

        emit Withdraw(msg.sender, _quantity, _poolId, limitPrice[_poolId], inQuote, orderId);
    }

    /// @inheritdoc IBook
    function borrow(
        int24 _poolId,
        uint256 _quantity
    )
        external
        moreThanZero(_quantity)
        poolHasAssets(_poolId)
        poolHasOrders(_poolId)
    {
        Pool memory pool = pools[_poolId];
        bool inQuote = convertToInQuote(_poolType(_poolId));

        // decrease available assets in pool by min deposits 
        // ensure mainimal assets are reserved for takers even when positions outnumber deposits in pool
        _increasePoolNonBorrowablesBy(minDeposit(_isBuyOrder), _poolId);

        // cannot borrow more than available assets in pool
        require(_quantity <= _poolAvailableAssets(_poolId), "Borrow too much_1");

        // calculate required collateral of borrow
        uint256 requiredCollateral = convert(_quantity, limitPrice[_poolId], inQuote, ROUNDUP);

        // update TWIR before calculating user's excess collateral
        _incrementWeightedRates(_poolId);

        // update excess collateral with accrued interest rate
        // check borrowed amount is collateralized enough by borrower's own orders
        require(requiredCollateral <= _getUserExcessCollateral(msg.sender, !inQuote), "Borrow too much_2");
        
        // create new or update existing borrowing position in positions
        // update pool's total borrow
        // add position id to borrowIds[] in user if new
        // add position id to positionIds[] in pool if new
        // returns id of new position or updated existing one
        uint256 positionId = _createOrAddPositionInPositions(_poolId, msg.sender, _quantity, inQuote);

        // add _quantity to pool's total borrow
        _increasePoolBorrowBy(_poolId, _quantity, _inQuote);

        _transferTo(msg.sender, _quantity, inQuote);

        emit Borrow(msg.sender, _poolId, positionId, _quantity, inQuote);
    }

    /// @inheritdoc IBook
    function repay(
        int24 _poolId,
        uint256 _quantity
    )
        external
        moreThanZero(_quantity)
        poolHasAssets(_poolId)
        poolHasOrders(_poolId)
        // positionHasBorrowedAssets(_positionId)
        // onlyBorrower(_positionId)
    {
        Pool memory pool = pools[_poolId];
        bool inQuote_ = convertToInQuote(_poolType(_poolId));

        // which position in pool user repays
        uint256 positionId = getUserPositionIdInPool(msg.sender, _poolId, inQuote);

        // check user is an active borrower in pool
        require(positions[positionId].borrowedAssets > 0);

        // order's asset type must match pool's asset type
        require(positions[positionId].inQuote == inQuote_, "asset mismatch_7");

        // increment time-weighted rates with IR based on UR before repay
        _incrementWeightedRates(_poolId);

        // add interest rate to borrowed quantity
        // update TWIR_t to TWIR_T to reset interest rate to zero
        // add interest rate to borrowed quantity and pool's total borrow
        _addInterestRateTo(_poolId, TO_POSITION, positionId);

        require(_quantity <= positions[positionId].borrowedAssets, "Repay too much");

        // decrease borrowed assets in position, possibly to zero
        _decreaseBorrowBy(positionId, _quantity);

        // decrease borrowed assets in pool's total borrow
        _decreasePoolBorrowBy(_poolId, _quantity, inQuote);

        // decrease non borrowables by min deposit if full repay or quantity if non borrowable
        // _decreasePoolNonBorrowablesBy(_poolId, _quantity, inQuote);

        _transferFrom(msg.sender, _quantity, inQuote);
        
        emit Repay(msg.sender, _poolId, positionId, _quantity, inQuote);
    }

    /// @inheritdoc IBook
    function take(
        uint256 _poolId,
        uint256 _takenQuantity
    )
        public
        poolHasAssets(_poolId)
        poolHasOrders(_poolId)
    {
        Pool memory pool = pools[_poolId];
        // uint256 gas = 200000;
        
        // if order is borrowed, taking is allowed for profitable trades only
        if (pool.borrows > 0) require(profitable(_poolId), "Trade must be profitable");

        uint256 availableAssets = _substract(pool.deposits, pool.borrows, "err 012", !RECOVER);
        require(_takenQuantity <= availableAssets, "take too muche_00");
        
        bool inQuote = convertToInQuote(_poolType(_poolId));
        // uint256 minDepose = minDeposit(inQuote);
        uint256 positionNumber = calibrate(_poolId); 
        
        // take orders as they come in pool's orderIds[] from bottom up
        // from order with assets A, take minDeposit M 
        // clear remaining assets (A-M) with collateral C of pool's debt D
        // check if makers borrow the other side of the book, iterate on all maker's debt
        // repay maker's debt convert(D) up to order's assets (A-M), as if collateral was 100 % in pool
        // with residual amount R = (A-M-convert(D)), create or increase limit orders by convert(R) the other side of the book
        // Example: Alice deposits 2100 USDC in a buy order (p = 1900)
        // She borrows 1 ETH from Clair's sell order (p' = 2200)
        // Alice's buy order is taken for X \in (0, 2100) USDC in exchange of X/p ETH
        // Her debt in ETH is repaid for min(X/p, 1) 

        if (_takenQuantity > 0)
        {
            uint256 remainingTakenQuantity = _takenQuantity;
            for (uint256 i = pool.bottomOrder; i < pool.topOrder; i++) {
                uint256 orderId = pool.orderIds[i];
                Order order = orders[orderId];
                remainingTakenQuantity = (remainingTakenQuantity - minDeposit(inQuote)).maxi(0);

                // increment time-weighted rates with IR based on past UR before take() changes future UR
                _incrementWeightedRates(_poolId);
                
                // liquidate N borrowing positions, output seized borrowers' collateral
                // Ex: Bob deposits 2 ETH in a sell order to borrow 4000 from Alice's buy order (p = 2000)
                // Alice's buy order is taken, Bob's collateral is seized for 4000/p = 2 ETH  
                uint256 seizedCollateral = _closeNPositions(orderId);
                
                // Liquidation means les assets deposited (seized collateral) and less assets borrowed (canceled debt)
                uint256 canceledDebt = 0;
                if (seizedCollateral > 0) {
                    // total deposits from borrowers' side are reduced by 2 ETH
                    _decreasePoolDepositsBy(_poolId, seizedCollateral, !isBuyOrder);
                    // if 2 ETH are seized, 2*p = 4000 USDC of debt are canceled
                    canceledDebt = convert(seizedCollateral, takenOrder.price, !isBuyOrder, !ROUNDUP);
                    // total borrow is reduced by 4000 USDC
                    _decreasePoolBorrowBy(poolId, canceledDebt, isBuyOrder);
                }

                
                
                
                // maker's debt paid back
                if (order.quantity > 0) {
                    uint256 takenAssets = remainingTakenQuantity.mini(order.quantity);
                    uint256 cash = convert(takenAssets, limitPrice[_poolId], inQuote, !ROUNDUP);

                    // if user has no debt, remaining cash = cash
                    // if he has a lot of debt, remaining cash = 0
                    // CAN REPAY() BE REUSED HERE ?
                    uint256 remainingCash = _repayUserDebt(order.maker, cash, inquote);

                    // whatever the amount of repaid debt, taker exchanges the whole order
                    remainingTakenQuantity -= convert(remainingCash, limitPrice[_poolId], inQuote, ROUNDUP);
                }

                

                
            }
        }
            
        }

        // liquidate positions as they come fromm bottom up
        // seize assets the other side of the book up to the amount borrowed
        // with the proceeds, create or increase limit orders the other side of the book

        for (uint256 i = pool.bottomPosition; i < (pool.bottomPosition + maxPosition); i++) {
            
        }



        // taking is allowed for non-borrowed assets, possibly net of minimum deposit if taking is partial
        require(_takable(_poolId, _quantity, minDepose), "Take too much");

        

        

        // quantity given by taker in exchange of _takenQuantity (can be zero)
        uint256 exchangedQuantity = convert(_takenQuantity, takenOrder.price, isBuyOrder, ROUNDUP);
        
        // check if an identical order exists already, if so increase deposit, else create
        uint256 pairedOrderId = _getOrderIdInDepositIdsInUsers(
            takenOrder.maker,
            takenOrder.poolId,
            takenOrder.pairedPoolId,
            !takenOrder.isBuyOrder);
        uint256 netTransfer = _substract(exchangedQuantity + seizedCollateral, canceledDebt, "err 000", RECOVER);
        
        if (netTransfer > 0) {
            // if the paired order must be created and minimum amount deposited is not met, send to maker back
            // else create or increase paired order
            uint256 minDepose = minDeposit(!isBuyOrder);
            if (pairedOrderId == 0 && netTransfer < minDepose) {
                _transferTo(takenOrder.maker, netTransfer, !isBuyOrder);
            } else {
                uint256 newOrderId = _placeOrder(
                    poolId,
                    takenOrder.maker,
                    netTransfer,
                    pairedPoolId, // takenOrder.pairedPrice,
                    // takenOrder.price,
                    !isBuyOrder,
                    takenOrder.isBorrowable,
                    orderId
                );
                // add new orderId in depositIds array in users
                _addOrderIdInDepositIdsInUser(_maker, newOrderId);

                // add new orderId in pool orderIds mapping
                _addOrderIdToOrderIdsInPool(_poolId, newOrderId);
        
                // update TWIR
                _incrementWeightedRates(_poolId);

                // increase total deposits net of non borrowables in pool
                _increasePoolDepositsBy(_poolId, netTransfer, isBuyOrder);
                if (!takenOrder.isBorrowable) _increasePoolNonBorrowablesBy(_poolId, netTransfer, isBuyOrder);
                else _increasePoolNonBorrowablesBy(_poolId, minDepose);
            }            
        }

        if (_takenQuantity > 0) { 
            _transferTo(msg.sender, _takenQuantity, isBuyOrder);
            _transferFrom(msg.sender, exchangedQuantity, !isBuyOrder);
        }

        emit Take(msg.sender, _takenOrderId, takenOrder.maker, _takenQuantity, takenOrder.price, isBuyOrder);
    }

    /// @inheritdoc IBook
    function liquidate(uint256 _positionId)
        external
        positionHasBorrowedAssets(_positionId)
    {
        uint256 orderId = positions[_positionId].orderId;
        
        // if taking is profitable, liquidate all positions, not only the undercollateralized one
        if (profitable(pooolId)) {
            take(orderId, 0);
        } else {
            // only maker can pull the trigger
            _onlyMaker(orderId);
            _liquidate(_positionId);
            emit Liquidate(msg.sender, _positionId);
        }
    }

    /// @inheritdoc IBook
    function changeLimitPrice(uint256 _orderId, uint256 _price)
        external
        moreThanZero(_price)
        onlyMaker(_orderId)
    {
        Order memory order = orders[_orderId];
        require(consistent(_price, order.pairedPrice, order.isBuyOrder), "Inconsistent prices");
        require(getAssetsLentByOrder(_orderId) == 0, "Order must not be borrowed from");
        orders[_orderId].price = _price;
        emit ChangeLimitPrice(_orderId, _price);
    }

    /// @inheritdoc IBook
    function changePairedPrice(uint256 _orderId, uint256 _pairedPrice)
        external
        moreThanZero(_pairedPrice)
        onlyMaker(_orderId)
    {
        Order memory order = orders[_orderId];
        require(consistent(order.price, _pairedPrice, order.isBuyOrder), "Inconsistent prices");
        orders[_orderId].pairedPrice = _pairedPrice;
        emit ChangePairedPrice(_orderId, _pairedPrice);
    }

    /// @inheritdoc IBook

    // scenario : depose - borrowed - change to non borrowable - Available assets are reduced by depose but careful with negative available assets

    function changeBorrowable(uint256 _orderId, bool _isBorrowable)
        external
        onlyMaker(_orderId)
    {
        if (_isBorrowable) orders[_orderId].isBorrowable = true;
        else orders[_orderId].isBorrowable = false;
        emit ChangeBorrowable(_orderId, _isBorrowable);
    }

    ///////******* Internal functions *******///////
    
    // lets users place order in the book
    // update TWIR and initialize deposit's time-weighted and UR-weighted rate
    // update ERC20 balances
    
    function _deposit(
        uint256 _quantity,
        int24 _poolId,
        int24 _pairedPoolId,
        bool _isBuyOrder,
        bool _isBorrowable
    )
        internal
        returns (uint256 orderId_)
    {
        // revert if limit price and paired limit price are in wrong order
        require(consistent(_poolId, _pairedPoolId, _isBuyOrder), "Inconsistent limit prices");

        // revert if _poolId or _pairedPoolId has no price and is not adjacent to a pool id with a price        
        require(nearBy(_poolId), "Limit price too far");
        require(nearBy(_pairedPoolId), "Paired price too far");
        
        // returns order id if maker already supplies in pool with same paired limit price, if not returns zero
        uint256 orderId = _getOrderIdInDepositIdsInUsers(msg.sender, _poolId, _pairedPoolId, _isBuyOrder);

        // check minimum amount deposited
        if (orderId == 0) require(_quantity >= minDeposit(_isBuyOrder), "Deposit too small");

        // update TWIR and TUWIR before accounting for changes in UR and future interest rate
        _incrementWeightedRates(_poolId);

        // add to existing order or create new order
        // if new order:
        // - add new orderId in depositIds[] in users
        // - add new orderId on top of orderIds[] in pool
        orderId_ = _createOrIncreaseOrder(msg.sender, _quantity, _poolId, _pairedPoolId, _isBuyOrder, _isBorrowable, orderId);

        // increase total deposits in pool
        _increasePoolDepositsBy(_poolId, _quantity, _isBuyOrder);

        // increase total deposits in pool, net of non borrowable assets
        if (!_isBorrowable) _increasePoolNonBorrowablesBy(_poolId, _quantity, _isBuyOrder);
        else _increasePoolNonBorrowablesBy(minDepose, _poolId);

        _transferFrom(msg.sender, _quantity, _isBuyOrder);
    }
        
    // import order id if maker already supplies in pool with same paired limit price (otherwise zero)
    // add to existing order or create new order
    // if existing order:
    // - increase deposit by quantity + accrued interest rate
    // - reset R_t to R_T
    // if new order:
    // - add new orderId in depositIds[] in users
    // - add new orderId on top of orderIds[] in pool
    // update pool's total deposit
    // returns order id
    // called by _deposit() or take() ? for self-replacing order
    
    function _createOrIncreaseOrder(
        int24 _poolId,
        address _maker,
        uint256 _quantity,
        int24 _pairedPoolId,
        bool _isBuyOrder,
        bool _isBorrowable,
        uint256 _orderId
    )
        internal
        returns (uint256 orderId_)
    {

        // if order already exists     
        if (_orderId != 0) {

            // add interest rate to existing deposit
            // update TUWIR_t to TUWIR_T to reset interest rate to zero
            // add interest rate to deposit and pool's total borrow
            _addInterestRateTo(_poolId, !TO_POSITION, _orderId);

            // add additional quantity to existing deposit
            _increaseOrderBy(_orderId, _quantity);

            orderId_ = _orderId;

        // order does not exist
        } else {

            // create new order in orders
            uint256 newOrderId = _placeOrder(_poolId, _maker, _quantity, _pairedPoolId, _isBuyOrder, _isBorrowable);
            
            // add new orderId in depositIds[] in users
            // revert if max orders reached
            _addOrderIdInDepositIdsInUser(msg.sender, newOrderId);

            // add new orderId on top of orderIds[] in pool
            _addOrderIdToOrderIdsInPool(_poolId, newOrderId);
        }
    }

    // create a new order
    
    function _placeOrder(
        int24 _poolId,
        address _maker,
        uint256 _quantity,
        int24 _pairedPoolId,
        bool _isBuyOrder,
        bool _isBorrowable
    )
        internal
        returns (uint256 newOrderId)
    {
        Order memory newOrder = Order(
            _poolId,
            _maker,
            _quantity,
            _pairedPoolId,
            getTimeUrWeightedRate(poolId),
            _isBuyOrder,
            _isBorrowable
        );
        newOrderId = lastOrderId;
        orders[newOrderId] = newOrder;
        lastOrderId ++;
    }
    
    // NOT RELEVANT ANYMORE: ne ferme plus max_positions positions sur un ordre mais N positions dans un pool
    // close **all** borrowing positions after taking in a pool, even if taking is partial or 0
    // call _closePosition for every position to close
    // doesn't perform external transfers
    // _poolId: pool id from which borrowing positions must be cleared

    function _closeNPositions(uint256 poolId)
        internal
        returns (uint256 seizedBorrowerCollateral)
    {
        uint256[MAX_POSITIONS] memory positionIds = orders[_fromOrderId].positionIds;
        seizedBorrowerCollateral = 0;

        // iterate on position ids which borrow from the pool taken, liquidate position one by one
        for (uint256 i = 0; i < MAX_POSITIONS; i++) {
            uint256 positionId = positionIds[i];
            if(_hasBorrowedAssets(positionId)) {

                // return interest rate multiplied by borrowed quantity
                accruedInterestRate_ = accruedInterestRate(positions[positionId].poolId, TO_POSITION, positionId);

                // add interest rate to position
                _increaseBorrowBy(positionId, accruedInterestRate_);

                // update pool's total borrow
                _increasePoolBorrowBy(_poolId, accruedInterestRate_, inQuote);

                uint256 seizedCollateral = _closePosition(
                    positionId,
                    positions[positionId].borrowedAssets,
                    orders[_fromOrderId].price
                );
                seizedBorrowerCollateral += seizedCollateral;
            }
        }
    }

    // When an order is taken, all positions which borrow from it are closed
    // close one borrowing position for quantity _borrowToCancel:
    // - cancel debt for this quantity
    // - seize collateral for the exact amount liquidated at exchange rate _price, order's limit price
    // as multiple orders may collateralize a closed position:
    //  - iterate on collateral orders made by borrower in the opposite currency
    //  - seize collateral orders as they come, stop when borrower's debt is fully canceled
    //  - change internal balances
    // interest rate has been added to position before callling _closePosition
    // outputs actually seized collateral which can be less than expected amount
    // if maker failed to trigger an interest-based liquidation 

    function _closePosition(
        uint256 _positionId,
        uint256 _borrowToCancel,
        uint256 _price
    )
        internal
        returns (uint256 seizedCollateral_)
    {
        Position memory position = positions[_positionId]; // position to be liquidated
        bool inQuote = orders[position.orderId].isBuyOrder; // type of order from which assets are taken
        
        // collateral to seize the other side of the book given borrowed quantity
        // ex: Bob deposits 1 ETH in 2 sell orders to borrow 4000 from Alice's buy order (p = 2000)
        // Alice's buy order is taken => seized Bob's collateral is 4000/p = 2 ETH spread over 2 orders
        uint256 collateralToSeize = convert(_borrowToCancel, _price, inQuote, ROUNDUP);

        uint256 remainingCollateralToSeize = collateralToSeize;

        // order id list of collateral orders to seize:
        uint256[MAX_ORDERS] memory depositIds = users[position.borrower].depositIds;
        for (uint256 j = 0; j < MAX_ORDERS; j++) {
            // order id from which assets are seized, ex: id of Bob's first sell order with ETH as collateral
            uint256 orderId = depositIds[j];
            if (_orderHasAssets(orderId) &&
                orders[orderId].isBuyOrder != inQuote)
            {
                uint256 orderQuantity = orders[orderId].quantity;

                if (orderQuantity > remainingCollateralToSeize)
                {
                    // enough collateral assets are seized before borrower's order could be fully seized
                    _decreaseOrderBy(orderId, remainingCollateralToSeize);
                    uint256 canceledDebt = convert(remainingCollateralToSeize, _price, !inQuote, ROUNDUP);
                    // handle rounding errors
                    positions[_positionId].borrowedAssets = _substract(
                        positions[_positionId].borrowedAssets, canceledDebt, "err 001", RECOVER);
                    remainingCollateralToSeize = 0;
                    break;
                } else {
                    // borrower's order is fully seized, reduce order quantity to zero
                    _decreaseOrderBy(orderId, orderQuantity);
                    // cancel debt for the same amount as collateral seized
                    positions[_positionId].borrowedAssets = 0;
                    remainingCollateralToSeize -= orderQuantity;
                }
            }
        }
        // could be less than collateralToSeize if maker has not liquidated undercollateralized positions
        seizedCollateral_ = collateralToSeize - remainingCollateralToSeize;
    }

    // when an order is taken, the assets that the maker obtains serve in priority to pay back maker's own positions
    // reduce maker's borrowing positions possibly as high as _cash
    // Ex: Bob deposits a sell order as collateral to borrow Alice's buy order
    // Bob's sell order is taken first, his borrowing position from Alice is reduced, possibly to zero
    // as multiple positions may be collateralized by a taken order:
    // - iterate on user's borrowing positions
    // - close positions as they come by calling _repayDebt()
    // - stop when all positions have been closed or cash is exhausted
    // - change internal balances
    
    function _repayUserDebt(
        address _borrower,
        uint256 _cash,
        bool _inQuote // type of the taken order
    )
        internal
        returns (uint256 remainingCash_)
    {
        remainingCash_ = _cash;
        uint256[MAX_POSITIONS] memory borrowIds_ = users[_borrower].borrowIds;

        // iterate on position ids, pay back position one by one with budget
        for (uint256 i = 0; i < MAX_POSITIONS; i++) {
            uint256 positionId = positions[borrowIds[i]];
            if (positions[positionId].borrowedAssets > 0 && positions[positionId].inQuote != _inQuote)
            {
                remainingCash_ = _repayDebt(poolId, positionId, remainingCash);
                if (remainingCash_ == 0) break;
            }
        }
    }

    // reduce maker's debt in position, partially or fully, with remainingCash
    // remaining cash: available assets exchanged against taken order

    function _repayDebt(
        int24 _poolId,
        uint256 _positionId,
        uint256 _remainingCash
    )
        internal 
        returns (uint256 remainingCash_) // after closing this position
    {
        // add interest rate to borrowed quantity and update TWIR_t to TWIR_T to reset interest rate to zero
        // add interest rate to pool's total borrow
        _addInterestRateTo(_poolId, TO_POSITION, _positionId);
        
        uint256 canceledDebt = positions[_positionId].borrowedAssets.mini(_remainingCash);

        // decrease borrowed assets in position, possibly to zero
        _decreaseBorrowBy(_positionId, canceledDebt);

        // decrease borrowed assets in pool
        _decreasePoolBorrowBy(positions[positionId].poolId, canceledDebt, positions[positionId].inQuote);

        // revise remaining cash down
        remainingCash_ = _remainingCash - canceledDebt;
    }

    // liquidate borrowing positions from users which excess collateral is zero or negative
    // borrower's excess collateral must be zero or negative
    // only maker can liquidate positions borrowing from her order

    function _liquidate(uint256 _positionId) internal
    {
        Position memory position = positions[_positionId]; // position to be liquidated
        Order memory borrowedOrder = orders[position.orderId]; // order of maker from which assets are borrowed
        bool inQuote = borrowedOrder.isBuyOrder;
        
        // increment time-weighted rates with IR before liquidate (necessary for up-to-date excess collateral)
        _incrementWeightedRates(_poolId);

        require(_getUserExcessCollateral(position.borrower, !inQuote) == 0, "Borrower excess collateral is positive");

        // multiply fee rate by borrowed quantity = fee
        uint256 totalFee = FEE.wMulUp(position.borrowedAssets);

        // add fee to borrowed quantity (interest rate already added), update pool's total borrow
        _increaseBorrowBy(_positionId, totalFee);

        // add fee to pool's total borrow
        _increasePoolBorrowBy(_poolId, totalFee, inQuote);

        // seize collateral equivalent to borrowed quantity + interest rate + fee
        uint256 seizedCollateral = _closePosition(_positionId, positions[_positionId].borrowedAssets, priceFeed);

        // Liquidation means less assets deposited (seized collateral) and less assets borrowed (canceled debt)
        if (seizedCollateral > 0) {
            // total deposits from borrowers' side are reduced by 2 ETH
            _decreasePoolDepositsBy(seizedCollateral, !inQuote);
            // if 2 ETH are seized, 2*p = 4000 USDC of debt are canceled
            _decreasePoolBorrowBy(poolId, convert(seizedCollateral, borrowedOrder.price, !inQuote, !ROUNDUP), inQuote);
            // transfer seized collateral to maker
            _transferTo(borrowedOrder.maker, seizedCollateral, !inQuote);
        }
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

    // DEPRECATED add order to Order, returns id of the new order
    // function _addOrderToOrders(
    //     address _maker,
    //     bool _isBuyOrder,
    //     uint256 _quantity,
    //     uint256 _price,
    //     uint256 _pairedPrice,
    //     bool _isBorrowable
    // )
    //     internal 
    //     returns (uint256 orderId)
    // {
    //     uint256[MAX_POSITIONS] memory positionIds;
    //     Order memory newOrder = Order(
    //         _maker,
    //         _isBuyOrder,
    //         _quantity,
    //         _price,
    //         _pairedPrice,
    //         _isBorrowable,
    //         positionIds
    //     );
    //     orders[lastOrderId] = newOrder;
    //     orderId = lastOrderId;
    //     lastOrderId++;
    // }

    // add new orderId in depositIds[] in users 
    // revert if max orders reached

    function _addOrderIdInDepositIdsInUser(
        address _maker,
        uint256 _orderId
    )
        internal
    {
        bool fillRow = false;
        for (uint256 i = 0; i < MAX_ORDERS; i++) {
            if (!_orderHasAssets(users[_maker].depositIds[i])) {
                users[_maker].depositIds[i] = _orderId;
                fillRow = true;
                break;
            }
        }
        if (!fillRow) revert("Max orders reached");
    }

    // add position id in borrowIds[] in mapping users
    // reverts if user's max number of positions reached

    function _addPositionIdInBorrowIdsInUser(
        address _borrower,
        uint256 _positionId
    )
        internal
    {
        bool fillRow = false;
        for (uint256 i = 0; i < MAX_POSITIONS; i++)
        {
            if (!_hasBorrowedAssets(users[_borrower].borrowIds[i]))
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
        address _poolId,
        uint256 _orderId
    )
        internal
    {
        pools[_poolId].orderIds[pools[_poolId].topOrder] = _orderId;
        pools[_poolId].topOrder ++;
    }

    // add position to existing position or create new one
    // check if user already borrows in pool
    // if yes:
    // - increase borrow by quantity + accrued interest rate
    // - reset R_t to R_T
    // if not:
    // add position id to borrowIds[] in users
    // add position id to borrows[] in pools
    // update pool's total borrow
    // returns existing or new position id
    // _poolId: pool id from which assets are borrowed

    function _createOrAddPositionInPositions(
        int24 _poolId,
        address _borrower,
        uint256 _quantity,
        bool _inQuote
    )
        internal
        returns (uint256 positionId_)
    {
        // find if borrower has already a position in pool
        positionId_ = getPositionId(_borrower, _poolId);

        // if position already exists
        if (positionId_ != 0) {
            
            // add interest rate to borrowed quantity
            // update TWIR_t to TWIR_T to reset interest rate to zero
            // add interest rate to borrowed quantity and pool's total borrow
            _addInterestRateTo(_poolId, TO_POSITION, positionId_);

            // add additional borrow to borrowed quantity
            _increaseBorrowBy(positionId_, _quantity);
        }
        // if position doesn't exist
        else 
        {
            // create position in positions, return new position id
            newPositionId = _addPositionToPositions(_poolId, _borrower, _quantity, _inQuote);

            // add new position id to borrowIds[] in users, 
            // revert if user has too many open positions (max position reached)
            _addPositionIdInBorrowIdsInUser(msg.sender, newPositionId);

            // add new position id in pool
            _AddPositionIdToPositionIdsInPool(poolId, newPositionId);
        }
    }


    // create position in positions mapping
    // returns new position id
    
    function _addPositionToPositions(
        int24 _poolId,
        address _borrower,
        uint256 _quantity,
        bool _inQuote
    )
        internal
        returns (uint256 positionId_)
    {
        Position memory newPosition = Position(
            _poolId,
            _borrower,
            _quantity,
            getTimeWeightedRate(_poolId), // initialize interest rate
            _inQuote
        );
        positionId_ = lastPositionId;
        positions[position_Id] = newPosition;
        lastPositionId++;
    }

    // increase borrowedAssets in position (special attention to excessCollateral)
    function _increaseBorrowBy(
        uint256 _positionId,
        uint256 _quantity
    )
        internal
    {
        positions[_positionId].borrowedAssets += _quantity;
    }

    // decrease borrowedAssets in position, borrowing = 0 is equivalent to deleted position
    // quantity =< borrowing is checked before the call, _substract could be removed

    function _decreaseBorrowBy(
        uint256 _positionId,
        uint256 _quantity
    )
        internal
    {
        positions[_positionId].borrowedAssets = _substract(
            positions[_positionId].borrowedAssets, _quantity, "err 002", RECOVER
        );
    }

    // add new position id on top of positionIds[] in pool
    // make sure position id does not already exist in positionIds

    function _AddPositionIdToPositionIdsInPool(
        uint256 _positionId,
        uint256 _orderId
    )
        internal
    {
        pools[_poolId].positionIds[pools[_poolId].topPosition] = _positionId;
        pools[_poolId].topPosition ++;
    }

    }

    // increase quantity offered in order, possibly from zero
    function _increaseOrderBy(
        uint256 _orderId,
        uint256 _quantity
    )
        internal
    {
        orders[_orderId].quantity += _quantity;
    }

    // reduce quantity offered in order, emptied is equivalent to deleted
    function _decreaseOrderBy(
        uint256 _orderId,
        uint256 _quantity
    )
        internal
    {
        orders[_orderId].quantity = _substract(orders[_orderId].quantity, _quantity, "err 003", !RECOVER);
    }

    // increase total deposits in pool (check before asset type)
    function _increasePoolDepositsBy(
        int256 _poolId,
        uint256 _quantity,
        bool _inQuote
    )
        internal
    {
        pools[_poolId].deposits += _quantity;
    }

    // check asset type, decrease total deposits in pool
    function _decreasePoolDepositsBy(
        int24 _poolId,
        uint256 _quantity,
        bool _inQuote
    )
        internal
    {
        if (_sameType(_poolType(_poolId), _inQuote)) 
            pools[_poolId].deposits = _substract(pools[_poolId].deposits, _quantity, "err 004", RECOVER);
        else revert("asset mismatch_1");
    }

    // check asset type, increase total borrow in pool
    function _increasePoolBorrowBy(
        int24 _poolId,
        uint256 _quantity,
        bool _inQuote
    )
        internal
    {
        if (_sameType(_poolType(_poolId), _inQuote)) pools[_poolId].borrows += _quantity;
        else revert("asset mismatch_2");
    }

    // check asset type and decrease total borrow in pool
    function _decreasePoolBorrowBy(
        int24 _poolId,
        uint256 _quantity,
        bool _inQuote
    )
        internal
    {
        if (_sameType(_poolType(_inQuote), _inQuote))
            _substract(pools[_poolId].borrows, _quantity, "err 006", !RECOVER);
        else revert("asset mismatch_3");
    }
    
    // check asset type, increase non borrowables in pool
    function _increasePoolNonBorrowablesBy(
        int24 _poolId,
        uint256 _quantity,
        bool _inQuote        
    )
        internal
    {
        if (!_isBorrowable) pools[_poolId].nonBorrowables += _quantity;
        else pools[_poolId].nonBorrowables += minDeposit(_isBuyOrder);
    }

    // check asset type, decrease non borrowables in pool
    function _decreasePoolNonBorrowablesBy(
        int24 _poolId,
        uint256 _quantity,
        bool _inQuote        
    )
        internal
    {
        if (_sameType(_poolType(_poolId), _inQuote)) {
            _substract(pools[_poolId].nonBorrowables, _quantity, "err 009", !RECOVER);
        }
        else revert("asset mismatch_5");
    }

    // handle substraction between two quantities
    // if negative, _recover = true, sets result to zero, emits an error code but does'nt break the flow 

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

    // add IR_{t-1} (n_t - n_{t-1})/N to TWIR_{t-2} in pool
    // and get TWIR_{t-1} the time-weighted interest rate from inception to present (in WAD)
    // with N number of seconds in a year, elapsed in seconds (intergers)
    // TWIR_{t-2} = IR_0 n_1/N + IR_1 (n_2 - n_1)/N + ... + IR_{t-1} (n_{t-2} - n_{t-1})/N
    // TWIR_{t-1} = IR_0 n_1/N + IR_1 (n_2 - n_1)/N + ... + IR_{t-1} (n_{t-2} - n_{t-1})/N + (n_t - n_{t-1})/N
    // pool can be either in quote or base tokens, depending on market price
    
    function _incrementWeightedRates(int24 _poolId)
        internal
    {
        uint256 elapsedTime = block.timestamp - pools[_poolId].lastTimeStamp;
        if (elapsedTime == 0) return;
        pools[_poolId].timeWeightedRate += elapsedTime * getInstantRate(_poolId);
        pools[_poolId].timeUrWeightedRate += elapsedTime * getInstantRate(_poolId).mulDivDown(getUtilizationRate(_poolId));
        pools[_poolId].lastTimeStamp = block.timestamp;
    }

    // get user's excess collateral in the quote or base token
    // excess collateral = total deposits - borrowed assets - needed collateral
    // needed collateral is computed with interest rate added to borrowed assets
    // _inQuote: asset type of required collateral

    function _getUserExcessCollateral(
        address _user,
        bool _inQuote
    )
        public
        returns (uint256) {
        
        _substract(getUserTotalDeposits(_user, _inQuote), _getUserRequiredCollateral(_user, _inQuote), "err 009", !RECOVER);
    }

    // calculate accrued interest rate for borrowed quantity or deposit
    // update TWIR_t to TWIR_T to reset interest rate to zero
    // add interest rate to borrowed quantity or deposit
    // add interest rate to pool's total borrow or total deposit
    // note: increasing total borrow and total deposit by interest rate does not chang pool's EL, as expected
    // however, it changes UR a bit upward
    // _mappingId: positionId or orderId
    // _toPosition: true of applied to position, false if applied to deposit
    
    function _addInterestRateTo(
        int24 _poolId,
        bool _toPosition,
        uint256 _mappingId,
    )
        internal
    {
        // return interest rate multiplied by borrowed quantity or deposit
        uint256 accruedInterestRate_ = accruedInterestRate(_poolId, _toPosition, _mappingId);

        if (_toPosition) {

            // update TWIR_t to TWIR_T to reset interest rate to zero
            positions[_mappingId].positionWeightedRate = getTimeWeightedRate(_poolId);

            // add interest rate to borrowed quantity
            _increaseBorrowBy(_mappingId, accruedInterestRate_);

            // add interest rate to pool's total borrow
            _increasePoolBorrowBy(_poolId, accruedInterestRate_);

        } else {

            // update TUWIR_t to TUWIR_T to reset interest rate to zero
            orders[_mappingId].orderWeightedRate = getTimeUrWeightedRate(_poolId);

            // add interest rate to deposit
            _increaseOrderBy(_mappingId, accruedInterestRate_);

            // add interest rate to pool's total deposits
            _increasePoolDepositsBy(_poolId, accruedInterestRate_);
        }
    }

    // required collateral needed to secure a user's debt in a given asset
    // update borrow by adding interest rate to debt (_incrementWeightedRates() has been called before)
    // collateral is in the opposite assets to debt's asset

    function _getUserRequiredCollateral(
        address _borrower,
        bool _inQuote
    )
        public
        returns (uint256 totalNeededCollateral_)
    {
        totalNeededCollateral_ = 0;

        uint256[MAX_POSITIONS] memory borrowIds_ = users[_borrower].borrowIds;
        for (uint256 i = 0; i < MAX_BORROWS; i++) {

            uint256 positionId = borrowedIds[i]; // position id from which user borrows assets
            int24 poolId_ = positions[positionId].poolId;
            PoolIn poolType = _poolType(poolId_);

            // look for borrowing positions to calculate required collateral
            if (_hasBorrowedAssets(positionId) && !_sameType(poolType, _inQuote)) {
                // add interest rate to borrowed quantity, update TWIR_t to TWIR_T to reset interest rate to zero
                // add interest rate to borrowed quantity and pool's total borrow
                _addInterestRateTo(poolId_, TO_POSITION, positionId);
                uint256 borrowed = positions[positionId].borrowedAssets;
                totalNeededCollateral += convert(borrowed, limitPrice[_poolId], poolType, ROUNDUP);
            }
        }
    }

    // check whether the pool is in quote token, base token or none
    // update bottomOrder if necessary
    
    function _poolType(int24 _poolId) 
        internal
        returns (PoolIn)
    {
        Pool pool = pools[_poolId];
        pool.token = PoolIn.none; // default

        for (uint256 i = pool.bottomOrder; i <= pool.topOrder; i++) {
            uint256 orderId = pool.orderIds[i];
            if (orders[orderId].quantity > 0) {
                pool.token = orders[orderId].isbuyOrder ? PoolIn.quote : PoolIn.base;
                pool.bottomOrder = i;
                break;
            }
        }
    }

    //////////********* Public View functions *********/////////

    function getUserOrderIdInPool(
        address _user,
        int24 _poolId,
        bool _inQuote
    )
        internal view
        returns (uint256 orderId_)
    {
        uint256[MAX_ORDERS] memory depositIds = users[_user].depositIds;
        orderId_ = 0;
        for (uint256 i = 0; i < MAX_ORDERS; i++) {
            uint256 orderId = depositIds[i];
            if (orders[orderId].poolId == _poolId && orders[orderId].isBuyOrder == _inQuote)
                orderId_ = orderId;
        }
    }

    function getUserPositionIdInPool(
        address _user,
        int24 _poolId,
        bool inquote
    )
        internal view
        returns (uint256 positionId_)
    {
        uint256[MAX_POSITIONS] memory borrowIds = users[_user].borrowIds;
        positionId_ = 0;
        for (uint256 i = 0; i < MAX_POSITIONS; i++) {
            uint256 positionId = borrowIds[i];
            if (positions[positionId].poolId == _poolId && positions[positionId].inQuote == _inQuote)
                positioId_ = positionId;
        }
    }
    
    // get UR = total borrow / total net assets in pool
    function getUtilizationRate(int24 _poolId)
        public view
        returns (uint256 utilizationRate_)
    {
        Pool pool = pools[_poolId];
        uint256 netDeposits = pool.deposits - pool.nonBorrowables;
        if (netDeposits == 0) utilizationRate_ = 5 * WAD / 10;
        else if (netDeposits <= pool.borrows) utilizationRate_ = 1 * WAD;
        else utilizationRate_ = pool.borrows.mulDivUp(WAD, netDeposits);
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
    
    // get TWIR_T in pool, used to compute interest rate for borrowing positions
    function getTimeWeightedRate(int24 _poolId)
        public view
        returns (uint256)
    {
        return pools[_poolId].TimeWeightedRate;
    }

    // get TUWIR_T in pool, used to compute interest rate for deposits
    function getTimeUrWeightedRate(int24 _poolId)
        public view
        returns (uint256)
    {
        return pools[_poolId].TimeUrWeightedRate;
    }

    // get maker's address based on order id
    function getMaker(uint256 _orderId)
        public view
        returns (address)
    {
        return orders[_orderId].maker;
    }

    // get borrower's address based on position id
    function getBorrower(uint256 _positionId)
        public view
        returns (address)
    {
        return positions[_positionId].borrower;
    }

    // sum all assets deposited by user in the quote or base token
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
            if (orders[depositIds[i]].isBuyOrder == _inQuote)
                totalDeposit += orders[depositIds[i]].quantity;
        }
    }

    // total assets borrowed by other users from _user in base or quote token
    // function getUserTotalBorrowFrom(
    //     address _user,
    //     bool _inQuote
    // )
    //     public view
    //     returns (uint256 totalBorrow)
    // {
    //     uint256[MAX_ORDERS] memory orderIds = users[_user].borrowIds;
    //     totalBorrow = 0;
    //     for (uint256 i = 0; i < MAX_ORDERS; i++) {
    //         totalBorrow += _getOrderBorrowedAssets(orderIds[i], _inQuote);
    //     }
    // }

    // total assets borrowed from order in base or quote tokens
    // DEPRECATED

    // function _getOrderBorrowedAssets(
    //     uint256 _orderId,
    //     bool _inQuote
    //     )
    //     public view
    //     returns (uint256 borrowedAssets)
    // {
    //     if (!_orderHasAssets(_orderId) || orders[_orderId].isBuyOrder != _inQuote) return borrowedAssets = 0;
    //     uint256[MAX_POSITIONS] memory positionIds = orders[_orderId].positionIds;
    //     for (uint256 i = 0; i < MAX_POSITIONS; i++) {
    //         borrowedAssets += positions[positionIds[i]].borrowedAssets;
    //     }
    // }

    // get quantity of assets lent by order
    // function getAssetsLentByOrder(uint256 _orderId)
    //     public view
    //     returns (uint256 totalLentAssets)
    // {
    //     uint256[MAX_POSITIONS] memory positionIds = orders[_orderId].positionIds;
    //     totalLentAssets = 0;
    //     for (uint256 i = 0; i < MAX_POSITIONS; i++) {
    //         totalLentAssets += positions[positionIds[i]].borrowedAssets;
    //     }
    // }
    
    // check that taking assets in pool is profitable
    // if buy order, price feed must be lower than limit price
    // if sell order, price feed must be higher than limit price
    
    function profitable(int24 _poolId)
        public view
        returns (bool)
    {
        if (pools[_poolId].token = PoolIn.quote) return (priceFeed <= limitPrice[_poolId]);
        else if (pools[_poolId].token = PoolIn.base) return (priceFeed >= limitPrice[_poolId]);
        else return false;
    }
    
    // return false if desired quantity cannot be withdrawn
    function _removable(
        uint256 _orderId,
        uint256 _quantity // removed quantity
    )
        internal view
        returns (bool)
    {
        Order order = orders[_orderId];
        uint256 minDepose = minDeposit(order.isbuyorder);

        if (_quantity == order.quantity || (_quantity + minDepose < order.quantity)) return true;
        else return false;
    }

    function _poolAvailableAssets(int24 _poolId)
        internal view
        returns (uint256)
    {
        Pool pool = pools[_poolId];
        return _substract(pool.deposits, pool.borrows + pool.nonBorrowables, "err 009", !RECOVER);
    }
    
    // return false if desired quantity is not possible to borrow
    function _borrowable(
        uint256 _orderId,
        uint256 _quantity // borrowed quantity
    )
        internal view
        returns (bool)
    {
        uint256 depositedAssets = orders[_orderId].quantity;
        uint256 lentAssets = getAssetsLentByOrder(_orderId);
        uint256 availableAssets = _substract(depositedAssets, lentAssets, "err 009", RECOVER);
        uint256 minDepose = minDeposit(orders[_orderId].isBuyOrder); 

        if (_quantity + minDepose <= availableAssets) return true;
        else return false;
    }

    // return false if desired quantity is not possible to take
    function _takable(
        uint256 _poolId,
        uint256 _quantity, // taken quantity
        uint256 _minDeposit
    )
        internal view
        returns (bool)
    {
        Pool pool = pools[_poolId];
        uint256 availableAssets = _substract(pool.deposits, pool.borrows, "err 010", !RECOVER);

        if (_quantity == availableAssets || _quantity + _minDeposit <= availableAssets) return true;
        else return false;
    }


    //////////********* Internal View functions *********/////////

    // compute interest rate since start of borrowing position or deposit between t and T
    // exp(TWIR_T - TWIR_t) - 1 is computed using a 3rd order Taylor approximation

    function interestRate(
        int24 _poolId,
        bool _toPosition,
        uint256 _mappingId
    )
        internal view
        returns (uint256)
    {
        uint256 rateDiff;
        if (_toPosition) {
            rateDiff = _substract(getTimeWeightedRate(_poolId), positions[_mappingId].positionWeightedRate, "err 000", !RECOVER);
            if (rateDiff > 0) return rateDiff.wTaylorCompoundedUp();
            else return 0;
        } else {
            rateDiff = _substract(getTimeUrWeightedRate(_poolId), users[_mappingId].orderWeightedRate, "err 001", !RECOVER);
            if (rateDiff > 0) return rateDiff.wTaylorCompoundedDown();
            else return 0;
        }
    }

    // return interest rate multiplied by borrowed quantity or deposit

    function accruedInterestRate(
        int24 poolId,
        bool _toPosition,
        uint256 _mappingId
    )
        internal view
        returns (uint256)
    {
        if(_toPosition)
            return interestRate(_poolId, _toPosition, _mappingId).wMulUp(positions[_positionId].borrowedAssets);
        else
            return interestRate(_poolId, !_toPosition, _mappingId).wMulDown(orders[_orderId].quantity);
    }

    // function _orderHasAssets(uint256 _orderId)
    //     internal view
    //     returns (bool)
    // {
    //     return (orders[_orderId].quantity > 0);
    // }

    function _poolHasAssets(int24 _poolId)
        internal view
        returns (bool)
    {
        return (pools[_poolId].deposits > 0);
    }

    function _poolHasOrders(int24 _poolId)
        internal view
        returns (bool)
    {
        return (_poolType(_poolId) != PoolIn.none);
    }

    function _onlyMaker(uint256 orderId)
        internal view
    {
        require(getMaker(orderId) == msg.sender, "Only maker can modify order");
    }

    function _onlyBorrower(uint256 _positionId)
        internal view
    {
        require(getBorrower(_positionId) == msg.sender, "Only borrower can repay position");
    }

    function _hasBorrowedAssets(uint256 _positionId)
        internal view
        returns (bool)
    {
        return (positions[_positionId].borrowedAssets > 0);
    }

    function _orderIsBorrowable(uint256 _orderId)
        internal view
        returns (bool)
    {
        return orders[_orderId].isBorrowable;
    }

    function _sameType(bool _isBuyOrder, PoolIn _token)
        internal view
        returns (bool)
    {
        if ((_isBuyOrder && _token != PoolIn.base) || (!_isBuyOrder && _token != PoolIn.quote)) return true;
        else return false;
    }

    // check if user borrows from order
    // if so, returns row in borrowFromIds array

    function _getBorrowFromIdsRowInUsers(
        address _borrower,
        uint256 _orderId // in the borrowFromIds array of users
    )
        internal view
        returns (uint256 borrowFromIdsRow)
    {
        borrowFromIdsRow = ABSENT;
        uint256[MAX_BORROWS] memory borrowFromIds = users[_borrower].borrowFromIds;
        for (uint256 i = 0; i < MAX_BORROWS; i++) {
            if (borrowFromIds[i] == _orderId) {
                borrowFromIdsRow = i;
                break;
            }
        }
    }

    // check if an order already exists in the pool, if so, returns order id, otherwise returns 0
    
    function _getOrderIdInDepositIdsInUsers(
        address _user,
        int24 _poolId,
        int24 _pairedPoolId,
        bool _isBuyOrder
    )
        internal view
        returns (uint256 orderId)
    {
        orderId = 0;
        uint256[MAX_ORDERS] memory depositIds = users[_user].depositIds;
        for (uint256 i = 0; i < MAX_ORDERS; i++) {
            if (
                orders[depositIds[i]].poolId == _poolId &&
                orders[depositIds[i]].pairedPoolId == _pairedPoolId &&
                orders[depositIds[i]].isBuyOrder == _isBuyOrder
            ) {
                orderId = depositIds[i];
                break;
            }
        }
    }

    // get position id from borrowIds[] in user, returns 0 if not found

    function getPositionId(
        address _user,
        int24 _poolId
    )
        internal view
        returns (uint256 positionId_)
    {
        positionId_ = 0;
        uint256[MAX_POSITIONS] memory positionIds = users[_user].borrowIds;
        for (uint256 i = 0; i < MAX_POSITIONS; i++) {
            if (positions[positionIds[i]].borrower == _borrower &&
                positions[positionIds[i]].poolId == _poolId &&
                positions[positionIds[i]].borrowedAssets > 0) {
                positionId_ = positionIds[i];
                break;
            }
        }
    }

    /////**** Functions used in tests and in UI ****//////

    function setPriceFeed(uint256 _newPrice)
        public
    {
        priceFeed = _newPrice;
    }
    
    // Add manual getter for positionIds in Order, used in setup.sol for tests
    // function getOrderPositionIds(uint256 _orderId)
    //     public view
    //     returns (uint256[MAX_POSITIONS] memory)
    // {
    //     return orders[_orderId].positionIds;
    // }
    
    // Add manual getter for depositIds for User, used in AX_ORDERSreachedsetup.sol for tests
    function getUserDepositIds(address user)
        public view
        returns (uint256[MAX_ORDERS] memory)
    {
        return users[user].depositIds;
    }

    // Add manual getter for borroFromIds for User, used in setup.sol for tests
    function getUserBorrowFromIds(address user)
        public view
        returns (uint256[MAX_POSITIONS] memory)
    {
        return users[user].borrowFromIds;
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

    //////////********* Pure functions *********/////////
    
    // check that order has consistent limit prices
    // if buy order, limit price must be lower than limit paired price
    // if sell order, limit price must be higher than limit paired price
    
    function consistent(
        int24 _poolId,
        int24 _pairedPoolId,
        bool _isBuyOrder
    )
        public pure
        returns (bool)
    {
        
        if (_isBuyOrder) return (_pairedPoolId >= _poolId);
        else return (_pairedPoolId <= _poolId);
    }

    function nearBy(int24 _poolId)
        public pure
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

     function calibrate(
        int24 _poolId,
        uint256 availableAssets
    ) 
        view private
        returns (positionNumber_)
    {
        uint256 nbPositions = _substract(pools[_poolId].topPosition, pools[_poolId].bottomPositionRow, "err 011", !RECOVER);

        for (uint256 i = pool.bottomOrder; i < pool.topOrder; i++) {
            if(order[pool.orderIds[i]].quantity > 0) nbOrders++;
        }

        if (nbOrders == 0) {
            revert("No liquidity");
        }
        else if (nbPositions == 0) {
            positionNumber_ = 0;
        }
        else if (nbOrders >= nbPositions) {
            positionNumber_ = 1;
        }
        else {
            positionNumber_ = MAX_OPERATIONS.maxi((nbPositions / nbOrders) + 1);
        }
    }
    
    function convert(
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

    function minDeposit(bool _isBuyOrder)
        public pure
        returns (uint256)
    {
        _isBuyOrder = true ? MIN_DEPOSIT_QUOTE : MIN_DEPOSIT_BASE;
    }

    function convertToPoolType(bool _isBuyOrder)
        private pure
        returns (PoolIn)
    {
        return _isBuyOrder ? PoolIn.quote : PoolIn.base;
    }

    function convertToInQuote(PoolIn _poolToken)
        private pure
        returns (bool)
    {
        if (_poolToken == PoolIn.quote) return true;
        else if (_poolToken == PoolIn.base) return false;
        else revert("Pool has no orders");
    }

}