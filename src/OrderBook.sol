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
        require(order.quantity != 0 && order.quantity != 0, "Order does not exist");
        _;
    }

    modifier userExists(address _user) {
        Order memory user = users[_user];
        require(user.depositIds.length > 0, "User does not exist");
        _;
    }

    modifier positionExists(uint256 _positionId) {
        Order memory position = positionss[_positionInde];
        require(position.borrower != address(0), "Borrowing position does not exist");
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
        require(!isMakerBorrower(getMaker(_orderId)),
            "Assets used as collateral: not available for borrowing");
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

        _checkAllowanceAndBalance(msg.sender, _quantity, _isBuyOrder);
        _transferTokenFrom(msg.sender, _quantity, _isBuyOrder);

        // update orders: add order to orders
        // output the id of the new order
        uint256 newOrderId = _addOrderToOrders(
            msg.sender,
            _isBuyOrder,
            _quantity,
            _price,
            new uint256[](0) // Empty array
        );

        // Update users: add orderId in depositIds array
        pushOrderIdInDepositIdsInUsers(newOrderId, msg.sender);

        // User memory user = User({
        //     depositIds: new uint256[](0), // Empty array
        //     borrowFromIds: new uint256[](0) // Empty array
        // });
        // user.depositIds.push(lastOrderId);
        // users[msg.sender] = user;

        // Update list of borrowable orders
        _pushOrderIdInBorrowables(newOrderId);
        
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
        bool liquidate = true;
        uint256 repositionedQuantity = _displaceAssets(_removedOrderId, _quantityToBeRemoved, !liquidate);

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
            _removeOrderFromDepositIdsInUsers(remover, _removedOrderId);
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
    /// partial taking liquidates enough borrowing positions
    /// full taking liquidates all borrowing positions
    /// liquidated position are in full
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

        // liquidate enough borrowing positions
        // output the quantity actually displaced, which must be >= the taken quantity
        bool liquidate = true;
        uint256 displacedQuantity = _displaceAssets(_takenOrderId, _takenQuantity, liquidate);
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

        _checkAllowanceAndBalance(msg.sender, exchangedQuantity, !takenOrder.isBuyOrder);

        // if taking is full:
        // - remove order in orders
        // - remove orderId in depositIds array in users
        // - remove order from the list of borrowable orders
        // otherwise adjust internal balances
        if (_takenQuantity == takenOrder.quantity) {
            delete orders[_takenOrderId];
            _removeOrderFromDepositIdsInUsers(takenOrder.maker, _takenOrderId);
            _removeOrderFromBorrowables(_removedOrderId);
        } else {
            takenOrder.quantity -= _takenQuantity;
        }

        // if a buy order is taken, the taker pays the quoteToken and receives the baseToken
        _checkAllowanceAndBalance(msg.sender, exchangedQuantity, !takenOrder.isBuyOrder);
        _transferTokenFrom(msg.sender, exchangedQuantity, !takenOrder.isBuyOrder);
        _transferTokenTo(takenOrder.maker, exchangedQuantity, takenOrder.isBuyOrder);
        _transferTokenTo(msg.sender, _takenQuantity, takenOrder.isBuyOrder);

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

        // userEquity is excess deposits available to collateralize additional debt
        require(
            getUserEquity(msg.sender, borrowedOrder.isBuyOrder) >=
            borrowedOrder.quantity,
            "borrowOrder: Insufficient equity to borrow assets, deposit more collateral"
        );

        // update users: add orderId in borrowFromIds array
        // check first if borrower already borrows from order
        uint256 row = getBorrowFromIdsRowInUser(msg.sender, _borrowedOrderId);
        if (row == 2**256 - 1) {
            users[msg.sender].borrowFromIds.push(_borrowedOrderId);
        }

        // update positions: add borrowing position
        // check first if a borrowing position alreday exists
        uint256 positionId = getPositionIdInPositions(_borrowedOrderId, msg.sender);
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

        _transferTokenTo(msg.sender, _borrowedQuantity, borrowedOrder.isBuyOrder);

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
    ) external 
    orderExists(_repaidOrderId) 
    isPositive(_repaidQuantity)
    {
        Orders memory repaidOrder = orders[_repaidOrderId];

        uint256 positionId = getPositionIdInPositions(_repaidOrderId, msg.sender);
        require(
            positionId != 2**256 - 1 && position[positionId].borrowedAssets > 0,
            "repayBorrowing: No borrowing position found"
        );

        require(
            _repaidQuantity <= position[positionId].borrowedAssets,
            "repayBorrowing: Repaid quantity exceeds borrowed quantity"
        );

        // update positions: decrease borrowedAssets
        position[positionId].borrowedAssets -= _repaidQuantity;

        // if borrowing is fully repaid, delete position in positions and positionId from positionIds in orders
        if (positions[borrowingId].borrowedAssets == 0) {
            delete positions[borrowingId];
            uint256 row = getPositionIdsRowInOrders(_repaidOrderId, msg.sender);
            if (row != 2**256 - 1) {
                orders[_repaidOrderId].positionIds[row] 
                = orders[_repaidOrderId].positionIds[orders[_repaidOrderId].positionIds.length - 1];
                orders[_repaidOrderId].positionIds.pop();
            }
            // if user is not a borrower anymore, his own orders become borrowable
            // => include all his orders in the borrowable list
            if (!isMakerBorrower(msg.sender)) {
                for (uint256 i = 0; i < users[msg.sender].depositIds.length; i++) {
                    uint256 orderId = users[msg.sender].depositIds[i];
                    _pushOrderIdInBorrowables(orderId);
                }
            }
        }

        _checkAllowanceAndBalance(ms.sender, _repaidQuantity, orders[_repaidOrderId].isBuyOrder);
        _transferTokenFrom(ms.sender, _repaidQuantity, orders[_repaidOrderId].isBuyOrder);

        emit repayLoan(
            msg.sender,
            _repaidOrderId,
            _repaidQuantity,
            orders[_repaidOrderId].isBuyOrder
        );
    }

    ///////******* Internal functions *******///////

    // following removeOrder(), screen orders to find one borrowable, which:
    // have the same type (buy or sell) as fromOrderId, but are not fromOrderId
    // have available assets to be borrowed, at least equal to the borrowed quantity (no fragmentation)
    // have the closest price to previous position
        
    function _findNewPosition(uint256 _positionId)
        internal
        positionExists(_positionId)
        returns (uint256 newOrderId)
    {
        Position memory position = positions[_positionId];
        Order memory borrowedOrder = orders[position.orderId];
        bool isBid = borrowedOrder.isBuyOrder; // type (buy or sell order) of fromOrderId
        bool isQuoteToken = true;
        uint256[] orderList = _isBid ? buyOrderList : sellOrderList;
        uint256 maxIterations = (maxListSize / borrowedOrder.positionIds.length).min(
            orderList.length);
        uint256 closestPrice = 0;
        uint256 newOrderId = position.orderId;

        for (uint256 i = 0; i < maxIterations; i++) {
            uint256 j = orderList[i];
            if (j != position.orderId
            && (orders[j].quantity - getTotalAssetsLentByOrder(j)
                >= position.borrowedAssets)
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
                        if (getUserEquity(position.borrower, !isQuoteToken) > neededEquity) {
                            closestPrice = orders[j].price;
                            newOrderId = j;
                        }
                    } else {
                        closestPrice = orders[j].price;
                        newOrderId = j;
                    }
                }          
            }
        }
    }

    // _toOrderId is the order id, selected by _findNewPosition(), to which the borrowing is relocated
    // update all internal balances: orders, users and positions

    function _reposition(
        uint256 _fromPositionId, // position id to be removed
        uint256 _toOrderId // order id to which the borrowing is relocated
    )
        internal
        positionExists(_fromPositionId) orderExists(_toOrderId)
        returns (bool success)
    {
        address borrower = positions[_fromPositionId].borrower;
        uint256 fromOrderId = positions[_fromPositionId].orderId;

        // update positions: create new or update existing borrowing position in positions
        // output the id of the new or updated borrowing position
        uint256 positionId = _addPositionToPositions(
            borrower,
            _toOrderId,
            positions[_fromPositionId].borrowedAssets
        );
        
        // update orders: push new positionId in positionIds array of _toOrderId
        _pushNewPositionIdInOrder(positionId, _toOrderId);

        // update users: add toOrderId in borrowFromIds array if doesn't exist alrady
        _addOrderToBorrowFromIdsinUsers(positionId, borrower);
      
        // update users: delete fromOrderId in borrowFromIds array (reposiiton is full)
        _removeOrderIdFromBorrowFromIdsinUsers(orders[fromOrderId].maker, fromOrderId);
 
        // update orders: delete positionId from positionIds array of fromOrderId (reposiiton is full)
        _removeOrderIdFromPositionIdsInOrders(fromOrderId, borrower);
  
        // update positions: delete previous position (reposiiton is full)
        delete positions[_fromPositionId];
    }
    
    // called by removeOrder() with !liquidate (never liquidate) and takeOrder() with liquidate (always liquidate)
    // if removal, try to relocate enough, if not, forbid removal of non-relocated assets
    // positions are fully relocated to one order (1 to 1), or locked
    // => total quantity actually removed can be greater or lower than the quantity to be removed
    // if taking, even partial, liquidate all borrowing positions
    // output the quantity actually relocated (removal) or liquidated (taking)
    // doesn't perform the final transfer (removing or taking)

    function _displaceAssets(
        uint256 _fromOrderId, // order from which borrowing positions must be cleared
        uint256 _quantityToDisplace, // quantity removed or taken
        bool _liquidate // true if taking, false if removing
    ) 
    internal returns (uint256 displacedQuantity) {
        
        displacedQuantity = 0;
        // iterate on the borrowing ids of the order to be removed
        uint256[] memory positionIds = orders[_fromOrderId].positionIds;

        for (uint256 i = 0; i < positionIds.length; i++) {
            uint256 fromPositionId = positions[positionIds[i]];
            if (!_liquidate) {
                // try to reposition borrowing position in full
                uint256 toOrderId = _findNewPosition(positionIds[i]);
                // if a new order is found, reposition the borrowing position
                if (toOrderId != _fromOrderId) {
                    _reposition(fromPositionId, toOrderId);
                    // update displacedQuantity
                    displacedQuantity += fromPositionId.borrowedAssets;
                }
            } else {
                // liquidate the borrowing position
                _liquidate(fromPositionId.borrower, _fromOrderId);
                displacedQuantity += fromPositionId.borrowedAssets;
            }
            // if enough assets are displaced, removal or taking is completed
            if (displacedQuantity >= _quantityToDisplace) {
                break;
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
        uint256 _fromOrderId
    ) internal orderExists(_fromOrderId) {
        (uint256 borrowedQuantity, uint256 borrowingId) 
        = getBorrowerPosition(_borrower, _fromOrderId);

        bool isBid = orders[_fromOrderId].isBuyOrder; // type (buy or sell order) of fromOrderId

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

    // tranfer ERC20 tokens from the contract to the user
    function _transferTokenTo(address _to, uint256 _quantity, bool _isBuyOrder) 
        internal returns (bool success) {
        if (_isBuyOrder) {
            quoteToken.transfer(_to, _quantity);
        } else {
            baseToken.transfer(_to, _quantity);
        }
        success = true;
    }

    // check allowance and balance before ERC20 transfer
    // 
    
    function _checkAllowanceAndBalance(
        address _user, 
        uint256 _quantity,
        bool _isBuyOrder
    ) internal returns(bool success){
        success = false;
        if (_isBuyOrder) {
            require(
                quoteToken.balanceOf(_user) >= _quantity,
                "quote token: Insufficient balance"
            );
            require(
                quoteToken.allowance(_user, address(this)) >= quantity,
                "quote token: Insufficient allowance"
            );
        } else {
            require(
                baseToken.balanceOf(_user) >= quantity,
                "base token: Insufficient balance"
            );
            require(
                baseToken.allowance(_user, address(this)) >=
                    quantity,
                "base token: Insufficient allowance"
            );
        }
        success = true;
    }
    
    // transfer ERC20 tokens from user to the contract
    function _transferTokenFrom(address _from, uint256 _quantity, bool _isBuyOrder) 
        internal returns (bool success) 
    {
        if (_isBuyOrder) {
            quoteToken.transferFrom(_from, address(this), _quantity);
        } else {
            baseToken.transferFrom(_from, address(this), _quantity);
        }
        success = true;
    }

    function _addOrderToOrders(
        address _maker,
        bool _isBuyOrder,
        uint256 _quantity,
        uint256 _price,
        uint256[] borrowingIds
    ) internal returns (uint256 orderId) {
        uint256[] memory borrowingIds; // Empty array
        Order memory newOrder = Order({
            maker: msg.sender,
            isBuyOrder: _isBuyOrder,
            quantity: _quantity,
            price: _price,
            positionIds: borrowingIds
        });
        orders[lastOrderId] = newOrder;
        orderId = lastOrderId;
        lastOrderId++;
    }

    function pushOrderIdInDepositIdsInUsers(
        uint256 _orderId,
        address _maker            
    ) intenal orderIdExists(_orderId) userExists(_maker) {
        uint256 row = getDepositIdsRowInUsers(_maker, _orderId);
        if (row == 2**256 - 1) {
            users[_maker].depositIds.push(_orderId);
        }
    }
        
    function _removeOrderIdFromBorrowFromIdsinUsers(
        address _user,
        uint256 _orderId
    )
        internal
        userExists(_user)
        orderExists(_orderId)
        returns (bool success)
    {
        success = false;
        uint256 row = getBorrowFromIdsRowInUser(_user, _orderId);
        if (row != 2**256 - 1) {
            uint256[] borrowFromIds = users[_user].borrowFromIds;
            borrowFromIds[row] = borrowFromIds[borrowFromIds.length - 1];
            borrowFromIds.pop();
            success = true;
        }
    }

    function _removeOrderIdFromPositionIdsInOrders(
            uint256 orderId,
            address borrower) 
        internal returns (bool success)
        {
            uint256 row = getPositionIdsRowInOrders(orderId, borrower);
            if (row != 2**256 - 1) {
                uint256[] positionIds = orders[orderId].positionIds;
                positionIds[row] = positionIds[positionIds.length - 1];
                positionIds.pop();
            }
            success = true;
        }

    function _removeOrderFromDepositIdsInUsers(address _maker, uint256 _orderId)
        internal
        userExists(_maker)
        orderExists(_orderId)
        returns (bool success)
    {
        success = false;
        uint256 row = getDepositIdsRowInUsers(_maker, _orderId);
        if (row != 2**256 - 1) {
            users[_maker].depositIds[row] 
            = users[_maker].depositIds[users[_maker].depositIds.length - 1];
            users[_maker].depositIds.pop();
            success = true;
        }
    }

    // push order in the list of borrowable orders
    function _pushOrderIdInBorrowables(uint256 _orderId)
        internal orderExists(_orderId)
    {
        uint256 row = getOrderIdRowInBorrowables(_orderId);
        if (row == 2**256 - 1) {
            if (orders[_orderId]_isBuyOrder) {
                buyOrderList.push(lastOrderId);
            } else {
                sellOrderList.push(lastOrderId);
            }
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
    // returns existing or new position id in positions mapping

    function _addPositionToPositions(
        address _borrower,
        uint256 _orderId,
        uint256 _borrowedAssets
    ) internal returns (uint256 positionId) 
    {
        uint256 positionId = getPositionIdInPositions(_orderId, borrower);
        if (positionId != 2**256 - 1) {
            positions[_positionId].borrowedAssets += _borrowedAssets;
        } else {
            Position memory newPosition = Position({
                borrower: borrower,
                orderId: _toOrderId,
                borrowedAssets: _borrowedAssets
            });
            positions[lastPositionId] = newPosition;
            positionId = lastPositionId;
            lastPositionId ++;
        }
    }

    // update orders: add new positionId in positionIds array if borrower does not borrow from orderId already

    function _pushNewPositionIdInOrder(
        uint256 _positionId,
        uint256 _orderId
    ) internal orderExists(_orderId) positionExists(_positionId) {
        uint256 row = getPositionIdRowInOrders(_orderId, positions[_positionId].borrower);
        if (row == 2**256 - 1) {
            orders[_orderId].positionIds.push(_positionId);
        }
    }

    // // update orders: add new positionId in positionIds array
    // // check first that borrower does not borrow from _orderTo already
    // function _pushNewPositionIdInOrder(
    //     uint256 _positionId,
    //     uint256 _toOrderId,
    //     uint256 _borrowedAssets
    // ) internal returns (bool success) {
    //     success = false;
    //     address borrower = positions[_positionId].borrower;
    //     uint256 row = getPositionIdRowInOrders(_toOrderId, borrower);
    //     if (row != 2**256 - 1) {
    //         positions[_positionId].borrowedAssets += _borrowedAssets;
    //     } else {
    //         Position memory newPosition = Position({
    //             borrower: borrower,
    //             orderId: _toOrderId,
    //             borrowedAssets: _borrowedAssets
    //         });
    //         orders[_toOrderId].positionIds.push(newPosition);
    //     }
    //     success = true;
    // }

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

    // get all assets deposited by a trader/borrower backing his limit orders, in the quote or base token
    function getUserTotalDeposit(
        address _borrower,
        bool _isQuoteToken
    ) internal view returns (uint256 totalDeposit) {
        uint256[] memory depositIds = users[_borrower].depositIds;
        totalDeposit = 0;
        for (uint256 i = 0; i < depositIds.length; i++) {
            if (orders[depositIds[i]].isBuyOrder == _isQuoteToken) {
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

    function getUserEquity(
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

    getDepositIdsRowInUsers(
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

    // function getPositionIdsRowInOrders(
    //     uint256 _orderId,
    //     uint256 _positionId // in the positionIds array of the order _orderId
    // ) internal view returns (uint256 PositionIdRow) {
    //     PositionIdRow = 2**256 - 1;
    //     uint256[] memory positionIds = orders[_orderId].positionIds;
    //     for (uint256 i = 0; i < positionIds.length; i++) {
    //         if (i == _positionId) {
    //             PositionIdRow = i;
    //             break
    //         }
    //     }
    // }

    // find in positionIds from orders if _borrower borrows from _orderId
    // and, if so, at which row in the positionId array

    function getPositionIdsRowInOrders(
        uint256 _orderId,
        address _borrower
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

    function getPositionIdInPositions(uint256 _OrderId, address _borrower)
    intenal view returns (uint256 positionId) {
        positionId = 2**256 - 1;
        uint256 row = getPositionIdsRowInOrders(_orderId, _borrower);
        if (row != 2**256 - 1) {
            positionId = orders[_orderId].positionIds[row];
        }
    }

    // loopy
    
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
