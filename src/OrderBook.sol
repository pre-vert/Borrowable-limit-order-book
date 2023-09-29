// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

/// @title A borrowable order book for ERC20 tokens
/// @author Pré-vert
/// @notice Allows users to place limit orders on the book, take orders, and borrow assets
/// @dev A money market for the pair base/quote is handled by a single contract
/// which manages both order book operations lending/borrowing operations

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IOrderBook} from "./interfaces/IOrderBook.sol";
import {console} from "forge-std/Test.sol";
import "./lib/MathLib.sol";

contract OrderBook is IOrderBook {
    using Math for uint256;
    using MathLib for uint256;
    IERC20 private quoteToken;
    IERC20 private baseToken;

    /// @notice provide core public functions (place, take, remove, borrow, repay),
    /// internal functions (find new orders, reposition, liquidate) and view functions
    /// @dev mapping orders stores orders in a struct Order
    /// mapping users stores users (makers and borrowers) in a struct User
    /// mapping positions links orders and borrowers ina P2P fashion and stores borrowing positions in a struct Position
    /// buyOrderList and sellOrderList are unordered lists of buy and sell orders id to scan for new orders

    struct Order {
    address maker; // address of the maker
    bool isBuyOrder; // true for buy orders, false for sell orders
    uint256 quantity; // assets deposited (quoteToken for buy orders, baseToken for sell orders)
    uint256 price; // price of the order
    uint256[] positionIds; // stores positions id in mapping positions who borrow from order
    }

    struct User {
        uint256[] depositIds; // stores orders id in mapping orders to which borrower deposits
        uint256[] borrowFromIds; // stores orders id in mapping orders from which borrower borrows
    }

    struct Position {
        address borrower; // address of the borrower
        uint256 orderId; // stores orders id in mapping orders, from which assets are borrowed
        uint256 borrowedAssets; // quantity of assets borrowed (quoteToken for buy orders, baseToken for sell orders)
    }

    mapping(uint256 orderIndex => Order) private orders;
    mapping(address user => User) private users;
    mapping(uint256 positionIndex => Position) private positions;

    // when an order is removed, we need to iterate through orders to reposition the debt
    // gas costs is bounded by:
    // - looping only on relevant orders = same side, with non-borowed and non-collateral assets
    // - setting a maxListSize for the number of orders to be scanned

    uint256[] buyOrderList; // unordered list of buy orders id 
    uint256[] sellOrderList; // unordered list of sell orders id 
    uint256 maxListSize = 10; // maximum number of orders to be scanned when repositioning debt
    
    uint256 lastOrderId = 0;
    uint256 lastPositionId = 0;

    constructor(address _quoteToken, address _baseToken) {
        quoteToken = IERC20(_quoteToken);
        baseToken = IERC20(_baseToken);
    }

    modifier orderExists(uint256 _orderId) {
        Order memory order = orders[_orderId];
        require(
            order.quantity != 0 && order.quantity != 0,
            "Order does not exist"
        );
        _;
    }

    modifier userExists(address _user) {
        Order memory user = users[_user];
        require(
            user.depositIds.length > 0,
            "User does not exist"
        );
        _;
    }

    modifier positionExists(uint256 _positionId) {
        Order memory position = positionss[_positionInde];
        require(
            position.borrower != address(0),
            "Borrowing position does not exist"
        );
        _;
    }

    modifier isPositive(uint256 _var) {
        require(_var > 0, "Must be positive");
        _;
    }

    modifier onlyMaker(address maker) {
        require(maker == msg.sender, "removeOrder: Only the maker can remove the order");
        _;
    }

    // only assets which do not serve as collateral are borrowable
    // check if the maker is not a borrower

    modifier isBorrowable(uint256 _orderId) {
        require(
            !isMakerBorrower(getMaker(_orderId)),
            "Assets used as collateral: not available for borrowing"
        );
        _;
    }

    /// @notice lets users place orders in the order book
    /// @dev Update ERC20 balances. The order is stored in the mapping orders
    /// @param _quantity The quantity of assets deposited (quoteToken for buy orders, baseToken for sell orders)
    /// @param _price price of the buy or sell order
    /// @param _isBuyOrder true for buy orders, false for sell orders

    function placeOrder(
        uint256 _quantity,
        uint256 _price,
        bool _isBuyOrder
    ) external isPositive(_quantity) isPositive(_price) {

        _transferTokenFrom(msg.sender, _quantity, _isBuyOrder);
        
        if (_isBuyOrder) {
            buyOrderList.push(lastOrderId);
        } else {
            sellOrderList.push(lastOrderId);
        }

        // Update orders mapping
        uint256[] memory borrowingIds; // Empty array
        Order memory newOrder = Order({
            maker: msg.sender,
            isBuyOrder: _isBuyOrder,
            quantity: _quantity,
            price: _price,
            positionIds: borrowingIds
        });
        orders[lastOrderId] = newOrder;

        // Update users mapping
        User memory user = User({
            depositIds: new uint256[](0), // Empty array
            borrowFromIds: new uint256[](0) // Empty array
        });
        user.depositIds.push(lastOrderId);
        users[msg.sender] = user;

        // Update list of borrowable orders
        if (_isBuyOrder) {
            buyOrderList.push(lastOrderId);
        } else {
            sellOrderList.push(lastOrderId);
        }

        lastOrderId++;
        emit PlaceOrder(msg.sender, _quantity, _price, _isBuyOrder);
    }

    /// @notice lets user partially or fully remove her order from the book
    /// The same order can have multiple borrowers, which position must be displaced
    /// Full removal is subject to succesful reallocation of all borrowed assets
    /// Partial removal is subject to relocation of enough borrowing positions
    /// If removal is partial, the order is updated with the remaining quantity
    /// @param _removedOrderId id of the order to be removed
    /// @param _quantityToBeRemoved desired quantity of assets removed

    function removeOrder(
        uint256 _removedOrderId,
        uint256 _quantityToBeRemoved
    )
        external
        orderExists(_removedOrderId)
        isPositive(_quantityToBeRemoved)
        onlyMaker(orders[_removedOrderId].maker)
    {
        Order memory removedOrder = orders[_removedOrderId];
        address remover = removedOrder.maker;

        require(removedOrder.quantity >= _quantityToBeRemoved,
            "removeOrder: Removed quantity exceeds deposit"
        );

        // Remaining total deposits must be enough to secure existing borrowing positions
        require(_quantityToBeRemoved <= getUserEquity(remover, removedOrder.isBuyOrder),
            "removeOrder: Close your borrowing positions before removing your orders"
        );

        // remove borrowing positions eqyivalent to the removed quantity
        // output the quantity actually repositioned

        bool forceLiquidation = false;
        uint256 repositionedQuantity = _displaceAssets(_removedOrderId, _quantityToBeRemoved, forceLiquidation);

        // removal is executed for the quantity actually relocated
        uint256 transferredQuantity = repositionedQuantity.min(_quantityToBeRemoved);
        if (transferredQuantity > 0) {
            _transferTokenTo(msg.sender, transferredQuantity, removedOrder.isBuyOrder);
        }
        // if taking is full:
        // - remove order in orders
        // - remove orderId in depositIds array in users
        // otherwise adjust internal balances
        if (transferredQuantity == removedOrder.quantity) {
            delete orders[_removedOrderId];
            _removeOrderFromDepositIds(remover, _removedOrderId);
        } else {
            orders[_removedOrderId].quantity -= transferredQuantity;
        }
        // regardless removal is partial or full, withdraw order from the list of borrowable orders
        _removeOrderFromBorrowables(_removedOrderId);

        emit RemoveOrder(
            remover,
            repositionedQuantity,
            removedOrder.price,
            removedOrder.isBuyOrder
        );
    }

    /// @notice Let users take limit orders on the book, regardless their assets are borrowed or not
    /// Assets can be partially taken
    /// taking triggers liquidation of borrowing positions which couldn't be relocated
    /// some borrowing positions can be liquidated while others are repositioned
    /// regardless they are relocated or liquidated, they are in full
    /// @param _takenOrderId id of the order to be taken
    /// @param _takenQuantity quantity of assets taken from the order

    function takeOrder(
        uint256 _takenOrderId,
        uint256 _takenQuantity
    ) external orderExists(_takenOrderId) isPositive(_takenQuantity) {

        Order memory takenOrder = orders[_takenOrderId];

        require(
            _takenQuantity <= takenOrder.quantity,
            "takeOrder: Taken quantity exceeds deposit"
        );

        // remove or liquidate all borrowing positions
        // output the quantity actually displaced, which must be >= the taken quantity

        bool forceLiquidation = true;
        uint256 displacedQuantity = _displaceAssets(_takenOrderId, _takenQuantity, forceLiquidation);
        require(
            displacedQuantity >= _takenQuantity,
            "takeOrder: insufficient displaced quantity"
        );

        // quantity exchanged against _takenQuantity
        uint256 exchangedQuantity;
        if (takenOrder.isBuyOrder) {
            exchangedQuantity = _takenQuantity / takenOrder.price;
        } else {
            exchangedQuantity = _takenQuantity * takenOrder.price;
        }

        _checkAllowanceAndBalance(msg.sender, exchangedQuantity, takenOrder.isBuyOrder);
        _transferTokenFrom(msg.sender, exchangedQuantity, takenOrder.isBuyOrder);
        _transferTokenTo(takenOrder.maker, exchangedQuantity, takenOrder.isBuyOrder);
        _transferTokenTo(msg.sender, _takenQuantity, takenOrder.isBuyOrder);

        // if taking is full:
        // - remove order in orders
        // - remove orderId in depositIds array in users
        // - remove order from the list of borrowable orders
        // otherwise adjust internal balances
        if (_takenQuantity == takenOrder.quantity) {
            delete orders[_takenOrderId];
            _removeOrderFromDepositIds(takenOrder.maker, _takenOrderId);
            _removeOrderFromBorrowables(_removedOrderId);
        } else {
            takenOrder.quantity -= _takenQuantity;
        }

        emit TakeOrder(
            msg.sender,
            takenOrder.maker,
            takenOrder.quantity,
            takenOrder.price,
            takenOrder.isBuyOrder
        );
    }

    /// @notice Lets users borrow assets on the book (creates or increases a borrowing position)
    /// Borrowers need to place orders first on the othe side of the book with enough assets
    /// orders are borrowable if:
    /// - the maker is not a borrower (his assets are not used as collateral)
    /// - the borrower does not demand more assets than available
    /// - the borrower has enough equity to borrow the assets
    /// @param _borrowedOrderId id of the order which assets are borrowed
    /// @param _borrowedQuantity quantity of assets borrowed from the order

    function borrowOrder(
        uint256 _borrowedOrderId,
        uint256 _borrowedQuantity
    )
        external
        orderExists(_borrowedOrderId)
        isPositive(_borrowedQuantity)
        isBorrowable(_borrowedOrderId)
    {
        Order memory borrowedOrder = orders[_borrowedOrderId];

        uint256 availableAssets = borrowedOrder.quantity -
            getTotalAssetsLentByOrder(_borrowedOrderId);
        require(
            availableAssets >= _borrowedQuantity,
            "borrowOrder: Insufficient available assets"
        );

        // userEquity: excess deposits available to collateralize additional debt
        require(
            getUserEquity(msg.sender, borrowedOrder.isBuyOrder) >=
            borrowedOrder.quantity,
            "borrowOrder: Insufficient equity to borrow assets, deposit more collateral"
        );

        _transferTokenTo(msg.sender, _borrowedQuantity, borrowedOrder.isBuyOrder);

        // update users: add orderId in borrowFromIds array
        // check first if borrower already borrows from order
        uint256 row = getBorrowFromIdsRowInUser(msg.sender, _borrowedOrderId);
        if (row == 2**256 - 1) {
            users[msg.sender].borrowFromIds.push(_borrowedOrderId);
        }

        // update positions: add borrowing position
        // check first if a borrowing position alreday exists
        uint256 positionId = getPositionIdInPositions(msg.sender, _borrowedOrderId);
        if (positionId != 2**256 - 1) {
            positions[positionId].borrowedAssets += _borrowedQuantity;
        } else {
            Position memory newPosition = Position({
                borrower: msg.sender,
                orderId: _borrowedOrderId,
                borrowedAssets: _borrowedQuantity
            });
            positions[lastPositionId] = newPosition;
            // update orders: add positionId in positionIds array
            orders[_borrowedOrderId].positionIds.push(lastPositionId);
            lastPositionId ++;
        }

        // update borrowables: remove order from borrowables if no more assets available
        if (getTotalAssetsLentByOrder(_borrowedOrderId) == orders[_borrowedOrderId].quantity) {
            _removeOrderFromBorrowables(_borrowedOrderId);
        }

        emit BorrowOrder(
            msg.sender,
            _borrowedOrderId,
            _borrowedQuantity,
            borrowedOrder.isBuyOrder
        );
    }


    /// @notice lets users decrease or close a borrowing position
    /// @param _repaidOrderId id of the order which assets are paid back
    /// @param _repaidQuantity quantity of assets paid back

    function repayBorrowing(
        uint256 _repaidOrderId,
        uint256 _repaidQuantity
    ) external orderExists(_repaidOrderId) isPositive(_repaidQuantity) {
        (uint256 borrowedQuantity, uint256 borrowingId) = getBorrowerPosition(
            msg.sender,
            _repaidOrderId
        );

        require(
            borrowedQuantity > 0,
            "repayBorrowing: No borrowing position found"
        );

        require(
            borrowedQuantity >= _repaidQuantity,
            "repayBorrowing: Repaid quantity exceeds borrowed quantity"
        );

        trasnferFrom(mes.sender, _repaidQuantity, orders[_repaidOrderId].isBuyOrder);

        positions[borrowingId].borrowedAssets -= _repaidQuantity;

        // if the borrowing line is emptied, delete it from the positions mapping
        if (positions[borrowingId].borrowedAssets == 0) {
            delete positions[borrowingId];
        }

        emit repayLoan(
            msg.sender,
            _repaidOrderId,
            _repaidQuantity,
            orders[_repaidOrderId].isBuyOrder
        );
    }

    ///////******* Internal functions *******///////

    // following a canceled order, screen orders to find the ones borrowable, which:
    // have the same type (buy or sell) as orderFrom, but are not orderFrom
    // have available assets to be borrowed, at least equal to the borrowed quantity (no fragmentation)
    // have the closest price to previous position
        
    function _findNewPosition(uint256 _positionId)
        internal
        positionExists(_positionId)
        returns (uint256 newOrderId)
    {
        Position memory position = positions[_positionId];
        Order memory borrowedOrder = orders[position.orderId];
        bool isBid = borrowedOrder.isBuyOrder; // type (buy or sell order) of orderFrom

        uint256[] orderList = borrowables(isBid);
        uint256 maxIterations = (maxListSize / borrowedOrder.positionIds.length).min(
            orderList.length);
        uint256 closestPrice = 0;
        uint256 closestOrderId = _positionId;

        for (uint256 i = 0; i < maxIterations; i++) {
            uint256 j = orderList[i];
            if (j != position.orderId &&
                (orders[j].quantity -
                    getTotalAssetsLentByOrder(j) >=
                    position.borrowedAssets)
            ) {
                if (closestPrice == 0
                || absolu(orders[j].price - borrowerOrder.price) 
                < absolu(closestPrice - borrowerOrder.price)) {
                    bool moreCollateral = isBid ? 
                    orders[j].price < borrowerOrder.price : 
                    orders[j].price > borrowerOrder.price;
                    if (moreCollateral) {
                        uint256 neededEquity = isBid ?
                            position.borrowedAssets / orders[j].price -
                            position.borrowedAssets / borrowerOrder.price
                            : position.borrowedAssets * (orders[j].price - borrowerOrder.price);
                        if (getUserEquity(position.borrower, isBid) >= neededEquity) {
                            closestPrice = orders[j].price;
                            closestOrderId = j;
                        }
                    } else {
                        closestPrice = orders[j].price;
                        closestOrderId = j;
                    }
                }          
            }
        }
        return newOrderId = closestOrderId;
    }

    // _orderToId is the order id to which the position is relocated
    // update internal balances:
    // retrieve the borrowing id of orderFrom
    // retrieve the borrower of the new order to which the debt is transferred
    // transfer the debt to the new order and update positions balances

    function _reposition(uint256 _positionId, uint256 _orderToId, uint256 _borrowedAssets)
        internal
        positionExists(_positionId) positionExists(_orderToId)
        returns (bool success)
    {
        address borrower = positions[_positionId].borrower;
        
        // update orders: add new positionId in positionIds array
        // check first that borrower does not borrow from _orderTo already

        uint256 row = getPositionIdRowInOrders(borrower, _orderToId);
        if (row != 2**256 - 1) {
            positions[_positionId].borrowedAssets += _borrowedAssets;
        } else {
            newPosition = Position({
                borrower: borrower,
                orderId: _orderToId,
                borrowedAssets: _borrowedAssets
            });
            orders[_orderToId].positionIds.push(newPosition);
        }

        // update positions: delete previous position
        // create new position with _orderTo
        // check first that borrower does not borrow from _orderTo already

        delete positions[_positionId];
        uint256 row = getBorrowFromIdsRowInUser(borrower, _orderToId);
        if (row != 2**256 - 1) {
            position = positions[_orderToId];
            positions[_positionId].borrowedAssets += _borrowedAssets;
        } else {
            newPosition = Position({
                borrower: borrower,
                orderId: _orderToId,
                borrowedAssets: _borrowedAssets
            });
            orders[_orderToId].positionIds.push(newPosition);
        }

        // update users: delete positionId in borrowFromIds
        
        users[borrower].borrowFromIds[row] 
        = users[borrower].borrowFromIds[users[borrower].borrowFromIds.length - 1];
        users[borrower].borrowFromIds.pop();
        // delete orderFrom from positionIds in orders mapping
        uint256 row = getPositionIdsRowInOrders(positions[_positionId].orderId, _positionId);
        orderFrom.positionIds[row] = orderFrom.positionIds[orderFrom.positionIds.length - 1];
        orderFrom.positionIds.pop();


        _removeOrderFromBorrowFromIds(orders[_removedOrderId].maker, _removedOrderId);
    }
    
    // called by removeOrder with _forceLiquidation = false and takeOrder with _forceLiquidation = true
    // if removal or taking is full, try to reposition *all* related borrowing positions
    // if removal or taking is partial, try to reposition enough to cover removed or taken quantity
    // positions are fully relocated or not at all
    // positions are relocated to one order only, which must have enough available assets
    // the total quantity displaced will be typically greater than the removed or taken quantity
    // Assets which couldn't be relocated are frozen if a removal or liquidated if a taking

    function _displaceAssets(
        uint256 _orderId, 
        uint256 _quantityToBeDisplaced, 
        bool _forceLiquidation
    ) 
    internal returns (uint256 displacedQuantity) {
        
        displacedQuantity = 0;
        // iterate on the borrowing ids of the order to be removed
        uint256[] memory positionIds = orders[_orderId].positionIds;

        for (uint256 i = 0; i < positionIds.length; i++) {
            // try to reposition the borrowing position in full
            uint256 newId = _findNewPosition(positionIds[i]);
            // if a new order is found, reposition the borrowing position
            if (newId != _orderId) {
                uint256 borrowedAssets = positions[positionIds[i]]
                .borrowedAssets;
                _reposition(_orderId, newId, borrowedAssets);
                // update displacedQuantity
                displacedQuantity += borrowedAssets;
            } else if (_forceLiquidation) {
                // if no new order is found, liquidate the borrowing position
                _liquidate(positions[positionIds[i]].borrower, _orderId);
                displacedQuantity += borrowedAssets;
            }
            // if enough assets are displaced, removal or taking is completed
            if (displacedQuantity >= _quantityToBeDisplaced) {
                break;
            }
        }
    }

    // the function takes as input the borrower's address and the order id which is taken or canceled ('orderFrom')
    // borrowed assets from orderFrom are repositioned to the next best-price order ('orderTo'), if exists
    // cannot reposition to more than one order and only if all _borrowedAssets can be transferred to orderTo,
    // some of orderTo's assets could already be borrowed, and the new borrowing doesn't have to exhaust its remaining assets
    // update internal debt balances, but doesn't perform the final transfer (removing or taking of orderFrom)
    // returns the id of orderTo if the reposition is successful, or the id of orderFrom if a failure

    function _repositionBorrowings(
        address _borrower,
        uint256 _orderOutId,
        uint256 _borrowedAssets
    )
        internal
        orderExists(_orderOutId)
        isPositive(_borrowedAssets)
        returns (uint256 newOrderId)
    {
        newOrderId = _orderOutId; // repositioning unsuccessfull by defaut
        bool isBid = orders[_orderOutId].isBuyOrder; // type (buy or sell order) of orderFrom

        // screen orders to find the ones borrowable, which:
        // have the same type (buy or sell) as orderFrom, but are not orderFrom
        // have available assets to be borrowed, at least equal to the borrowed quantity (no fragmentation)
        // have the best price (highest for buy orders, lowest for sell orders)

        uint256[] memory positionIds = orders[_orderOutId].positionIds;
        uint256 maxIterations;

        for (uint256 j = 0; j < positionIds.length; j++) {
            uint256 borrowedAssets = positions[positionIds[j]]
                    .borrowedAssets;
            uint256 closestPrice;
            if (isBid) {
                maxIterations = (maxListSize / positionIds.length).min(
                buyOrderList.length);
                for (uint256 i = 0; i < maxIterations; i++) {
                    uint256 k = borrowableSellOrders[i];
                    if (i != _orderOutId &&
                        (orders[k].quantity -
                            getTotalAssetsLentByOrder(k) >=
                            _borrowedAssets)
                    ) {
                        if (bestPrice == 0) {
                            bestPrice = orders[k].price;
                            newOrderId = k;
                        } else if (orders[i].price > bestPrice) {
                            bestPrice = orders[i].price;
                            newOrderId = i;
                        }
                    }
                }
            } else {

        }

        // still need to check whether the borrower has enough equity to switch
        // note: having selected the best-price next order minimize the issue
        // increasedCollateral: additional collateral needed to secure the increased debt

        uint256 increasedCollateral;

        // Ex 1) Bob borrows 2000 USDC from Alice's buy order of 2 ETH at 1800, needed collateral is 2000/1800 = 1.11 ETH
        // Alice's order is taken. Next buy order is 2 ETH at 1700, needed collateral is 2000/1700 = 1.18 ETH
        // Increased needed collateral is 2000/1700 - 2000/1800 = 0.07 ETH
        // Ex 2) Bob borrows 1.5 ETH from Alice's sell order of 2 ETH at 2000, needed collateral is 1.5*2000 = 3000 USDC
        // Alice's order is taken. Next sell order is 1.5 ETH at 2200, needed collateral is 1.5*2200 = 3300 USDC
        // Increased needed collateral is 1.5*(2200-2000) = 300 USDC

        if (newOrderId != _orderOutId) {
            uint256 orderExecutionPrice = orders[_orderOutId].price;
            uint256 nextExecutionPrice = orders[newOrderId].price;

            if (orders[_orderOutId].isBuyOrder) {
                increasedCollateral =
                    _borrowedAssets /
                    nextExecutionPrice -
                    _borrowedAssets /
                    orderExecutionPrice;
            } else {
                increasedCollateral =
                    _borrowedAssets *
                    (nextExecutionPrice - orderExecutionPrice);
            }

            // if the borrower has enough equity to switch to orderTo, update internal balances:
            // retrieve the borrowing id of orderFrom
            // retrieve the borrower of the new order to which the debt is transferred
            // transfer the debt to the new order and update positions balances

            if (
                getUserTotalDeposit(_borrower, isBid) >=
                getBorrowerNeededCollateral(_borrower, isBid) +
                    increasedCollateral
            ) {
                (, uint256 borrowingOutId) = getBorrowerPosition(
                    _borrower,
                    _orderOutId
                );

                // if the borrowing line is emptied, remove it from the positions array
                positions[borrowingOutId]
                    .borrowedAssets -= _borrowedAssets;

                if (positions[borrowingOutId].borrowedAssets == 0) {
                    positions[borrowingOutId] = positions[positions.length - 1];
                    positions.pop();
                }

                (
                    uint256 borrowedQuantity,
                    uint256 borrowingNewId
                ) = getBorrowerPosition(_borrower, newOrderId);

                // if the borrower doesn't already borrow from the new order, create a new borrowing position
                if (borrowedQuantity == 0) {
                    Position memory newBorrower = Position({
                        borrower: _borrower,
                        orderId: newOrderId,
                        borrowedAssets: _borrowedAssets
                    });
                    positions.push(newBorrower);
                } else {
                    // update the existing borrowing position
                    positions[borrowingNewId]
                        .borrowedAssets += _borrowedAssets;
                }
            }
        }
    }

    // takes as input the borrower address which position is liquidated and the id of the order taken
    // borrower's collateral is wiped out and his debt is written off for the same amount
    // multiple orders by the same borrower may collateralize the liquidated position
    // iterate on the book to find orders made by the borrower in the opposite currency
    // wipe out the orders as they come, stops when the borrower's debt is fully written off
    // liquidation is always full, i.e. the borrower's debt is fully written off
    // change internal balances, but doesn't execute external transfer of assets

    function _liquidate(
        address _borrower,
        uint256 _orderOutId
    ) internal orderExists(_orderOutId) {
        (uint256 borrowedQuantity, uint256 borrowingId) = getBorrowerPosition(
            _borrower,
            _orderOutId
        );

        bool isBid = orders[_orderOutId].isBuyOrder; // type (buy or sell order) of orderFrom

        uint256 remainingCollateralToWipeOut = borrowedQuantity;

        for (uint256 i = 0; i < orders.length; i++) {
            if (orders[i].maker == _borrower && orders[i].isBuyOrder != isBid) {
                uint256 orderAssets = orders[i].quantity;

                if (remainingCollateralToWipeOut >= orderAssets) {
                    remainingCollateralToWipeOut -= orderAssets;
                    delete orders[i];
                } else {
                    remainingCollateralToWipeOut = 0;
                    orders[i].quantity -= remainingCollateralToWipeOut;
                    break;
                }
            }

            require(
                remainingCollateralToWipeOut == 0,
                "liquidate: collateralToWipeOut != 0"
            );

            positions[borrowingId] = positions[positions.length - 1];
            positions.pop();
        }
    }

    function _transferTokenTo(address _to, uint256 _quantity, bool _isBuyOrder) 
        internal returns (bool success) {
        if (_isBuyOrder) {
            quoteToken.transfer(_to, _quantity);
        } else {
            baseToken.transfer(_to, _quantity);
        }
        success = true;
    }

    function _checkAllowanceAndBalance(
        address _user, 
        uint256 _quantity,
        bool _isBuyOrder
    ) internal returns(bool success){
        success = false;
        if (_isBuyOrder) {
            require(
                baseToken.balanceOf(_user) >= _quantity,
                "takeOrder, base token: Insufficient balance"
            );
            require(
                baseToken.allowance(_user, address(this)) >= quantity,
                "takeOrder, base token: Insufficient allowance"
            );
        } else {
            require(
                quoteToken.balanceOf(_user) >= quantity,
                "takeOrder, quote token: Insufficient balance"
            );
            require(
                quoteToken.allowance(_user, address(this)) >=
                    quantity,
                "takeOrder, quote token: Insufficient allowance"
            );
        }
        success = true;
    }
    
    function _transferTokenFrom(address _from, uint256 _quantity, bool _isBuyOrder) 
        internal returns (bool success) {
        if (_isBuyOrder) {
            require(quoteToken.balanceOf(_from) >= _quantity,
                "quote token: Insufficient balance"
            );
            require(quoteToken.allowance(_from, address(this)) >= _quantity,
                "quote token: Insufficient allowance"
            );
            quoteToken.transferFrom(_from, address(this), _quantity);
        } else {
            require(baseToken.balanceOf(_from) >= _quantityy,
                "base token: Insufficient balance"
            );
            require(baseToken.allowance(_from, address(this)) >= _quantity
                "base token: Insufficient allowance"
            );
            baseToken.transferFrom(_from, address(this), _quantity);
        }
        success = true;
    }

    function _removeOrderFromBorrowFromIds(address _remover, uint256 _removedOrderId)
        internal
        userExists(_remover)
        orderExists(_removedOrderId)
        returns (bool success)
    {
        success = false;
        uint256 row = getBorrowFromIdsRowInUser(_remover, _removedOrderId);
        if (row != 2**256 - 1) {
            users[_remover].borrowFromIds[row] 
            = users[_remover].borrowFromIds[users[_remover].borrowFromIds.length - 1];
            users[_remover].borrowFromIds.pop();
            success = true;
        }
    }

    function _removeOrderFromDepositIds(address _maker, uint256 _orderId)
        internal
        userExists(_maker)
        orderExists(_orderId)
        returns (bool success)
    {
        success = false;
        uint256 row = getDepositIdsRowInUser(_maker, _orderId);
        if (row != 2**256 - 1) {
            users[_maker].depositIds[row] 
            = users[_maker].depositIds[users[_maker].depositIds.length - 1];
            users[_maker].depositIds.pop();
            success = true;
        }
    }

    // remove order from the list of borrowable orders
    function _removeOrderFromBorrowables(uint256 _orderId)
        internal
        orderExists(_orderId)
        returns (bool success)
    {
        success = false;
        uint256 row = getOrderIdRowInBorrowables(_orderId);
        if (row != 2**256 - 1) {
            uint256[] orderList = orders[_orderId].isBuyOrder ? buyOrderList : sellOrderList;
            orderList[row] = orderList[orderList.length - 1];
            if (orders[_orderId].isBuyOrder) {
                buyOrderList.pop();
            } else {
                sellOrderList.pop();
            }
            success = true;
        }
    }


    // update orders: add new positionId in positionIds array
    // check first that borrower does not borrow from _orderTo already

    function _addOrderToPositions(address _borrower, uint256 _orderId, uint256 _borrowedAssets)

        uint256 row = getPositionIdRowInPosition(borrower, _orderToId);
        if (row != 2**256 - 1) {
            positions[_positionId].borrowedAssets += _borrowedAssets;
        } else {
            newPosition = Position({
                borrower: borrower,
                orderId: _orderToId,
                borrowedAssets: _borrowedAssets
            });
            orders[_orderToId].positionIds.push(newPosition);
        }

    

    //////////********* View functions *********/////////

    function getQuoteTokenAddress() public view returns (address) {
        return (address(quoteToken));
    }

    function getBaseTokenAddress() public view returns (address) {
        return (address(baseToken));
    }

    function getBookSize() public view returns (uint256) {
        return orders.length;
    }

    function getOrder(
        uint _orderId
    ) public view orderExists(_orderId) returns (Order memory) {
        return (orders[_orderId]);
    }

    // get the address of the maker of a given order
    function getMaker(
        uint256 _orderIndex
    ) public view orderExists(_orderId) returns (address) {
        return orders[_orderIndex].maker;
    }

    // check if the maker is a borrower
    function isMakerBorrower(
        address _maker
    ) internal view returns (bool isBorrower) {
        isBorrower = users[_maker].borrowFromIds.length > 0 ? true : false;
    }

    // returns the buy or sell order list
    function borrowables(
        bool _isBuyOrder
    ) internal view returns (uint256[] memory oderList) {
        orderList = _isBuyOrder ? buyOrderList : sellOrderList;
    }

    // get all assets deposited by a trader/borrower backing his limit orders, in the quote or base token
    function getBorrowerTotalDeposit(
        address _borrower,
        bool _isQuoteToken
    ) internal view returns (uint256 totalDeposit) {
        uint256[] memory depositIds = users[_borrower].depositIds;
        totalDeposit = 0;
        for (uint256 i = 0; i < depositIds.length; i++) {
            if (orders[depositIds[i]].isBuyOrder == _isQuoteToken
            ) {
                totalDeposit += orders[depositIds[i]].quantity;
            }
        }
    }

    // get borrower's total Debt in the quote or base token
    // to be corrected (orderId, not positionId)
    function getBorrowerTotalDebt(
        address _borrower,
        bool _isQuoteToken
    ) internal view returns (uint256 totalDebt) {
        uint256[] memory borrowFromIds = users[_borrower].borrowFromIds;
        totalDebt = 0;
        for (uint256 i = 0; i < borrowedIds.length; i++) {
            uint256[] memory position = positions[borrowedIds[i]];
            if (orders[position.orderId].isByOrder == _isQuoteToken) {
                totalDebt += position.borrowedAssets;
            }
        }
    }

    // get borrower's total collateral needed to secure his debt in the quote or base token
    // if order is a buy order, borrowed assets are in quote token and collateral needed is in base token
    // Ex: Alice deposits 2000 USDC to buy ETH at 2000; Bob borrows 1000 and put as collateral 1000/2000 = 0.5 ETH

    function getBorrowerNeededCollateral(
        address _borrower,
        bool _isQuoteToken
    ) internal view returns (uint256 totalNeededCollateral) {
        uint256[] memory borrowedIds = users[_borrower].borrowFromIds;
        totalNeededCollateral = 0;
        for (uint256 i = 0; i < borrowedIds.length; i++) {
            uint256[] memory position = positions[borrowedIds[i]];
            if (orders[position.orderId].isBuyOrder == _isQuoteToken) {
                totalNeededCollateral +=
                    position.borrowedAssets /
                    orders[position.orderId].price;
            } else {
                totalNeededCollateral +=
                    positions.borrowedAssets *
                    orders[position.orderId].price;
            }
        }
    }

    function getUserEquity (
        address _user,
        bool _isQuoteToken
    ) internal view userExists(_user) returns (uint256 equity) {
        equity = getUserTotalDeposit(_user, _isQuoteToken) 
        - getBorrowerNeededCollateral(_user, _isQuoteToken);
    }

    // function getBorrowerExcessCollateral(address borrower, bool _isBuyOrder) 
    // internal view returns (uint256 excessCollateral) {
    //     excessCollateral = getUserTotalDeposit(borrower, _isBuyOrder)
    //     - getBorrowerTotalDebt(borrower, _isBuyOrder);
    // }

    // get quantity of assets lent by order
    function getTotalAssetsLentByOrder(
        uint256 _orderIndex
    ) internal view orderExists(_orderIndex) returns (uint256 totalLentAssets) {
        uint256[] memory positions = orders[_orderIndex].positionIds;
        uint256 totalLentAssets = 0;
        for (uint256 i = 0; i < positionIds.length; i++) {
            totalLentAssets += positions[positionIds].borrowedAssets;
        }
    }

    // find in users if _maker has made _orderId
    // and, if so, what is its row in the depositIds array

    getDepositIdsRowInUser(
        address _maker,
        uint256 _orderId // in the depositIds array of users
    ) internal view returns (uint256 depositIdsRow) {
        depositIdsRow = 2**256 - 1;
        uint256[] memory depositds = users[_maker].depositIds;
        for (uint256 i = 0; i < depositIds.length; i++) {
            if (orders[depositIds[i]] == _orderId) {
                depositIdsRow = i;
                break
            }
        }
    }
    
    // check if user borrows from order
    // if so, returns the row in the borrowFromIds array

    getBorrowFromIdsRowInUser(
        address _borrower,
        uint256 _orderId // in the borrowFromIds array of users
    ) internal view returns (uint256 borrowFromIdsRow) {
        borrowFromIdsRow = 2**256 - 1;
        uint256[] memory borrowFromIds = users[_borrower].borrowFromIds;
        for (uint256 i = 0; i < borrowFromIds.length; i++) {
            if (orders[borrowFromIds[i]] == _orderId) {
                borrowFromIdsRow = i;
                break
            }
        }
    }

    // find in positionIds from orders if _positionId is included 
    // and, if so, at which row in positionIds array

    function getPositionIdsRowInOrders(
        uint256 _orderId,
        uint256 _positionId // in the positionIds array of the order _orderId
    ) internal view returns (uint256 PositionIdRow) {
        PositionIdRow = 2**256 - 1;
        uint256[] memory positionArray = orders[_orderId].positionIds;
        for (uint256 i = 0; i < positionArray.length; i++) {
            if (i = _positionId) {
                PositionIdRow = i;
                break
            }
        }
    }

    // find in positionIds from orders if _borrower borrows from _orderId
    // and, if so, at which row in the positionId array

    function getPositionIdRowInOrders(
        address _borrower,
        uint256 _orderId
    ) internal view returns (uint256 positionIdRow) {
        PositionIdRow = 2**256 - 1;
        uint256[] memory positionIds = orders[_orderId].positionIds;
        for (uint256 i = 0; i < positionIds.length; i++) {
            if (positions[positionIds[i]].borrower == _borrower) {
                PositionIdRow = i;
                break
            }
        }
    }

    function getPositionIdInPositions(address _borrower, uint256 _OrderId)
    intenal view returns (uint256 positionId) {
        positionId = 2**256 - 1;
        uint256 row = getPositionIdsRowInOrders(_borrower, _orderId);
        if (row != 2**256 - 1) {
            positionId = orders[_orderId].positionIds[row];
        }
    }

    function getOrderIdRowInBorrowables(uint256 _orderId)
    internal view returns (uint256 orderIdRow) {
        orderIdRow = 2**256 - 1;
        bool isBuyOrder = orders[_orderId].isBuyOrder;
        uint256[] memory orderList = isBuyOrder ? buyOrderList : sellOrderList;
        for (uint256 i = 0; i < orderList.length; i++) {
            if (orderList[i] == _orderId) {
                orderIdRow = i;
                break
            }
        }
    }
}
