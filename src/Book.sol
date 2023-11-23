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

    /// @notice provides core public functions (deposit, withdraw, take, borrow, repay)
    /// + internal functions (liquidateAssets, liquidatePositions, educeUserBorrow, ...) + view functions
    
    IERC20 public quoteToken;
    IERC20 public baseToken;
    uint256 constant public MAX_POSITIONS = 2; // How many positions can be borrowed from a single order
    uint256 constant public MAX_ORDERS = 2; // How many buy and sell orders can be placed by a single address
    uint256 constant public MAX_BORROWINGS = 2; // How many positions a borrower can open on both sides of the book
    uint256 constant public MIN_DEPOSIT_BASE = 2 * WAD; // Minimum deposited base tokens to be received by takers
    uint256 constant public MIN_DEPOSIT_QUOTE = 100 * WAD; // Minimum deposited quote tokens to be received by takers
    uint256 constant private ABSENT = type(uint256).max; // id for non existing order or position in arrays
    uint256 public constant ALPHA = 5 * WAD / 1000; // IRM parameter = 0.005
    uint256 public constant BETA = 15 * WAD / 1000; // IRM parameter = 0.015
    uint256 public constant GAMMA = 10 * WAD / 1000; // IRM parameter=  0.010
    uint256 public constant YEAR = 365 days; // number of seconds in one year

    struct Order {
        address maker; // address of the maker
        bool isBuyOrder; // true for buy orders, false for sell orders
        uint256 quantity; // assets deposited (quoteToken for buy orders, baseToken for sell orders)
        uint256 price; // price of the order
        uint256[MAX_POSITIONS] positionIds; // stores positions id in mapping positions who borrow from order
    }

    // makers and borrowers
    struct User {
        uint256[MAX_ORDERS] depositIds; // stores orders id in mapping orders in which borrower deposits
        uint256[MAX_BORROWINGS] borrowFromIds; // stores orders id in mapping orders from which borrower borrows
    }

    // borrowing positions
    struct Position {
        address borrower; // address of the borrower
        uint256 orderId; // stores orders id in mapping orders, from which assets are borrowed
        uint256 borrowedAssets; // quantity of assets borrowed (quoteToken for buy orders, baseToken for sell orders)
        uint256 timeWeightedRate; // time-weighted average interest rate for the position
    }

    mapping(uint256 orderId => Order) public orders;
    mapping(address user => User) internal users;
    mapping(uint256 positionId => Position) public positions;

    uint256 public lastOrderId = 1; // first id of the last order in orders (0 for non existing orders)
    uint256 public lastPositionId = 1; // id of the last position in positions (0 for non existing positions)
    uint256 public lastTimeStamp = block.timestamp; // # of periods since last time instant intrest rates have been updated
    uint256 private quoteTimeWeightedRate = 0; // time-weighted average interest rate for the buy order market (quoteToken)
    uint256 private baseTimeWeightedRate = 0; // time-weighted average interest rate for sell order market (baseToken)

    uint256 public totalQuoteAssets = 0; // total quote assets deposited in buy order market
    uint256 public totalQuoteBorrow = 0; // total quote assets borrowed in buy order market
    uint256 public totalBaseAssets = 0; // total base assets deposited in sell order market
    uint256 public totalBaseBorrow = 0; // total base assets borrowed in sell order market

    constructor(address _quoteToken, address _baseToken) {
        quoteToken = IERC20(_quoteToken);
        baseToken = IERC20(_baseToken);
    }

    modifier orderHasAssets(uint256 _orderId) {
        _revertIfOrderHasZeroAssets(_orderId);
        _;
    }

    modifier positionExists(uint256 _positionId) {
        _revertIfPositionDoesntExist(_positionId);
        _;
    }

    modifier isPositive(uint256 _var) {
        revertIfNonPositive(_var);
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
        uint256 _price,
        bool _isBuyOrder
    )
        external
        isPositive(_price)
    {
        // check if an identical order exists already, if so increase deposit, else create
        uint256 orderId = _getOrderIdInDepositIdsInUsers(msg.sender, _price, _isBuyOrder);
        if (orderId != 0) {
            _increaseOrderBy(orderId, _quantity);
        } else {
            // minimum amount deposited
            revertIfSuperiorTo(minDeposit(_isBuyOrder), _quantity);
            // add order to orders, output the id of the new order
            uint256 newOrderId = _addOrderToOrders(msg.sender, _isBuyOrder, _quantity, _price);
            // add new orderId in depositIds array in users
            _addOrderIdInDepositIdsInUsers(newOrderId, msg.sender);            
        }
        _incrementTimeWeightedRates();
        _increaseTotalAssets(_quantity, _isBuyOrder);
        _transferFrom(msg.sender, _quantity, _isBuyOrder);
        emit Deposit(msg.sender, _quantity, _price, _isBuyOrder);
    }

    /// @inheritdoc IBook
    function withdraw(
        uint256 _removedOrderId,
        uint256 _removedQuantity
    )
        external
        orderHasAssets(_removedOrderId)
        isPositive(_removedQuantity)
        onlyMaker(_removedOrderId)
    {
        require(outable(_removedOrderId, _removedQuantity), "Remove too much assets");

        Order memory removedOrder = orders[_removedOrderId];

        // Remaining total deposits must be enough to secure maker's existing borrowing positions
        // Maker's excess collateral must remain positive after removal
        bool inQuoteToken = removedOrder.isBuyOrder;
        revertIfSuperiorTo(_removedQuantity, getUserExcessCollateral(removedOrder.maker, inQuoteToken));

        // reduce quantity in order, possibly to zero
        _reduceOrderByQuantity(_removedOrderId, _removedQuantity);

        _incrementTimeWeightedRates();
        _decreaseTotalAssets(_removedQuantity, inQuoteToken);
        _transferTo(msg.sender, _removedQuantity, removedOrder.isBuyOrder);
        emit Withdraw(removedOrder.maker, _removedQuantity, removedOrder.price, removedOrder.isBuyOrder);
    }

    /// @inheritdoc IBook
    function borrow(
        uint256 _borrowedOrderId,
        uint256 _borrowedQuantity
    )
        external
        orderHasAssets(_borrowedOrderId)
        isPositive(_borrowedQuantity)
    {
        Order memory borrowedOrder = orders[_borrowedOrderId];

        // cannot borrow more than available assets, net of minimum deposit
        require(outable(_borrowedOrderId, _borrowedQuantity), "Too much assets borrowed");

        // check available assets are not used as collateral by maker and can be borrowed
        bool inQuoteToken = borrowedOrder.isBuyOrder;
        revertIfSuperiorTo(_borrowedQuantity, getUserExcessCollateral(borrowedOrder.maker, inQuoteToken));

        // check borrowed amount is collateralized enough by borrower's own orders
        uint256 convertedBorrowableQuantity = convert(_borrowedQuantity, borrowedOrder.price, inQuoteToken);
        revertIfSuperiorTo(convertedBorrowableQuantity, getUserExcessCollateral(msg.sender, !inQuoteToken));   

        // check if borrower already borrows from order, if not, add orderId to borrowFromIds array, revert if max position reached
        _addOrderIdInBorrowFromIdsInUsers(msg.sender, _borrowedOrderId);

        // increment time-weighted interest rates and update total borrowing before adding position
        _incrementTimeWeightedRates();

        // create new or update existing borrowing position in positions
        // output the id of the new or updated borrowing position
        uint256 positionId = _addPositionToPositions(msg.sender, _borrowedOrderId, _borrowedQuantity);
        _increaseTotalBorrow(positions[positionId].borrowedAssets, inQuoteToken);

        // add new positionId in positionIds array in orders, check first that position doesn't already exist
        // reverts if max number of positions is reached
        _AddPositionIdToPositionIdsInOrders(positionId, _borrowedOrderId);

        _transferTo(msg.sender, _borrowedQuantity, inQuoteToken);
        emit Borrow(msg.sender, _borrowedOrderId, _borrowedQuantity, inQuoteToken);
    }

    /// @inheritdoc IBook
    function repay(
        uint256 _positionId,
        uint256 _repaidQuantity
    )
        external
        positionExists(_positionId)
        isPositive(_repaidQuantity)
        onlyBorrower(_positionId)
    {
        bool inQuoteToken = orders[positions[_positionId].orderId].isBuyOrder;

        // increment time-weighted rates with IR based on UR before repay
        _incrementTimeWeightedRates();
        // add interest rate to borrowed quantity and update TWIR_t to TWIR_T
        uint256 interestLoad = _interestLoad(_positionId);
        _increaseBorrowBy(_positionId, interestLoad);
        positions[_positionId].timeWeightedRate = getTimeWeightedRate(inQuoteToken);
        _increaseTotalBorrow(interestLoad, inQuoteToken);

        revertIfSuperiorTo(_repaidQuantity, positions[_positionId].borrowedAssets);

        // decrease borrowedAssets in positions, possibly to zero
        _reduceBorrowBy(_positionId, _repaidQuantity);
        _decreaseTotalBorrow(_repaidQuantity, inQuoteToken);

        _transferFrom(msg.sender, _repaidQuantity, inQuoteToken);
        emit Repay(msg.sender, _positionId, _repaidQuantity, inQuoteToken);
    }

    /// @inheritdoc IBook
    function take(
        uint256 _takenOrderId,
        uint256 _takenQuantity
    )
        external
        orderHasAssets(_takenOrderId)
    {
        Order memory takenOrder = orders[_takenOrderId];
        bool isBuyOrder = takenOrder.isBuyOrder;

        // taking is allowed for non-borrowed assets, possibly net of minimum deposit if taking is partial
        require(outable(_takenOrderId, _takenQuantity), "Too much assets taken");

        // increment time-weighted rates with IR based on past UR before take changes UR forward
        _incrementTimeWeightedRates();
        
        // liquidate all borrowing positions, output seized borrowers' collateral
        // Ex: Bob deposits 2 ETH in a sell order to borrow 4000 from Alice's buy order (p = 2000)
        // Alice's buy order is taken, Bob's collateral is seized for 4000/p = 2 ETH      
        uint256 seizedBorrowerCollateral = _liquidateAssets(_takenOrderId);

        // Liquidation means les assets deposited (seized collateral) and less assets borrowed (written off debt)
        uint256 writtenOffDebt;
        if (seizedBorrowerCollateral > 0) {
            // total deposits from borrowers' side are reduced by 2 ETH
            _decreaseTotalAssets(seizedBorrowerCollateral, !isBuyOrder);
            // if 2 ETH are seized, 2*p = 4000 USDC of debt are written off
            writtenOffDebt = convert(seizedBorrowerCollateral, takenOrder.price, !isBuyOrder);
            // total borrow is reduced by 4000 USDC
            _decreaseTotalBorrow(writtenOffDebt, isBuyOrder);
        } else {
            writtenOffDebt = 0;
        }

        // assets taken could collateralize maker's own borrowing positions
        // assets received (given by taker or seized from borrowers) are used to repay maker's own loans first
        // Alice deposits 2100 USDC in a buy order (p = 1900) to borrow 1 ETH from Clair's sell order (p' = 2200) 
        // Alice's buy order is taken for X \in (0, 2100) USDC in exchange of X/p ETH
        // Her borrowing in ETH is reduced by min(X/p, 1) 
        // Taking a collateral order writes off the debt first (exit strategy)

        uint256 budgetToRepayLoans = convert(_takenQuantity + writtenOffDebt, takenOrder.price, isBuyOrder);
        uint256 reducedBorrow = _reduceUserBorrow(takenOrder.maker, budgetToRepayLoans, isBuyOrder);
        _decreaseTotalBorrow(reducedBorrow, !isBuyOrder);

        // Alice buy order is reduced by amount taken + 2 * p USDC
        _reduceOrderByQuantity(_takenOrderId, _takenQuantity + writtenOffDebt);
        // total deposits from maker's side are reduced by taken quantity + 2*p USDC
        _decreaseTotalAssets(_takenQuantity + writtenOffDebt, isBuyOrder);

        // quantity given by taker in exchange of _takenQuantity (can be zero)
        uint256 exchangedQuantity = convert(_takenQuantity, takenOrder.price, isBuyOrder);

        if (_takenQuantity > 0) {
            _transferTo(msg.sender, _takenQuantity, isBuyOrder);
            _transferFrom(msg.sender, exchangedQuantity, !isBuyOrder);
        }

        if (exchangedQuantity + seizedBorrowerCollateral - reducedBorrow > 0) {
            _transferTo(takenOrder.maker, exchangedQuantity + seizedBorrowerCollateral - reducedBorrow, !isBuyOrder);
        }  
        emit Take(msg.sender, takenOrder.maker, _takenQuantity, takenOrder.price, isBuyOrder);
    }

    ///////******* Internal functions *******///////
    
    // liquidate **all** borrowing positions after taking an order, even if partial
    // output the quantity liquidated
    // doesn't perform external transfers
    // _fromOrderId: order from which borrowing positions must be cleared

    function _liquidateAssets(uint256 _fromOrderId)
        internal
        returns (uint256 seizedBorrowerCollateral)
    {
        uint256[MAX_POSITIONS] memory positionIds = orders[_fromOrderId].positionIds;
        seizedBorrowerCollateral = 0;

        // iterate on position ids which borrow from the order taken, liquidate position one by one
        for (uint256 i = 0; i < MAX_POSITIONS; i++) {
            uint256 positionId = positionIds[i];
            if(_borrowingInPositionIsPositive(positionId)) {
                (bool success, uint256 seizedCollateral) = _liquidatePosition(positionId);
                require(success, "Some collateral couldn't be seized");
                seizedBorrowerCollateral += seizedCollateral;
            }
        }
    }

    // liquidate one borrowing position: seize collateral and write off debt for the same amount
    // liquidation is full, i.e. borrower's debt is fully written off
    // collateral is seized for the exact amount liquidated
    // as multiple orders may collateralize the liquidated position:
    //  - iterate on collateral orders made by borrower in the opposite currency
    //  - seize collateral orders as they come, stop when borrower's debt is fully written off
    //  - change internal balances
    // doesn't execute final external transfer of assets

    function _liquidatePosition(uint256 _positionId)
        internal
        positionExists(_positionId)
        returns (bool success, uint256 seizedCollateral)
    {
        Position memory position = positions[_positionId]; // position to be liquidated
        Order memory takenOrder = orders[position.orderId]; // order from which assets are taken
        bool inQuoteToken = takenOrder.isBuyOrder;

        // add interest rate to borrowed quantity
        _increaseBorrowBy(_positionId, _interestLoad(_positionId));
        
        // collateral to seize the other side of the book given borrowed quantity
        // ex: Bob deposits 1 ETH in 2 sell orders to borrow 4000 from Alice's buy order (p = 2000)
        // Alice's buy order is taken => seized Bob's collateral is 4000/p = 2 ETH spread over 2 orders
        seizedCollateral = convert(position.borrowedAssets, takenOrder.price, inQuoteToken);
        uint256 remainingCollateralToSeize = seizedCollateral;

        // order id list of collateral orders to seize:
        uint256[MAX_ORDERS] memory depositIds = users[position.borrower].depositIds;
        for (uint256 j = 0; j < MAX_ORDERS; j++) {
            // order id from which assets are seized, ex: id of Bob's first sell order
            uint256 orderId = depositIds[j];
            if (_orderHasAssets(orderId) &&
                orders[orderId].isBuyOrder != inQuoteToken)
            {
                uint256 orderQuantity = orders[orderId].quantity;

                // if order quantity > remaining collateral to seize and doesn't leave dusts
                if (orderQuantity > remainingCollateralToSeize &&
                    outable(orderId, remainingCollateralToSeize)
                ) {
                    // enough collateral assets are seized before borrower's order is fully seized
                    _reduceOrderByQuantity(orderId, remainingCollateralToSeize);
                    uint256 reducedBorrow = convert(remainingCollateralToSeize, takenOrder.price, !inQuoteToken);
                    positions[_positionId].borrowedAssets -= reducedBorrow;
                    remainingCollateralToSeize = 0;
                    break;
                } else {
                    // borrower's order is fully seized, reduce order quantity to zero
                    _reduceOrderByQuantity(orderId, orderQuantity);
                    // write off debt for the same amount as collateral seized
                    positions[_positionId].borrowedAssets = 0;
                    remainingCollateralToSeize -= orderQuantity;
                }
            }
        }
        success = (remainingCollateralToSeize == 0);
    }

    // reduce maker's borrowing positions possibly as high as BudgetToRepayLoans
    // Ex: Bob deposits a sell order as collateral to borrow Alice's buy order
    // if Bob's sell order is taken first, his borrowing position from Alice is reduced, possibly to zero
    // as multiple positions may be collateralized by the taken order:
    //  - iterate on borrowing positions
    //  - close positions as they come, stops when no more positions or budget is exhausted
    //  - change internal balances
    
    function _reduceUserBorrow(
        address _borrower,
        uint256 _budgetToRepayLoans,
        bool _isBuyOrder // type of the taken order
    )
        internal
        returns (uint256 totalReducedBorrow_)
    {
        uint256[MAX_BORROWINGS] memory borrowFromIds = users[_borrower].borrowFromIds;
        uint256 budgetBefore = _budgetToRepayLoans;
        totalReducedBorrow_ = 0;

        // iterate on position ids which borrow from the order taken, liquidate position one by one
        for (uint256 i = 0; i < MAX_BORROWINGS; i++) {
            uint256 borrowedOrderId = borrowFromIds[i];
            uint256 positionId = _getPositionId(borrowedOrderId, _borrower);
            if (positions[positionId].borrowedAssets > 0 &&
                orders[borrowedOrderId].isBuyOrder != _isBuyOrder)
            {
                (uint256 budgetAfter, uint256 reducedBorrow) =_closePosition(positionId, budgetBefore);
                totalReducedBorrow_ += reducedBorrow;
                if (budgetAfter == 0) break;
                else budgetBefore = budgetAfter;
            }
        }
    }

    // reduce user's borrow from one order, partially or fully
    // _budget: remaining assets from taken position available to partially or fully repay the position

    function _closePosition(
        uint256 _positionId,
        uint256 _budget 
    )
        internal 
        returns (
            uint256 remainingBudget_, // after closing this position
            uint256 reducedBorrow_ // quantity of assets reduced from this position
        )
    {
        // add interest rate to borrowed quantity and update TWIR_t to TWIR_T
        uint256 interestLoad = _interestLoad(_positionId);
        bool inQuoteToken = orders[positions[_positionId].orderId].isBuyOrder;
        _increaseBorrowBy(_positionId, interestLoad);
        positions[_positionId].timeWeightedRate = getTimeWeightedRate(inQuoteToken);
        _increaseTotalBorrow(interestLoad, inQuoteToken);
        
        uint256 borrowedAssets = positions[_positionId].borrowedAssets;
        if (borrowedAssets >= _budget) {
            // position has enough borrowed assets to close: position partially closed
            reducedBorrow_ = _budget;
            remainingBudget_ = 0;
        } else {
            // position fully closed
            reducedBorrow_ = borrowedAssets;
            remainingBudget_ = _budget - borrowedAssets;
        }
        _reduceBorrowBy(_positionId, reducedBorrow_);
    }

    // tranfer ERC20 from contract to user/taker/borrower
    function _transferTo(
        address _to,
        uint256 _quantity,
        bool _isBuyOrder
    )
        internal
        isPositive(_quantity)
    {
        if (_isBuyOrder) quoteToken.safeTransfer(_to, _quantity);
        else baseToken.safeTransfer(_to, _quantity);
    }
    
    // transfer ERC20 from user/taker/repayBorrower to contract
    function _transferFrom(
        address _from,
        uint256 _quantity,
        bool _isBuyOrder
    ) internal isPositive(_quantity)
    {
        if (_isBuyOrder) quoteToken.safeTransferFrom(_from, address(this), _quantity);
        else baseToken.safeTransferFrom(_from, address(this), _quantity);
    }

    // add order to Order
    // returns id of the new order

    function _addOrderToOrders(
        address _maker,
        bool _isBuyOrder,
        uint256 _quantity,
        uint256 _price
    )
        internal 
        returns (uint256 orderId)
    {
        uint256[MAX_POSITIONS] memory positionIds;
        Order memory newOrder = Order({
            maker: _maker,
            isBuyOrder: _isBuyOrder,
            quantity: _quantity,
            price: _price,
            positionIds: positionIds
        });
        orders[lastOrderId] = newOrder;
        orderId = lastOrderId;
        lastOrderId++;
    }

    // if order id is not in depositIds array, include it, otherwise do nothing
    // reverts if max orders reached

    function _addOrderIdInDepositIdsInUsers(
        uint256 _orderId,
        address _maker
    )
        internal
        orderHasAssets(_orderId)
    {
        if (_getDepositIdsRowInUsers(_maker, _orderId) != ABSENT) return;
        bool fillRow = false;
        for (uint256 i = 0; i < MAX_ORDERS; i++) {
            if (!_orderHasAssets(users[_maker].depositIds[i])) {
                users[_maker].depositIds[i] = _orderId;
                fillRow = true;
                break;
            }
        }
        if (!fillRow) revert("Max number of orders reached for user");
    }

    function _removeOrderIdFromBorrowFromIdsInUsers(
        address _user,
        uint256 _orderId
    )
        internal
        orderHasAssets(_orderId)
    {
        uint256 row = _getBorrowFromIdsRowInUsers(_user, _orderId);
        if (row != ABSENT) users[_user].borrowFromIds[row] = 0;
    }

    // if borrower doen't already borrow from order, add order id in borrowFromIds array in mapping users
    // reverts if max borrowing reached

    function _addOrderIdInBorrowFromIdsInUsers(
        address _borrower,
        uint256 _orderId
    )
        internal
        orderHasAssets(_orderId)
    {
        if (_getBorrowFromIdsRowInUsers(_borrower, _orderId) != ABSENT) return;
        bool fillRow = false;
        for (uint256 i = 0; i < MAX_BORROWINGS; i++) {
            uint256 orderId = users[_borrower].borrowFromIds[i];
            if (orderId == 0 || _userHasZeroBorrowingFromOrder(orderId, _borrower))
            {
                users[_borrower].borrowFromIds[i] = _orderId;
                fillRow = true;
                break;
            }
        }
        if (!fillRow) revert("Max number of positions reached for borrower");
    }

    function _removeOrderIdFromDepositIdsInUsers(
        address _user,
        uint256 _orderId
    )
        internal
        orderHasAssets(_orderId)
    {
        if (orders[_orderId].quantity == 0) {
            uint256 row = _getDepositIdsRowInUsers(_user, _orderId);
            if (row != ABSENT) users[_user].depositIds[row] = 0;
        }
    }

    // if position doesn't exist, add new position in positions mapping
    // if exists, increase borrow by quantity + interest load, restarts R_t to R_T
    // returns existing or new position id in positions mapping
    // _orderId: from which assets are borrowed

    function _addPositionToPositions(
        address _borrower,
        uint256 _orderId,
        uint256 _borrowedQuantity
    )
        internal
        orderHasAssets(_orderId)
        isPositive(_borrowedQuantity)
        returns (uint256 positionId_)
    {
        positionId_ = _getPositionId(_orderId, _borrower);
        bool inQuoteToken = orders[_orderId].isBuyOrder;
        uint256 timeWeightedRate = getTimeWeightedRate(inQuoteToken);
        if (positionId_ != 0) {
            // add interest rate to borrowed quantity and update TWIR_t to TWIR_T
            uint256 interestLoad = _interestLoad(positionId_);
            _increaseBorrowBy(positionId_, _borrowedQuantity + interestLoad);
            positions[positionId_].timeWeightedRate = timeWeightedRate;
        } else {
            Position memory newPosition = Position({
                borrower: _borrower,
                orderId: _orderId,
                borrowedAssets: _borrowedQuantity,
                timeWeightedRate: timeWeightedRate
            });
            positions[lastPositionId] = newPosition;
            positionId_ = lastPositionId;
            lastPositionId++;
        }
    }

    // increase borrowedAssets in position, special attention to excessCollateral

    function _increaseBorrowBy(
        uint256 _positionId,
        uint256 _quantity
    )
        internal
        positionExists(_positionId)
    {
        positions[_positionId].borrowedAssets += _quantity;
    }

    // decrease borrowedAssets in position, borrowing = 0 is equivalent to deleted position
    // quantity =< borrowing is checked before the call

    function _reduceBorrowBy(
        uint256 _positionId,
        uint256 _quantity
    )
        internal
        positionExists(_positionId)
    {
        positions[_positionId].borrowedAssets -= _quantity;
    }

    // if borrower doesn't already borrow from order, add new position id in positionIds array in orders
    // reverts if max number of positions is reached

    function _AddPositionIdToPositionIdsInOrders(
        uint256 _positionId,
        uint256 _orderId
    )
        internal
        orderHasAssets(_orderId)
        positionExists(_positionId)
    {
        if (_getPositionId(_orderId, positions[_positionId].borrower) != 0) return; // could save gas by avoiding two loops FOR
        bool fillRow = false;
        uint256[MAX_POSITIONS] memory positionIds = orders[_orderId].positionIds;
        for (uint256 i = 0; i < MAX_POSITIONS; i++) {
            if (positionIds[i] == 0 || ! _borrowingInPositionIsPositive(positionIds[i])) {
                orders[_orderId].positionIds[i] = _positionId;
                fillRow = true;
                break;
            }
        }
        require(fillRow, "Max number of positions reached for order");
    }

    // increase quantity offered in order, possibly from zero
    function _increaseOrderBy(
        uint256 _orderId,
        uint256 _quantity
    )
        internal
        isPositive(_quantity)
    {
        orders[_orderId].quantity += _quantity;
    }

    // reduce quantity offered in order, emptied = deleted
    // reduced quantity =< order quantity has been check before the call

    function _reduceOrderByQuantity(
        uint256 _orderId,
        uint256 _quantity
    )
        internal
        orderHasAssets(_orderId)
    {
        if (orders[_orderId].quantity >= _quantity) orders[_orderId].quantity -= _quantity;
        else orders[_orderId].quantity = 0;
    }

    // increase total assets in quote (buy order side) or base (sell order side) token
    function _increaseTotalAssets(uint256 _quantity, bool _inQuote)
        internal
    {
        if (_inQuote) totalQuoteAssets += _quantity;
        else totalBaseAssets += _quantity;
    }

    function _decreaseTotalAssets(uint256 _quantity, bool _inQuote)
        internal
    {
        if (_inQuote) totalQuoteAssets -= _quantity;
        else totalBaseAssets -= _quantity;
    }

    // increase total borrow in quote (buy order side) or base (sell order side) token
    function _increaseTotalBorrow(uint256 _quantity, bool _inQuote)
        internal
    {
        if (_inQuote) totalQuoteBorrow += _quantity;
        else totalBaseBorrow += _quantity;
    }

    // decrease total borrow in quote or base tokens
    function _decreaseTotalBorrow(uint256 _quantity, bool _inQuote)
        internal
    {
        if (_inQuote) totalQuoteBorrow -= _quantity;
        else totalBaseBorrow -= _quantity;
    }

    // add IR_{t-1} (n_t - n_{t-1})/N to time-weighted interest rate TWIR_{t-2} in the two markets:
    // TWIR_{t-2} = IR_0 n_1/N + IR_1 (n_2 - n_1)/N + ... + IR_{t-1} (n_{t-2} - n_{t-1})/N
    // with N number of seconds in a year, elapsed in seconds (intergers), quote- and baseTimeWeightedRate in WAD
    
    function _incrementTimeWeightedRates()
        internal
    {
        uint256 elapsed = block.timestamp - lastTimeStamp;
        quoteTimeWeightedRate += elapsed * getInstantRate(true) / YEAR;
        baseTimeWeightedRate += elapsed * getInstantRate(false) / YEAR;
        lastTimeStamp = block.timestamp;
    }

    // compute interest rate since start of borrowing position between t and T
    // exp(TWIR_T - TWIR_t) - 1 using a Taylor approximation

    function _accruedInterestRate(
        uint256 _positionId,
        bool _inQuoteToken
    )
        internal
        returns (uint256 accruedInterestRate_)
    {
        accruedInterestRate_ = (
            getTimeWeightedRate(_inQuoteToken)
            - positions[_positionId].timeWeightedRate
        ).wTaylorCompounded();
    }

    function _interestLoad(uint256 _positionId)
        internal
        returns (uint256 interestLoad_)
    {
        bool inQuoteToken = orders[positions[_positionId].orderId].isBuyOrder;
        uint256 interestRate = _accruedInterestRate(_positionId, inQuoteToken);
        interestLoad_ = interestRate.wMulUp(positions[_positionId].borrowedAssets);
    }

    //////////********* View functions *********/////////

    // get UR = total borrow / total assets in the buy order or sell order market
    function getUtilizationRate(bool _isBuyOrder)
        public view
        returns (uint256 utilizationRate_)
    {
        if (_isBuyOrder) {
            if (totalQuoteAssets == 0) utilizationRate_ = 5 * WAD / 10;
            else if (totalQuoteAssets <= totalQuoteBorrow) utilizationRate_ = 1 * WAD;
            else {
                utilizationRate_ = totalQuoteBorrow.mulDivDown(WAD, totalQuoteAssets);
            }
        } else {
            if (totalBaseAssets == 0) utilizationRate_ = 5 * WAD / 10;
            else if (totalBaseAssets <= totalBaseBorrow ) utilizationRate_ = 1 * WAD;
            else utilizationRate_ = totalBaseBorrow.mulDivDown(WAD, totalBaseAssets);
        }
    }
    
    // get instant rate r_t (in seconds) for quote (buy order) and base tokens (sell orders)
    // must be multiplied by 60 * 60 * 24 * 365 / WAD to get annualized rate

    function getInstantRate(bool _isBuyOrder)
        public view
        returns (uint256)
    {
        return ALPHA 
            + BETA.wMulDown(getUtilizationRate(_isBuyOrder))
            + GAMMA.wMulDown(getUtilizationRate(!_isBuyOrder));
    }
    
    // get TWIR_T in buy or sell order market, used in computing interest rate for borrowing positions
    function getTimeWeightedRate(bool isBuyOrder)
        public view
        returns (uint256)
    {
        return isBuyOrder ? quoteTimeWeightedRate : baseTimeWeightedRate;
    }
    
    function _revertIfOrderHasZeroAssets(uint256 _orderId)
        internal view
    {
        require(_orderHasAssets(_orderId), "Order has zero assets");
    }

    function _orderHasAssets(uint256 _orderId)
        internal view
        returns (bool)
    {
        return (orders[_orderId].quantity > 0);
    }

    function _onlyMaker(uint256 orderId)
        internal view
    {
        require(getMaker(orderId) == msg.sender, "Only maker can remove order");
    }

    function _onlyBorrower(uint256 _positionId)
        internal view
    {
        require(getBorrower(_positionId) == msg.sender, "Only borrower can repay position");
    }

    function _revertIfPositionDoesntExist(uint256 _positionId)
        internal view
    {
        require(_borrowingInPositionIsPositive(_positionId), "Borrowing position does not exist");
    }

    function _borrowingInPositionIsPositive(uint256 _positionId)
        internal view
        returns (bool)
    {
        return (positions[_positionId].borrowedAssets > 0);
    }

    // get position id from positionIds array in orders and check that borrow is zero
    function _userHasZeroBorrowingFromOrder (
        uint256 _orderId,
        address _user
    )
        internal view
        returns (bool)
    {
        uint256 positionId = _getPositionId(_orderId, _user);
        return !_borrowingInPositionIsPositive(positionId);
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
    function getUserTotalDeposit(
        address _user,
        bool _inQuoteToken
    )
        public view
        returns (uint256 totalDeposit)
    {
        uint256[MAX_ORDERS] memory depositIds = users[_user].depositIds;
        totalDeposit = 0;
        for (uint256 i = 0; i < MAX_ORDERS; i++) {
            if (orders[depositIds[i]].isBuyOrder == _inQuoteToken)
                totalDeposit += orders[depositIds[i]].quantity;
        }
    }

    // total assets borrowed by other users from _user in base or quote token
    function getUserTotalBorrowedAssets(
        address _user,
        bool _inQuoteToken
    )
        public view
        returns (uint256 totalBorrowedAssets)
    {
        uint256[MAX_ORDERS] memory orderIds = users[_user].depositIds;
        totalBorrowedAssets = 0;
        for (uint256 i = 0; i < MAX_ORDERS; i++) {
            totalBorrowedAssets += _getOrderBorrowedAssets(orderIds[i], _inQuoteToken);
        }
    }

    // total assets borrowed from order in base or quote tokens
    function _getOrderBorrowedAssets(
        uint256 _orderId,
        bool _inQuoteToken
        )
        public view
        returns (uint256 borrowedAssets)
    {
        if (!_orderHasAssets(_orderId) || orders[_orderId].isBuyOrder != _inQuoteToken) return borrowedAssets = 0;
        uint256[MAX_POSITIONS] memory positionIds = orders[_orderId].positionIds;
        for (uint256 i = 0; i < MAX_POSITIONS; i++) {
            borrowedAssets += positions[positionIds[i]].borrowedAssets;
        }
    }

    // borrower's total collateral needed to secure his debt in the quote or base token
    // if needed collateral is in quote token, borrowed order is a sell order
    // Ex: Alice deposits 3 ETH to sell at 2100; Bob borrows 2 ETH and needs 2*2100 = 4200 USDC as collateral

    function getBorrowerNeededCollateral(
        address _borrower,
        bool _inQuoteToken
    )
        public view
        returns (uint256 totalNeededCollateral)
    {
        totalNeededCollateral = 0;
        uint256[MAX_BORROWINGS] memory borrowedIds = users[_borrower].borrowFromIds;
        for (uint256 i = 0; i < MAX_BORROWINGS; i++) {
            Order memory order = orders[borrowedIds[i]]; // order id which assets are borrowed
            if (order.isBuyOrder != _inQuoteToken) {
                uint256 positionId = _getPositionId(borrowedIds[i], _borrower);
                if (positionId != 0) {
                    uint256 collateral = convert(positions[positionId].borrowedAssets, order.price, order.isBuyOrder);
                    totalNeededCollateral += collateral;
                }
            }
        }
    }

    // get user's excess collateral in the quote or base token
    // excess collateral = total deposits - collateral assets - borrowed assets

    function getUserExcessCollateral(
        address _user,
        bool _inQuoteToken
    )
        public view
        returns (uint256 excessCollateral) {
        excessCollateral =
            getUserTotalDeposit(_user, _inQuoteToken) -
            getUserTotalBorrowedAssets(_user, _inQuoteToken) -
            getBorrowerNeededCollateral(_user, _inQuoteToken);
    }

    // get quantity of assets lent by order
    function getTotalAssetsLentByOrder(uint256 _orderId)
        public view
        returns (uint256 totalLentAssets)
    {
        uint256[MAX_POSITIONS] memory positionIds = orders[_orderId].positionIds;
        totalLentAssets = 0;
        for (uint256 i = 0; i < MAX_POSITIONS; i++) {
            totalLentAssets += positions[positionIds[i]].borrowedAssets;
        }
    }

    // get quantity of assets available in order: order quantity - assets lent - minimum deposit
    // available assets are non-borrowed assets if what is left is higher than minimal deposit
    // _outQuantity positive is checked before the call, if necessary
    // return false if desired quantity is not possible

    function outable(
        uint256 _orderId,
        uint256 _outQuantity // quantity to be removed, borrowed, liquidated or taken
    )
        public view
        orderHasAssets(_orderId)
        returns (bool)
    {
        uint256 lentAssets = getTotalAssetsLentByOrder(_orderId);
        uint256 minDep = minDeposit(orders[_orderId].isBuyOrder);
        uint256 availableAssets = orders[_orderId].quantity > lentAssets ? 
            orders[_orderId].quantity - lentAssets : 0;     
        // if removal/borrowing/taking is not full (less than available assets), min deposit applies
        if (_outQuantity > availableAssets ||
            _outQuantity < availableAssets && _outQuantity + minDep > availableAssets)
        return false;
        else return true;
    }

    // get quantity of assets available in order: order quantity - assets lent
    function nonBorrowedAssetsInOrder(uint256 _orderId)
        public view
        orderHasAssets(_orderId)
        returns (uint256 nonBorrowedAssets)
    {
        nonBorrowedAssets = orders[_orderId].quantity > getTotalAssetsLentByOrder(_orderId) ?
        orders[_orderId].quantity - getTotalAssetsLentByOrder(_orderId) : 0;
    }

    // find if user placed order id
    // if so, outputs its row in depositIds array

    function _getDepositIdsRowInUsers(
        address _user,
        uint256 _orderId // in the depositIds array of users
    )
        internal view
        returns (uint256 depositIdsRow)
    {
        depositIdsRow = ABSENT;
        uint256[MAX_ORDERS] memory depositIds = users[_user].depositIds;
        for (uint256 i = 0; i < MAX_ORDERS; i++) {
            if (depositIds[i] == _orderId) {
                depositIdsRow = i;
                break;
            }
        }
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
        uint256[MAX_BORROWINGS] memory borrowFromIds = users[_borrower].borrowFromIds;
        for (uint256 i = 0; i < MAX_BORROWINGS; i++) {
            if (borrowFromIds[i] == _orderId) {
                borrowFromIdsRow = i;
                break;
            }
        }
    }

    // check if an order already exists with the same user and limit price
    // if so, returns order id
    
    function _getOrderIdInDepositIdsInUsers(
        address _user,
        uint256 _price,
        bool _isBuyOrder
    )
        internal view
        isPositive(_price)
        returns (uint256 orderId)
    {
        orderId = 0;
        uint256[MAX_ORDERS] memory depositIds = users[_user].depositIds;
        for (uint256 i = 0; i < MAX_ORDERS; i++) {
            if (
                orders[depositIds[i]].price == _price &&
                orders[depositIds[i]].isBuyOrder == _isBuyOrder
            ) {
                orderId = depositIds[i];
                break;
            }
        }
    }

    // get positionId from positionIds array in orders, returns 0 if not found

    function _getPositionId(
        uint256 _orderId,
        address _borrower
    )
        internal view
        returns (uint256 positionId_)
    {
        positionId_ = 0;
        uint256[MAX_POSITIONS] memory positionIds = orders[_orderId].positionIds;
        for (uint256 i = 0; i < MAX_POSITIONS; i++) {
            if (positionIds[i] == 0) break; // a bit risky
            if (positions[positionIds[i]].borrower == _borrower &&
                positions[positionIds[i]].borrowedAssets > 0) {
                positionId_ = orders[_orderId].positionIds[i];
                break;
            }
        }
    }

    //////////********* Functions used in tests */

    // Add manual getter for positionIds in Order, used in setup.sol for tests
    function getOrderPositionIds(uint256 _orderId)
        public view
        returns (uint256[MAX_POSITIONS] memory)
    {
        return orders[_orderId].positionIds;
    }
    
    // Add manual getter for depositIds for User, used in setup.sol for tests
    function getUserDepositIds(address user)
        public view
        returns (uint256[MAX_ORDERS] memory)
    {
        return users[user].depositIds;
    }

    // Add manual getter for borroFromIds for User, used in setup.sol for tests
    function getUserBorrowFromIds(address user)
        public view
        returns (uint256[MAX_BORROWINGS] memory)
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
            count = orders[depositIds[i]].quantity > 0 ? count + 1 : count;
        }
    }

    //////////********* Pure functions *********/////////
    
    function convert(
        uint256 _quantity,
        uint256 _price,
        bool _inQuoteToken // type of the asset to convert to (quote or base token)
    )
        internal pure
        isPositive(_price)
        returns (uint256 convertedQuantity)
    {
        convertedQuantity = _inQuoteToken ? _quantity.wDivDown(_price) : _quantity.wMulDown(_price);
    }

    function minDeposit(bool _isBuyOrder)
        internal pure
        returns (uint256 minAssets)
    {
        minAssets = _isBuyOrder ? MIN_DEPOSIT_QUOTE : MIN_DEPOSIT_BASE;
    }
    
    function revertIfSuperiorTo(
        uint256 _quantity,
        uint256 _limit
    )
        internal pure
        isPositive(_limit)
    {
        require(_quantity <= _limit, "Quantity exceeds limit");
    }

    function revertIfNonPositive(uint256 _var)
        internal pure
    {
        require(_var > 0, "Must be positive");
    }

}