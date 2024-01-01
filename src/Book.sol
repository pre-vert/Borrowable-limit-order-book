// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

/// @title A lending order book for ERC20 tokens
/// @author Pré-vert
/// @notice Allows users to place limit orders on the book, take orders, and borrow quote assets
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
    bool constant private TO_POSITION = true; // applies to position (true) or order (false)
    bool constant private ROUNDUP = true; // round up in conversions
    uint256 public constant ALPHA = 5 * WAD / 1000; // IRM parameter = 0.005
    uint256 public constant BETA = 15 * WAD / 1000; // IRM parameter = 0.015
    // uint256 public constant GAMMA = 10 * WAD / 1000; // IRM parameter =  0.010
    uint256 public constant FEE = 20 * WAD / 1000; // interest-based liquidation fee for maker =  0.020 (2%)
    uint256 public constant YEAR = 365 days; // number of seconds in one year
    bool private constant RECOVER = true; // how negative uint256 following substraction are handled
    enum PoolIn {quote, base, none}

    struct Pool {
        mapping(uint256 => uint256) orderIds;  // index => order id in the pool
        mapping(uint256 => uint256) positionIds;  // index => position id in the pool
        uint256 deposits; // assets deposited in the pool
        uint256 minDeposits; // min deposits
        uint256 borrows; // assets borrowed from the pool
        uint256 lastTimeStamp; // # of periods since last time instant interest rate has been updated in the pool
        uint256 timeWeightedRate; // time-weighted average interest rate since inception of the pool, applied to borrows
        uint256 timeUrWeightedRate; // time-weighted and UR-weighted average interest rate since inception of the pool, applied to deposits
        uint256 topOrder; // row index of orderId on the top of orderIds mapping to add order id, starts at 0
        uint256 bottomOrder; // row index of last orderId deleted from orderIds mapping, starts at 0
        uint256 topPosition; // row index of positionId on the top of positionIds mapping to add position id, starts at 0
        uint256 bottomPosition; // row index of last positionId deleted from positionIds mapping, starts at 0
    }
    
    // orders and borrows by users
    struct User {
        uint256[MAX_ORDERS] depositIds; // orders id in mapping orders
        uint256[MAX_POSITIONS] borrowIds; // positions id in mapping positions, only in quote tokens
    }
    
    struct Order {
        int24 poolId; // pool id of order
        address maker; // address of maker
        int24 pairedPoolId; // pool id of paired order
        uint256 quantity; // assets deposited (quoteToken for buy orders, baseToken for sell orders)
        uint256 orderWeightedRate; // time-weighted and UR-weighted average interest rate for supply since initial deposit
        bool isBuyOrder; // true for buy orders, false for sell orders
    }

    // borrowing positions
    struct Position {
        int24 poolId; // pool id in mapping orders, from which assets are borrowed
        address borrower; // address of the borrower
        uint256 borrowedAssets; // quantity of assets borrowed (quoteToken for buy orders, baseToken for sell orders)
        uint256 positionWeightedRate; // time-weighted average interest rate for the position since its creation
        //bool inQuote; // asset's type
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
        int24 _poolId,
        uint256 _quantity,
        int24 _pairedPoolId,
        bool _isBuyOrder
    )
        external
        moreThanZero(_quantity)
    {
        PoolIn poolType = _poolType(_poolId); // in quote or base tokens, or none if the pool is empty
        bool profit = profitable(_poolId); // whether filling orders from pool is profitable for takers
        
        // deposit becomes take if profitable, which may liquidate positions
        if (!_sameType(_isBuyOrder, poolType) && profit) take(_poolId, _quantity);

        // deposit only if order's and pool's asset type match and order can't be immediately taken
        else if (_sameType(_isBuyOrder, poolType) && !profit) {
            uint256 orderId_ = _deposit(_poolId, _quantity, _pairedPoolId, _isBuyOrder);
            emit Deposit(msg.sender, _poolId, orderId_, _quantity, limitPrice[_poolId], _pairedPoolId, limitPrice[_pairedPoolId], _isBuyOrder);
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
        Order order = orders[orderId];

        // reverts if position is not found
        require(order.quantity > 0, "No order");

        // order's asset type must match pool's asset type
        require(order.isBuyOrder == inQuote, "asset mismatch_6");

        // withdraw no more than deposit net of min deposit if partial
        require(_removable(orderId_, _quantity), "Remove too much_1");

        // if deposits in quote tokens (borrowable token)
        if (inQuote) {
        
            // update pool's total borrow, total deposits
            // increment TWIR/TUWIR before changes in pool's UR and calculating user's excess collateral
            _updateAggregates(_poolId);
        
            // add interest rate to existing deposit
            // update TUWIR_t to TUWIR_T to reset deposit's interest rate to zero
            _addInterestRateToDeposit(orderId_);

            // withdraw no more than available assets in pool
            require(_quantity <= _poolAvailableAssets(_poolId), "Remove too much_2");
        }

        // if deposits in base tokens (collateral token)
        else
        {
            // update user's required collateral with accrued interest rate
            _updateUserRequiredCollateral(msg.sender);

            // excess collateral must remain positive after removal
            require(_quantity <= _getUserExcessCollateral(msg.sender), "Remove too much_3");
        }

        // reduce quantity in order, possibly to zero
        orders[orderId].quantity -= _quantity;

        // decrease total deposits in pool
        pools[_poolId].deposits -= _quantity;

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

        // revert if borrow base tokens or profitable to take
        require(inQuote && !profitable(_poolId) , "Cannot borrow");

        // cannot borrow more than available assets in pool
        require(_quantity <= _poolAvailableAssets(_poolId), "Borrow too much_1");

        // required collateral (in base tokens) to borrow _quantity i(n quote tokens)
        uint256 requiredCollateral = convert(_quantity, limitPrice[_poolId], inQuote, ROUNDUP);

        // update pool's total borrow, total deposits
        // increment TWIR before calculating user's excess collateral
        _updateAggregates(_poolId);

        // update borrower's excess collateral with accrued interest rate
        _updateUserRequiredCollateral(msg.sender);

        // check borrowed amount is collateralized enough by borrower's own orders
        require(requiredCollateral <= getUserExcessCollateral(msg.sender), "Borrow too much_2");

        // find if borrower has already a position in pool
        positionId_ = getPositionId(msg.sender, _poolId);

        // if position already exists, add interest rate and new quantity to borrow
        if (positionId_ != 0) _AddBorrowToPosition(positionId_, _quantity);

        // if position is new, create borrowing position in positions
        // add position id to borrowIds[] in user
        // add position id to positionIds[] in pool
        // returns id of new position or updated existing one
        else positionId_ = _createPosition(_poolId, msg.sender, _quantity);

        // add _quantity to pool's total borrow (double check asset type before)
        pools[_poolId].borrows += _quantity;

        _transferTo(msg.sender, _quantity, inQuote);

        emit Borrow(msg.sender, _poolId, positionId, _quantity, limitPrice[_poolId]);
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
        // onlyBorrower(_positionId)
    {
        Pool memory pool = pools[_poolId];

        // repay must be in quote tokens
        require(convertToInQuote(_poolType(_poolId)), "Non borrowable pool");

        // which position in pool user repays
        uint256 positionId_ = getUserPositionIdInPool(msg.sender, _poolId);

        // check user is a borrower in pool
        require(positions[positionId_].borrowedAssets > 0, "No borrow");

        // update pool's total borrow and total deposits
        // increment time-weighted rates with IR based on UR before repay
        _updateAggregates(_poolId);

        // add interest rate to borrowed quantity
        // update TWIR_t to TWIR_T to reset interest rate to zero
        // add interest rate to borrowed quantity
        _addInterestRateToPosition(positionId_);

        require(_quantity <= positions[positionId_].borrowedAssets, "Repay too much");

        // decrease borrowed assets in position, possibly to zero
        positions[positionId_].borrowedAssets -= _quantity;

        // decrease borrowed assets in pool's total borrow (check no asset mismatch)
        pools[_poolId].borrows = pools[_poolId].borrows - _quantity;

        _transferFrom(msg.sender, _quantity, inQuote);
        
        emit Repay(msg.sender, _poolId, positionId, _quantity);
    }

    /// @inheritdoc IBook
    function take(
        uint256 _poolId,
        uint256 _takenQuantity
    )
        public
        moreThanZero(_takenQuantity)
        poolHasAssets(_poolId)
        poolHasOrders(_poolId)
    {
        Pool memory pool = pools[_poolId];
        inQuote = convertToInQuote(_poolType(_poolId));
        
        // taking is allowed for profitable trades only
        require(profitable(_poolId), "Trade must be profitable");

        // cannot take more than available assets
        require(_takenQuantity <= pool.deposits - pool.borrows, "take too muche_00");
        
        bool inQuote = convertToInQuote(_poolType(_poolId));

        //****** If quote tokens: can be borrowed but cannot serve as collateral ******//

        if (inQuote) {

            // update pool's total borrow and total deposits
            // increment time-weighted rates with IR based on UR before repay
            _updateAggregates(_poolId);

            // pool's utilization rate before (debts cancelation)
            uint256 utilizationRate = getUtilizationRate(_poolId);

            // nothing to take if 100 % utilization rate
            require (utilizationRate < 1 * WAD, "Nothing to take");

            //*** Liquidation phase ***/
            
            // min canceled debt = taken quantity * UR / (1-UR)
            uint256 minCanceledDebt = _takenQuantity.mulDivDown(utilizationRate, 1 - utilizationRate);
                
            // cumulated liquidated quote assets
            uint256 liquidatedQuoteAssets = 0;

            // number of liquidation iterations
            uint256 round = 0;
            
            // pool.topPosition is first available slot for positions in pool's positionIds
            // pool.bottomPosition is first possible slot for positions to be liquidated
            // pool.bottomPosition == pool.topPosition means that there is noting more to liquidate
            // Example: a first borrow is recorded at topPosition = 0; topPosition is incremented to 1
            // In a liquidation event, bottomPosition starts at 0 < 1, finds a position to close
            // then increments to 1 and stops as 1 == 1
            
            for (uint256 row = pool.bottomPosition; row < pool.topPosition; row++) {

                round++;
                
                // which position in pool is closed
                uint256 positionId = pool.positionIds[row];

                // check user has still borrowed assets in pool
                if (positions[positionId].borrowedAssets == 0) continue;

                // add interest rate to borrowed quantity
                // update TWIR_t to TWIR_T to reset interest rate to zero
                _addInterestRateToPosition(positionId);

                // add liquidated assets to cumulated liquidated assets
                liquidatedQuoteAssets += positions[positionId].borrowedAssets;

                // decrease borrowed assets in pool's total borrow (check no asset mismatch)
                pools[_poolId].borrows -= positions[positionId].borrowedAssets;

                // decrease borrowed assets to zero
                positions[_positionId].borrowedAssets = 0;

                // if enough assets are liquidated by taker (given the take's size), stop
                // can liquidate more than strictly necessary
                if (liquidatedQuoteAssets >= minCanceledDebt) break;
            }

            // update pool's bottom position (first row at which a position potentially exists)
            
            if (orders[orderId].quantity == 0) pool.bottomPosition += round;
            else pool.bottomPosition += round - 1;

            //*** Close orders phase ***/

            // remaining (quote) assets to redeem against canceled debt
            // exact amount of redeemed assets for liquidated assets
            uint256 remainingRedeemable = liquidatedQuoteAssets;
            
            // remaining (quote) assets to take
            // exact amount of redeemed assets for taken assets
            uint256 remainingTakenAssets = _takenQuantity;

            // number of closing iterations
            uint256 round = 0;

            // iterate on orders

            for (uint256 row = pool.bottomOrder; row < pool.topOrder; row++) {

                round++;
                
                // which order in pool is closed
                uint256 orderId = pool.orderIds[row];

                uint256 orderSize = orders[orderId].quantity;

                // check user has still deposits in pool
                if (orderSize == 0) continue;

                // add interest rate to deposit
                // update TUWIR_t to TUWIR_T to reset interest rate to zero
                _addInterestRateToDeposit(orderId);

                //*** redeem orders for canceled debt if any remaining ***//

                // how much deposit can be redeemed against canceledDebt
                uint256 redeemable = 0;

                if (remainingRedeemable > 0) {

                    // if deposit exceeds remaining redeemable, some deposit's assets will remain
                    if (orderSize >= remainingRedeemable) {
                        redeemable = remainingRedeemable;
                        remainingRedeemable = 0;
                    }

                    // if deposit is smaller than remaining redeemable, deposit' assets are fully depleted
                    else {
                        redeemable = orderSize;
                        remainingRedeemable -= orderSize;
                    }
                }

                //*** redeem orders for taken assets if any remaining ***//

                // what taker can take from remaining assets in deposit
                uint256 takable = 0;
                
                if (orderSize > redeemable && remainingTakenAssets > 0) {

                    // if remaining deposit still exceeds taker's need
                    if (orderSize - redeemable >= remainingTakenAssets) {
                        takable = remainingTakenAssets;
                        remainingTakenAssets = 0;
                    }
                    // otherwise finish depleting order's assets
                    else {
                        takable = orderSize - redeemable;
                        remainingTakenAssets -= takable;
                    }                   
                }

                // decrease pool's total deposits (check no asset mismatch)
                pools[_poolId].deposits -= redeemable + takable;

                // decrease assets in order, possibly down to zero
                orders[orderId].quantity -= redeemable + takable;

                //*** Place base assets in a sell order on behalf of maker ***//
                
                // base assets received by maker
                uint256 makerReceivedAssets = convert(redeemable + takable, limitPrice[_poolId], inQuote, !ROUNDUP);
                
                // check if an identical order exists already, if so increase deposit, else create
                // pairedPoolId: paired pool with sell orders, higher pool id and higher price
                uint256 pairedOrderId = _getOrderIdInDepositIdsInUsers(
                    orders[orderId].maker,
                    orders[orderId].pairedPoolId,
                    !inQuote
                );

                // if new sell order, create order
                if (pairedOrderId_ == 0) 
                
                    // - add new orderId in depositIds[] in users
                    // - add new orderId on top of orderIds[] in pool
                    pairedOrderId_ = _createOrder(
                        _poolId + 1,
                        orders[orderId].maker,
                        _poolId,
                        makerReceivedAssets,
                        !inQuote
                    );
                
                // if existing order (even with zero quantity):
                else {

                    // add new quantity to existing deposit
                    orders[pairedOrderId_].quantity += makerReceivedAssets;
                }

                // increase pool's total deposits (double check asset type before)
                pools[orders[pairedOrderId_].poolId].deposits += makerReceivedAssets;

                // exit iteration on orders if all debt has been redeemed and take size is fully filled
                if (remainingRedeemable == 0 && remainingTakenAssets == 0) break;
            }

            // update pool's bottom order (first row at which an order potentially exists)

            if (orders[orderId].quantity == 0) pool.bottomPosition += round;
            else pool.bottomPosition += round - 1;
        }

        //****** If take base tokens: can serve as collateral but cannot be borrowed ******//

        else {


        

        
        }

        _transferTo(msg.sender, _takenQuantity, inQuote);

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
        int24 _poolId,
        uint256 _quantity,
        int24 _pairedPoolId,
        bool _isBuyOrder
    )
        internal
        returns (uint256 orderId_)
    {
        // revert if limit price and paired limit price are in wrong order
        require(consistent(_poolId, _pairedPoolId, _isBuyOrder), "Inconsistent limit prices");

        // revert if _poolId or _pairedPoolId has no price and is not adjacent to a pool id with a price        
        require(nearBy(_poolId), "Limit price too far");
        require(nearBy(_pairedPoolId), "Paired price too far");
        
        // revert if non borrowable greater than deposit
        require(_quantity < minDeposit(_isBuyOrder), "too much non borrowable");
        
        // if buy order market, update pool's total borrow and total deposits
        // increment TWIR and TUWIR before accounting for changes in UR and future interest rate
        // if deposits in quote tokens (borrowable token)
        if (_isBuyOrder) _updateAggregates(_poolId);

        // return order id if maker already supplies in pool, even with zero quantity, if not return zero
        orderId_ = _getOrderIdInDepositIdsInUsers(msg.sender, _poolId, _isBuyOrder);

        // if new order:
        // - add new orderId in depositIds[] in users
        // - add new orderId on top of orderIds[] in pool
        if (orderId_ == 0) orderId_ = _createOrder(_poolId, msg.sender, _pairedPoolId, _quantity, _isBuyOrder);
        
        // if existing order:
        else {

            // if buy order market, add interest rate to existing borrowable deposit
            // update TUWIR_t to TUWIR_T to reset interest rate to zero
            if (_isBuyOrder) _addInterestRateToDeposit(_orderId);

            // add new quantity to existing deposit
            orders[_orderId].quantity += _quantity;
        }

        // add new quantity to total deposits in pool (double check asset type before)
        pools[_poolId].deposits += _quantity;

        _transferFrom(msg.sender, _quantity, _isBuyOrder);
    }
        
    // import order id when maker already supplies in pool with same paired limit price
    // increase deposit by accrued interest rate
    // reset R_t to R_T
    // called by _deposit() or take() ? for self-replacing order
    // double check same type assets
    
    function _increaseOrder(
        uint256 _orderId,
        uint256 _quantity
    )
        internal
    {
        // add interest rate to existing borrowable deposit
        // update TUWIR_t to TUWIR_T to reset interest rate to zero
        // add interest rate to deposit and pool's total borrow
        _addInterestRateToDeposit(_orderId);

        // add additional quantity to existing deposit
        orders[_orderId].quantity += _quantity;
    }

    // create new order
    // add new orderId in depositIds[] in users
    // add new orderId on top of orderIds[] in pool
    // update pool's total deposit
    // returns order id
    // called by _deposit() and take() for self-replacing order
    
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
        uint256 subweightedRate = 1;
        if (_isBuyOrder) dubweightedRate = pools[_poolId].timeUrWeightedRate;
        
        // create new order in orders
        Order memory newOrder = Order(
            _poolId,
            _maker,
            _pairedPoolId,
            _quantity,
            dubweightedRate,
            _isBuyOrder
        );
        newOrderId_ = lastOrderId;
        orders[newOrderId_] = newOrder;
        lastOrderId ++;

        // add new orderId in depositIds[] in users
        // revert if max orders reached
        _addOrderIdInDepositIdsInUser(_maker, newOrderId);

        // add new orderId on top of orderIds[] in pool
        _addOrderIdToOrderIdsInPool(_poolId, newOrderId);
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
                positions[_positionId].borrowedAssets += accruedInterestRate_;

                // update pool's total borrow (check asset type before)
                pools[_poolId].borrows += accruedInterestRate_;

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
                    orders[orderId].quantity = _substract(orders[_orderId].quantity, remainingCollateralToSeize, "err 003", !RECOVER);
                    uint256 canceledDebt = convert(remainingCollateralToSeize, _price, !inQuote, ROUNDUP);
                    // handle rounding errors
                    positions[_positionId].borrowedAssets = _substract(
                        positions[_positionId].borrowedAssets, canceledDebt, "err 001", RECOVER);
                    remainingCollateralToSeize = 0;
                    break;
                } else {
                    // borrower's order is fully seized, reduce order quantity to zero
                    orders[orderId].quantity = _substract(orders_orderId].quantity, orderQuantity, "err 003", !RECOVER);
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
        // add interest rate to borrowed quantity
        // update TWIR_t to TWIR_T to reset interest rate to zero
        _addInterestRateToPosition(_positionId);
        
        uint256 canceledDebt = positions[_positionId].borrowedAssets.mini(_remainingCash);

        // decrease borrowed assets in position, possibly to zero (check non negativity)
        positions[_positionId].borrowedAssets -= canceledDebt;

        // decrease borrowed assets in pool
        pools[_poolId].borrows = _substract(pools[_poolId].borrows, _quantity, "err 006", !RECOVER);
        //_decreasePoolBorrowBy(positions[positionId].poolId, canceledDebt, positions[positionId].inQuote);

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
        
        // update pool's total borrow and total deposits
        // increment time-weighted rates with IR before liquidate (necessary for up-to-date excess collateral)
        _updateAggregates(_poolId);

        _updateUserRequiredCollateral(position.borrower);
        
        require(getUserExcessCollateral(position.borrower) >= 0, "Borrower excess collateral is positive");

        // multiply fee rate by borrowed quantity = fee
        uint256 totalFee = FEE.wMulUp(position.borrowedAssets);

        // add fee to borrowed quantity (interest rate already added), update pool's total borrow
        positions[_positionId].borrowedAssets += _totalFee;

        // add fee to pool's total borrow (check asset type)
        pools[_poolId].borrows += totalFee;

        // seize collateral equivalent to borrowed quantity + interest rate + fee
        uint256 seizedCollateral = _closePosition(_positionId, positions[_positionId].borrowedAssets, priceFeed);

        // Liquidation means less assets deposited (seized collateral) and less assets borrowed (canceled debt)
        if (seizedCollateral > 0) {
            // total deposits from borrowers' side are reduced by 2 ETH
            pools[_poolId].deposits = _substract(pools[_poolId].deposits, seizedCollateral, "err 004", RECOVER);
            // if 2 ETH are seized, 2*p = 4000 USDC of debt are canceled
            uint256 conversion_ = convert(seizedCollateral, borrowedOrder.price, !inQuote, !ROUNDUP);
            pools[poolId].borrows = _substract(pools[poolId].borrows, conversion_, "err 006", !RECOVER);
            // transfer seized collateral to maker
            _transferTo(borrowedOrder.maker, seizedCollateral, !inQuote); // ou position.borrower ?
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

    // increase borrow by quantity + accrued interest rate
    // reset R_t to R_T

    function _AddBorrowToPosition(
        int24 _positionId,
        uint256 _quantity
    )
        internal
    {
        // add interest rate to borrowed quantity
        // update TWIR_t to TWIR_T to reset interest rate to zero
        _addInterestRateToPosition(positionId_);

        // add additional borrow to borrowed quantity
        positions[_positionId].borrowedAssets += _quantity;
    }

    // add position id to borrowIds[] in users
    // add position id to borrows[] in pools
    // returns existing or new position id
    // _poolId: pool id from which assets are borrowed
    
    function _createPosition(
        int24 _poolId,
        address _borrower,
        uint256 _quantity
    )
        internal
        returns (uint256 positionId_)
    {
        uint256 subweightedRate = 1;
        if (_isBuyOrder) subweightedRate = pools[_poolId].timeWeightedRate;
        
        // create position in positions, return new position id
        Position memory newPosition = Position(
            _poolId,
            _borrower,
            _quantity,
            subWeightedRate, // initialize interest rate
        );
        positionId_ = lastPositionId;
        positions[positionId_] = newPosition;
        lastPositionId++;

        // add new position id to borrowIds[] in users, 
        // revert if user has too many open positions (max position reached)
        _addPositionIdInBorrowIdsInUser(msg.sender, newPositionId);

        // add new position id on top of positionIds[] in pool
        _AddPositionIdToPositionIdsInPool(poolId, newPositionId);
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

    // check asset type, decrease non borrowables in pool
    // function _decreasePoolNonBorrowablesBy(
    //     int24 _poolId,
    //     uint256 _quantity,
    //     bool _inQuote        
    // )
    //     internal
    // {
    //     if (_sameType(_poolType(_poolId), _inQuote)) {
    //         _substract(pools[_poolId].nonBorrowables, _quantity, "err 009", !RECOVER);
    //     }
    //     else revert("asset mismatch_5");
    // }

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

        // depoit interest rate is borrow rate scaled scaled down by UR
        uint256 depositRate = borrowRate.mulDivDown(getUtilizationRate(_poolId));

        // add interest rate to time- and UR-weighted interest rate
        pools[_poolId].timeUrWeightedRate += depositRate;

        // add interest rate to total deposits in pool
        pools[_poolId].deposits += depositRate.wTaylorCompoundedDown().wMulDown(pools[_poolId].deposits);

        pools[_poolId].lastTimeStamp = block.timestamp;
    }

    // get user's excess collateral in the quote or base token
    // excess collateral = total deposits - borrowed assets - needed collateral
    // needed collateral is computed with interest rate added to borrowed assets
    // _inQuote: asset type of required collateral

    function getUserExcessCollateral(address _user)
        public
        returns (uint256) {
        
        _substract(
            getUserTotalDeposits(_user, false),
            getUserRequiredCollateral(_user),
            "err 009",
            !RECOVER
        );
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
        Order order = orders[orderId];

        // add interest rate multiplied by existing quantity to deposit
        orders[orderId].quantity += depositInterestRate(order.poolId_, _orderId).wMulDown(order.quantity);

        // update TUWIR_t to TUWIR_T to reset interest rate to zero
        orders[orderId].orderWeightedRate = pools[order.poolId].timeUrWeightedRate;
    }

    // calculate accrued interest rate for borrowed quantity
    // update TWIR_t to TWIR_T to reset interest rate to zero
    // add interest rate to borrowed quantity
    
    function _addInterestRateToPosition(uint256 _positionId)
        internal
    {
        Position position = positions[_positionId];

        // multiply interest rate with borrowed quantity and add to borrowed quantity
        positions[_positionId].borrowedAssets += borrowInterestRate(position.poolId, _positionId).wMulUp(position.borrowedAssets);

        // update TWIR_t to TWIR_T in position to reset interest rate to zero
        positions[_positionId].positionWeightedRate = pools[position.poolId].timeWeightedRate;
    }

    // required collateral in base assets needed to secure a user's debt in quote assets
    // update borrow by adding interest rate to debt (_updateAggregates() has been called before)

    function _updateUserRequiredCollateral(address _borrower)
        internal
    {
        uint256[MAX_POSITIONS] memory borrowIds_ = users[_borrower].borrowIds;
        for (uint256 i = 0; i < MAX_POSITIONS; i++) {

            uint256 positionId = borrowedIds[i]; // position id from which user borrows assets

            // look for borrowing positions to calculate required collateral
            if (_hasBorrowedAssets(positionId)) {
                // add interest rate to borrowed quantity, update TWIR_t to TWIR_T to reset interest rate to zero
                // add interest rate to borrowed quantity
                _addInterestRateToPosition(positions[positionId].poolId, positionId);
            }
        }
    }

    // required collateral needed to secure user's debt in quote assets
    // _inQuote: asset type of required collateral = false = in base tokens

    function getUserRequiredCollateral(address _borrower)
        public
        returns (uint256 totalNeededCollateral_)
    {
        totalNeededCollateral_ = 0;
        uint256[MAX_POSITIONS] memory borrowIds_ = users[_borrower].borrowIds;

        for (uint256 i = 0; i < MAX_POSITIONS; i++) {
            Position position = positions.[borrowedIds[i]];
            if (position.borrowedAssets > 0) {
                totalNeededCollateral += 
                convert(position.borrowedAssets, limitPrice[position.poolId], _poolType(position.poolId), ROUNDUP);
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
            if (orders[orderId].poolId == _poolId && orders[orderId].isBuyOrder == _inQuote) {
                orderId_ = orderId;
                break;
            }
        }
    }

    function getUserPositionIdInPool(
        address _user,
        int24 _poolId
    )
        internal view
        returns (uint256 positionId_)
    {
        uint256[MAX_POSITIONS] memory borrowIds = users[_user].borrowIds;
        positionId_ = 0;
        for (uint256 i = 0; i < MAX_POSITIONS; i++) {
            if (positions[borrowIds[i]].poolId == _poolId) {
                positionId_ = borrowIds[i];
                break;
            }
        }
    }
    
    // get UR = total borrow / total net assets in pool (in WAD)

    function getUtilizationRate(int24 _poolId)
        public view
        returns (uint256 utilizationRate_)
    {
        Pool pool = pools[_poolId];
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
            if (orders[depositIds[i]].isBuyOrder == _inQuote) {
                totalDeposit += orders[depositIds[i]].quantity;
            }   
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
        uint256 available = orders[_orderId].quantity;
        uint256 minDepose = minDeposit(order.isbuyorder);

        if (_quantity == available || _quantity + minDepose < available) return true;
        else return false;
    }

    function _poolAvailableAssets(int24 _poolId)
        internal view
        returns (uint256)
    {
        return _substract(pools[_poolId].deposits, pools[_poolId].borrows, "err 009", !RECOVER);
    }
    
    // return false if desired quantity is not possible to borrow
    // function _borrowable(
    //     uint256 _orderId,
    //     uint256 _quantity // borrowed quantity
    // )
    //     internal view
    //     returns (bool)
    // {
    //     uint256 depositedAssets = orders[_orderId].quantity;
    //     uint256 lentAssets = getAssetsLentByOrder(_orderId);
    //     uint256 availableAssets = _substract(depositedAssets, lentAssets, "err 009", RECOVER);
    //     uint256 minDepose = minDeposit(orders[_orderId].isBuyOrder); 

    //     if (_quantity + minDepose <= availableAssets) return true;
    //     else return false;
    // }

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

    // compute interest rate since start of deposit between t and T
    // exp(TWIR_T - TWIR_t) - 1 is computed using a 3rd order Taylor approximation

    function depositInterestRate(
        int24 _poolId,
        uint256 _orderId
    )
        internal view
        returns (uint256)
    {
        uint256 rateDiff = _substract(pools[_poolId].timeUrWeightedRate, users[_orderId].orderWeightedRate, "err 001", !RECOVER);
        if (rateDiff > 0) return rateDiff.wTaylorCompoundedDown();
        else return 0;
    }
    
    // compute interest rate since start of borrowing position between t and T
    // exp(TWIR_T - TWIR_t) - 1 is computed using a 3rd order Taylor approximation

    function borrowInterestRate(
        int24 _poolId,
        uint256 _positionId
    )
        internal view
        returns (uint256)
    {
        uint256 rateDiff = _substract(pools[_poolId].timeWeightedRate, positions[_positionId].positionWeightedRate, "err 000", !RECOVER);
        if (rateDiff > 0) return rateDiff.wTaylorCompoundedUp();
        else return 0;
    }

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

    // function _getBorrowFromIdsRowInUsers(
    //     address _borrower,
    //     uint256 _orderId // in the borrowFromIds array of users
    // )
    //     internal view
    //     returns (uint256 borrowFromIdsRow)
    // {
    //     borrowFromIdsRow = ABSENT;
    //     uint256[MAX_BORROWS] memory borrowFromIds = users[_borrower].borrowFromIds;
    //     for (uint256 i = 0; i < MAX_BORROWS; i++) {
    //         if (borrowFromIds[i] == _orderId) {
    //             borrowFromIdsRow = i;
    //             break;
    //         }
    //     }
    // }

    // returns order id if order already exists in pool, even with zero quantity
    // by assumption, maker can create only one deposit in a pool and therefore can only choose one paired price
    // CHECK THIS ASSUMPTION ACTUALLY HOLD !
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
            if (orders[depositIds[i]].poolId == _poolId && orders[depositIds[i]].isBuyOrder == _isBuyOrder)
            {
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