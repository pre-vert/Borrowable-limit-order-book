// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

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
        uint256 orderId; // index in the mapping orders of the order which assets are borrowed
        uint256 borrowedAssets; // quantity of assets borrowed (quoteToken for buy orders, baseToken for sell orders)
    }

    mapping(uint256 orderIndex => Order) private orders;
    mapping(address user => User) private users;
    mapping(uint256 positionIndex => Position) private positions;

    // when an order is removed, we need to iterate on orders to reposition the debt
    // gas costs from looping on the book is bounded by:
    // - looping only on relevant orders = same side, with non-borowed and non-collateral assets
    // - setting a maxListSize for the number of orders to be scanned

    uint256[] buyOrderList; // unordered list of buy orders id 
    uint256[] sellOrderList; // unordered list of sell orders id 
    uint256 maxListSize = 10; // maximum number of orders to be scanned when repositioning debt
    
    uint256 lastOrderIndex = 0;
    uint256 lastPositionIndex = 0;

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
        require(_var > 0, "Mmust be positive");
        _;
    }

    modifier onlyMaker(address maker) {
        require(maker == msg.sender, "removeOrder: Only the maker can remove the order");
        _;
    }

    // lets users place orders in the order book
    // transfers the assets to the order book
    // adds a balance in the mapping orders

    function placeOrder(
        uint256 _quantity,
        uint256 _price,
        bool _isBuyOrder
    ) external isPositive(_quantity) isPositive(_price) {

        transferTokenFrom(msg.sender, _quantity, _isBuyOrder);
        
        if (_isBuyOrder) {
            buyOrderList.push(lastBuyOrderIndex);
        } else {
            sellOrderList.push(lastSellOrderIndex);
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
        orders[lastOrderIndex] = newOrder;

        // Update users mapping
        User memory user = User({
            depositIds: new uint256[](0), // Empty array
            borrowFromIds: new uint256[](0) // Empty array
        });
        user.depositIds.push(lastOrderIndex);
        users[msg.sender] = user;

        // Update list of borrowable orders
        if (_isBuyOrder) {
            buyOrderList.push(lastOrderIndex);
        } else {
            sellOrderList.push(lastOrderIndex);
        }

        lastOrderIndex++;

        emit PlaceOrder(msg.sender, _quantity, _price, _isBuyOrder);
    }

    // lets users partially or fully remove their orders from the book
    // the same order can have multiple borrowers
    // full removal is subject to succesful reallocation of all borrowed assets
    // partial removal is subject to reallocation of enough borrowing positions
    // all assets deposited >= desired quantity >= quantity actually removed:
    // orders[_removedOrderId].quantity >= _quantityToBeRemoved >= repositionedQuantity >= 0

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
        require(removedOrder.quantity >= _quantityToBeRemoved,
            "removeOrder: Removed quantity exceeds deposit"
        );

        // Remaining total deposits must be enough to secure existing borrowing positions
        require(_quantityToBeRemoved <= getBorrowerExcessCollateral(removedOrder.isBuyOrder),
            "removeOrder: Close your borrowing positions before removing your orders"
        );

        // if removal is full, try to reposition *all* related borrowing positions
        // if removal is partial, try to reposition enough to cover removed quantity
        // for each detected borrowing positions, the repositioned assets are either the quantity
        // borrowed by the position (if less) or the remaining quantity to be repositioned (if less)
        // a borrowing position is either fully repositioned (all borrowed assets are moved) or not at all
        // if not enough assets are repositioned, removal is equal to removed quantity

        uint256 repositionedQuantity = 0;

        // iterate on the borrowing ids of the order to be removed
        uint256[] memory positionIds = orders[_removedOrderId].positionIds;

        for (uint256 i = 0; i < positionIds.length; i++) {
            // try to reposition the borrowing position in full
            uint256 newId = findNewPosition(positionIds[i]);
            // if debt reposition is successful,
            if (newId != _removedOrderId) {
                uint256 quantityToReposition = positions[positionIds[i]]
                .borrowedAssets;
                reposition(_removedOrderId, newId, quantityToReposition);
                // update repositionedQuantity
                repositionedQuantity += quantityToReposition;
            }
            // if enough assets are repositioned, removal is completed
            if (repositionedQuantity == _quantityToBeRemoved) {
                break;
            }
        }

        // removal is executed for the quantity actually repositioned
        if (repositionedQuantity > 0) {
            transferTokenTo(msg.sender, repositionedQuantity, removedOrder.isBuyOrder);

            // if all borrowed assets could be repositioned, removal is complete
            // in this case, remove the order from the book, otherwise adjust internal balances

            if (repositionedQuantity == removedOrder.quantity) {
                delete orders[_removedOrderId];
            } else {
                orders[_removedOrderId].quantity -= repositionedQuantity;
            }
        }

        emit RemoveOrder(
            msg.sender,
            repositionedQuantity,
            removedOrder.price,
            removedOrder.isBuyOrder
        );
    }

    // let users take sell and buy orders on the book, regardless their assets are borrowed or not
    // assets can be partially taken
    // taking triggers liquidation of related borrowing positions which cannot be repositioned
    // some borrowing positions can be liquidated while others are repositioned
    // the marginal borrowing position can be partially repositioned if taking is partial
    // if they are liquidated, they are in full

    function takeOrder(
        uint256 _takenOrderId,
        uint256 _takenQuantity
    ) external orderExists(_takenOrderId) isPositive(_takenQuantity) {
        Order memory takenOrder = orders[_takenOrderId];

        require(
            _takenQuantity <= takenOrder.quantity,
            "takeOrder: Taken quantity exceeds deposit"
        );
        if (takenOrder.isBuyOrder) {
            uint256 baseQuantity = _takenQuantity / takenOrder.price;
            require(
                baseToken.balanceOf(msg.sender) >= baseQuantity,
                "takeOrder, base token: Insufficient balance"
            );
            require(
                baseToken.allowance(msg.sender, address(this)) >= baseQuantity,
                "takeOrder, base token: Insufficient allowance"
            );
        } else {
            uint256 quoteQuantity = _takenQuantity * takenOrder.price;
            require(
                quoteToken.balanceOf(msg.sender) >= quoteQuantity,
                "takeOrder, quote token: Insufficient balance"
            );
            require(
                quoteToken.allowance(msg.sender, address(this)) >=
                    quoteQuantity,
                "takeOrder, quote token: Insufficient allowance"
            );
        }

        // tries to reposition enough associated borrowing positions (if any) in the order book to cover the taken quantity
        // for each borrowing position detected, the matching engine tries to reposition the full position
        // unless it is larger than what is left to be repositioned
        // example: Alice deposits 3600 USDC to buy 2 ETH at 1800; Bob borrows 1800 and Carole 1200 from Alice
        // half of Alice's order is taken: the borrowing of 1800 USDC must be repositionned
        // Carole's borrowing is fully repositionned: remains 600 USDC to reposition
        // for Bob, the next order selected has 1000 USDC available to be borrowed
        // of which 600 USDC are repositioned; Bob's remaining borrowing 1800-600 = 1200 USDC is not repositioned
        // which corresponds to Alice's remaining order of 1800-600 = 1200 USDC

        uint256 repositionedQuantity = 0;

        // Two cases:
        // 1) the quantity left to be repositioned is greater than the borrowed assets of the order
        // _takenQuantity - repositionedQuantity >= positions[i].borrowedAssets
        // the quantity to reposition is at most the borrowed assets of the order: quantityToReposition = positions[i].borrowedAssets
        // 2) the quantity left to be repositioned is less than borrowed assets of a given order
        // the quantity to reposition is at most the quantity left to be repositioned

        uint256[] memory positionIds = orders[_takenOrderId].positionIds;

        for (uint256 i = 0; i < positionIds.length; i++) {
            uint256 quantityToReposition = positions[positionIds[i]]
                .borrowedAssets
                .min(_takenQuantity - repositionedQuantity);

            // try to reposition the borrowing position in full
            uint256 newId = repositionBorrowings(
                positions[positionIds[i]].user,
                _takenOrderId,
                quantityToReposition
            );

            // 1a) success: the borrowing position is fully repositioned
            // 1b) failure: the borrowing position is fully liquidated
            // In both cases, repositionedQuantity =< _takenQuantity
            // 2a) success: the borrowing position is partially repositioned
            //     repositionedQuantity = _takenQuantity => process complete
            //     => all remaining positions can live on the assets of the order which are not taken
            // 2b) failure: the borrowing position is fully liquidated

            if (newId != _takenOrderId) {
                // 1a) or 2a)
                repositionedQuantity += quantityToReposition;
                if (repositionedQuantity == _takenQuantity) {
                    break;
                }
            } else {
                // 1b) or 2b)
                liquidate(positions[positionIds[i]].user, _takenOrderId);
            }
        }

        // once repositionedQuantity == _takenQuantity, execution of the swap
        // all borrowing positions have been repositioned, liquidated or preserved

        if (takenOrder.isBuyOrder) {
            uint256 quantity = _takenQuantity / takenOrder.price;
        } else {
            uint256 quantity = _takenQuantity * takenOrder.price;
        }

        transferTokenFrom(msg.sender, quantity, takenOrder.isBuyOrder);
        transferTokenTo(takenOrder.maker, quantity, takenOrder.isBuyOrder);
        transferTokenTo(msg.sender, _takenQuantity, takenOrder.isBuyOrder);

        // if the taker takes all the assets of the order, remove the order from the book
        // otherwise adjust internal balances

        if (_takenQuantity == takenOrder.quantity) {
            delete orders[_takenOrderId];
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

    // let users with assets on the book borrow assets on the other side of the book
    // create a borrowing position or increase an existing one
    // orders are borrowable if
    // - the maker is not a borrower (i.e. the assets are not used as collateral)
    // - the borrower does not demand more assets than available
    // - the borrower has enough equity to borrow the assets

    function borrowOrder(
        uint256 _borrowedOrderId,
        uint256 _borrowedQuantity
    )
        external
        orderExists(_borrowedOrderId)
        isPositive(_borrowedQuantity)
    {
        Order memory borrowedOrder = orders[_borrowedOrderId];

        require(
            _borrowedQuantity > 0,
            "borrowOrder: Borrowed assets must be positive"
        );

        require(
            isOrderBorrowable(_borrowedOrderId),
            "borrowOrder: Assets not available for borrowing"
        );

        uint256 availableAssets = borrowedOrder.quantity -
            getTotalAssetsLentByOrder(_borrowedOrderId);
        require(
            availableAssets >= _borrowedQuantity,
            "borrowOrder: Insufficient available assets"
        );

        // borrowerEquity is excess deposit available to collateralize additional debt
        uint256 borrowerEquity = getUserTotalDeposit(
            msg.sender,
            borrowedOrder.isBuyOrder
        ) - getBorrowerNeededCollateral(msg.sender, borrowedOrder.isBuyOrder);
        require(
            borrowedOrder.quantity <= borrowerEquity,
            "borrowOrder: Deposit more collateral"
        );

        transferTokenTo(msg.sender, _borrowedQuantity, borrowedOrder.isBuyOrder);

        // update internal records for the new borrowing position
        // begin by searching for an existing borrowing position to update

        uint256[] memory positionIds = orders[_borrowedOrderId].positionIds;
        bool borrowerExists = false;

        for (uint256 i = 0; i < positionIds.length; i++) {
            if (positions[positionIds[i]].user == msg.sender) {
                positions[positionIds[i]].borrowedAssets += _borrowedQuantity;
                borrowerExists = true;
                break;
            }
        }

        // if no existing borrowing position, create a new one

        if (!borrowerExists) {
            Position memory newBorrower = Position({
                borrower: msg.sender,
                orderId: _borrowedOrderId,
                borrowedAssets: _borrowedQuantity
            });

            positions[lastBorrowerIndex] = newBorrower;
            lastBorrowerIndex++;
        }

        emit BorrowOrder(
            msg.sender,
            _borrowedOrderId,
            _borrowedQuantity,
            borrowedOrder.isBuyOrder
        );
    }

    // lets users decrease or close a borrowing position

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
        
    function findNewPosition(uint256 _positionId)
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

    // if a new position is found, update internal balances:
    // retrieve the borrowing id of orderFrom
    // retrieve the borrower of the new order to which the debt is transferred
    // transfer the debt to the new order and update positions balances

    function reposition(uint256 _positionId, uint256 _orderToId, uint256 _quantityToReposition)
        internal
        positionExists(_positionId) positionExists(_orderToId)
        returns (bool success)
    {
        address borrower = positions[_positionId].borrower;
        
        if (positions[_positionId].borrowedAssets > _quantityToReposition) {
            // update positions mapping
            positions[_positionId].borrowedAssets -= _quantityToReposition;
        } if else (positions[_positionId].borrowedAssets == _quantityToReposition) {
            delete positions[_positionId];
            // delete borrowing from borrowFromIds in users mapping
            uint256 row = getBorrowFromIdsRowOfOrderId(borrower, positions[_positionId].orderId)
            users[borrower].borrowFromIds[row] 
            = users[borrower].borrowFromIds[users[borrower].borrowFromIds.length - 1];
            users[borrower].borrowFromIds.pop();
            // delete orderFrom from positionIds in orders mapping
            uint256 row = getPositionIdRowOfOrderId(positions[_positionId].orderId, _positionId);
            orderFrom.positionIds[row] = orderFrom.positionIds[orderFrom.positionIds.length - 1];
            orderFrom.positionIds.pop();
        }

        // struct User {
        // uint256[] depositIds; // stores orders id in mapping orders to which borrower deposits
        // uint256[] borrowFromIds; // stores orders id in mapping orders from which borrower borrows

        // add orderTo in positionIds in orders mapping
        // check first that orderTo is not already in positionIds
        uint256 row = getPositionIdRowOfBorrower(_orderToId, borrower);
        if (row != 2**256 - 1) {
            positions[_positionId].borrowedAssets += _quantityToReposition;
        } else {
            newPosition = Position({
                borrower: borrower,
                orderId: _orderToId,
                borrowedAssets: _quantityToReposition
            });
            orders[_orderToId].positionIds.push(newPosition);
        }
    }
    
    // the function takes as input the borrower's address and the order id which is taken or canceled ('orderFrom')
    // borrowed assets from orderFrom are repositioned to the next best-price order ('orderTo'), if exists
    // cannot reposition to more than one order and only if all _quantityToReposition can be transferred to orderTo,
    // some of orderTo's assets could already be borrowed, and the new borrowing doesn't have to exhaust its remaining assets
    // update internal debt balances, but doesn't perform the final transfer (removing or taking of orderFrom)
    // returns the id of orderTo if the reposition is successful, or the id of orderFrom if a failure

    function repositionBorrowings(
        address _borrower,
        uint256 _orderOutId,
        uint256 _quantityToReposition
    )
        internal
        orderExists(_orderOutId)
        isPositive(_quantityToReposition)
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
            uint256 quantityToReposition = positions[positionIds[j]]
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
                            _quantityToReposition)
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
                    _quantityToReposition /
                    nextExecutionPrice -
                    _quantityToReposition /
                    orderExecutionPrice;
            } else {
                increasedCollateral =
                    _quantityToReposition *
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
                    .borrowedAssets -= _quantityToReposition;

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
                        borrowedAssets: _quantityToReposition
                    });
                    positions.push(newBorrower);
                } else {
                    // update the existing borrowing position
                    positions[borrowingNewId]
                        .borrowedAssets += _quantityToReposition;
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

    function liquidate(
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

    function transferTokenTo(address _to, uint256 _quantity, bool _isBuyOrder) 
        internal returns (bool success) {
        if (_isBuyOrder) {
            quoteToken.transfer(_to, _quantity);
        } else {
            baseToken.transfer(_to, _quantity);
        }
        success = true;
    }

    function transferTokenFrom(address _from, uint256 _quantity, bool _isBuyOrder) 
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

    function borrowables(
        bool _isBuyOrder
    ) internal view returns (uint256[] memory oderList) {
        orderList = _isBuyOrder ? buyOrderList : sellOrderList;
    }

    // only assets which do not serve as collateral are borrowable
    // check if the maker is not a borrower

    function isOrderBorrowable(
        uint256 _orderIndex
    ) internal view orderExists(_orderId) returns (bool) {
        return !isMakerBorrower(getMaker(_orderIndex));
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
    function getBorrowerTotalDebt(
        address _borrower,
        bool _isQuoteToken
    ) internal view returns (uint256 totalDebt) {
        uint256[] memory borrowedIds = users[_borrower].borrowFromIds;
        totalDebt = 0;
        for (uint256 i = 0; i < borrowedIds.length; i++) {
            uint256[] memory position = positions[borrowedIds[i]];
            if (orders[position.orderId].isByOrder == _isQuoteToken) {
                totalLentDebt += position.borrowedAssets;
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

    function getBorrowerExcessCollateral(bool _isBuyOrder) internal view returns (uint256 excessCollateral) {
        excessCollateral = getUserTotalDeposit(msg.sender, _isBuyOrder)
        - getBorrowerTotalDebt(msg.sender, _isBuyOrder);
    }

    // get quantity of assets lent by the order
    function getTotalAssetsLentByOrder(
        uint256 _orderIndex
    ) internal view orderExists(_orderIndex) returns (uint256 totalLentAssets) {
        uint256[] memory positions = orders[_orderIndex].positionIds;
        uint256 totalLentAssets = 0;
        for (uint256 i = 0; i < positionIds.length; i++) {
            totalLentAssets += positions[positionIds].borrowedAssets;
        }
    }
}

    // takes as inputs the borrower's address and the order id from which assets are borrowed
    // returns borrower's borrowed quantity and borrowing id in array positions
    // returns borrowed quantity = 0 if the address doesn't borrow from the order

    function getBorrowerPosition(
        address _borrowerAddress,
        uint256 _orderId
    )
        internal
        view
        orderExists(_orderId)
        returns (uint256 borrowerLoan, uint256 borrowingId)
    {
        borrowerLoan = 0;
        borrowingId = 0;
        for (uint256 j = 0; j < positions.length; j++) {
            if (
                positions[j].borrower == _borrowerAddress &&
                positions[j].orderId == _orderId &&
                positions[j].borrowedAssets > 0
            ) {
                borrowingId = j;
                borrowerLoan = positions[j].borrowedAssets;
                break;
            }
        }
    }

    // find if _positionId is listed in the positionIds array of the order _orderId, and at which row
    function getPositionIdRowOfOrderId(
        uint256 _orderId,
        uint256 _positionId // in the positionIds array of the order _orderId
    ) internal view returns (uint256 PositionIdsRow) {
        PositionIdsRow = 2**256 - 1;
        uint256[] memory positionArray = orders[_orderId].positionIds;
        for (uint256 i = 0; i < positionArray.length; i++) {
            if (i = _positionId) {
                PositionIdsRow = i;
                break
            }
        }
    }

    getBorrowFromIdsRowOfOrderId(
        address _borrower
        uint256 _orderId,
    ) internal view returns (uint256 borrowFromIdsRow) {
        borrowFromIdsRow = 2**256 - 1;
        uint256[] memory borrowFromIdsArray = users[_borrower].borrowFromIds;
        for (uint256 i = 0; i < borrowFromIdsArray.length; i++) {
            if (orders[borrowFromIdsArray[i]] == _orderId) {
                borrowFromIdsRow = i;
                break
            }
        }
    }

    // find if _borrower borrows from _orderId, and, if so, what is its row in the positionId array
    function getPositionIdRowOfBorrower(
        uint256 _orderId,
        address _borrower
    ) internal view returns (uint256 positionIdRow) {
        PositionIdsRow = 2**256 - 1;
        uint256[] memory positionArray = orders[_orderId].positionIds;
        for (uint256 i = 0; i < positionArray.length; i++) {
            Position memory position = positions[positionArray[i]];
            if (position.borrower == _borrower) {
                PositionIdsRow = i;
                break
            }
        }
    }
}
