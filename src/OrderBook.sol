// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

/// @title A borrowable order book for ERC20 tokens
/// @author Pré-vert
/// @notice Allows users to place limit orders on the book, take orders, and borrow assets
/// @dev A money market for the pair base/quote is handled by a single contract
/// which manages both order book operations lending/borrowing operations

// import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IOrderBook} from "./interfaces/IOrderBook.sol";
import {console} from "forge-std/Test.sol";
import "./lib/MathLib.sol";

contract OrderBook is IOrderBook {
    // using Math for uint256;
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
    uint256 orderListRow; // row in buyOrderList or sellOrderList
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

    // uint256 constant ROOT = 1;

    mapping(uint256 orderId => Order) private orders;
    mapping(address user => User) private users;
    mapping(uint256 positionId => Position) private positions;

    // when an order is removed, we need to iterate through orders to reposition the debt
    // gas costs is bounded by:
    // - looping only on relevant orders = same side, with non-borowed and non-collateral assets
    // - setting a maxListSize for the number of orders to be scanned

    uint256[] buyOrderList; // unordered list of buy orders id 
    uint256[] sellOrderList; // unordered list of sell orders id 
    uint256 maxListSize = 10; // maximum number of orders to be scanned when repositioning debt
    uint256 lastOrderId;
    uint256 lastPositionId;

    // mapping(uint256 orderId => uint256) private nextBuyOrder;
    // mapping(uint256 orderId => uint256) private nextSellOrder;
    // uint256 buyOrderListSize;
    // uint256 sellOrderListSize;
 
   
    constructor(address _quoteToken, address _baseToken) {
        quoteToken = IERC20(_quoteToken);
        baseToken = IERC20(_baseToken);
        // nextBuyOrder[ROOT] = ROOT;
        // nextSellOrder[ROOT] = ROOT;
        lastOrderId = 1;
        lastPositionId = 0;
    }

    modifier orderExists(uint256 _orderId) {
        Order memory order = orders[_orderId];
        require(order.quantity != 0 && order.quantity != 0, "Order does not exist");
        _;
    }

    modifier userExists(address _user) {
        require(users[_user].depositIds.length > 0, "User does not exist");
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

        // update orders: add order to orders, output the id of the new order
        uint256 orderListRow = 0;
        uint256[] memory positionIds = new uint256[](0);
        uint256 newOrderId = _addOrderToOrders(
            msg.sender,
            _isBuyOrder,
            _quantity,
            _price,
            positionIds,
            orderListRow
        );

        // Update users: add orderId in depositIds array
        _pushOrderIdInDepositIdsInUsers(newOrderId, msg.sender);

        // Update orderList: add orderId in buyOrderList or sellOrderList, output the row in the list 
        orderListRow = _pushOrderIdInBorrowables(newOrderId);

        // update orders: add orderListRow in orderListRow in orders
        orders[newOrderId].orderListRow = orderListRow;

        _transferTokenFrom(msg.sender, _quantity, _isBuyOrder);
        
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
        onlyMaker(getMaker(_removedOrderId))
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
        _removeOrderFromorderList(_removedOrderId);

        emit RemoveOrder(
            remover,
            repositionedQuantity,
            removedOrder.price,
            removedOrder.isBuyOrder
        );
    }

    /// @notice Let users take limit orders, regardless the orders' assets are borrowed or not
    /// Assets can be partially taken
    /// partial taking liquidates enough borrowing positions to cover the taken quantity
    /// full taking liquidates all borrowing positions and liquidated position are in full
    /// taking of a collateral order triggers the borrower's liquidation for enough assets (TO DO)
    /// @param _takenOrderId id of the order to be taken
    /// @param _takenQuantity quantity of assets taken from the order

    function takeOrder(
        uint256 _takenOrderId,
        uint256 _takenQuantity
    ) 
        external 
        orderExists(_takenOrderId)
        isPositive(_takenQuantity)
    {
        Order memory takenOrder = orders[_takenOrderId];
        require(_takenQuantity <= takenOrder.quantity,
            "takeOrder: Taken quantity exceeds deposit"
        );

        // liquidate enough borrowing positions
        // output the quantity actually displaced, which must be >= taken quantity
        bool liquidate = true;
        uint256 displacedQuantity = _displaceAssets(_takenOrderId, _takenQuantity, liquidate);

        // quantity given by taker in exchange of _takenQuantity
        uint256 exchangedQuantity = takenOrder.isBuyOrder ?
            _takenQuantity / takenOrder.price :
            _takenQuantity * takenOrder.price;

        _checkAllowanceAndBalance(msg.sender, exchangedQuantity, !takenOrder.isBuyOrder);

        // if taking is full, remove:
        // - orderId in depositIds array in users
        // - order from borrowable orderList
        // - order in orders
        // otherwise adjust internal balances
        if (_takenQuantity == takenOrder.quantity) {
            _removeOrderFromDepositIdsInUsers(takenOrder.maker, _takenOrderId);
            _removeOrderFromorderList(_removedOrderId);
            delete orders[_takenOrderId];
        } else {
            takenOrder.quantity -= _takenQuantity;
        }

        // external transfers: if a buy order is taken, the taker pays the quoteToken and receives the baseToken
        _checkAllowanceAndBalance(msg.sender, exchangedQuantity, !takenOrder.isBuyOrder);
        _transferTokenFrom(msg.sender, exchangedQuantity, !takenOrder.isBuyOrder);
        _transferTokenTo(takenOrder.maker, exchangedQuantity, takenOrder.isBuyOrder);
        _transferTokenTo(msg.sender, _takenQuantity, takenOrder.isBuyOrder);

        emit TakeOrder(
            msg.sender,
            takenOrder.maker,
            _takenQuantity,
            takenOrder.price,
            takenOrder.isBuyOrder
        );
    }

    /// @notice Lets users borrow assets from posted orders (creates or increases a borrowing position)
    /// Borrowers need to place orders first on the othe side of the book with enough assets
    /// orders are borrowable if:
    /// - the maker is not a borrower (his assets are not used as collateral)
    /// - the borrower does not demand more assets than available
    /// - the borrower has enough equity (excess collateral) to borrow the assets
    /// @param _borrowedOrderId id of the order which assets are borrowed
    /// @param _borrowedQuantity quantity of assets borrowed from the order

    function borrowOrder(
        uint256 _borrowedOrderId,
        uint256 _borrowedQuantity
    )
        external
        orderExists(_borrowedOrderId)
        isPositive(_borrowedQuantity)
    {
        Order memory borrowedOrder = orders[_borrowedOrderId];

        // only assets which do not serve as collateral are borrowable
        // check if the maker is not a borrower

        require(!isMakerBorrower(getMaker(_borrowedOrderId)),
            "Assets used as collateral are not available for borrowing");

        uint256 availableAssets = borrowedOrder.quantity -
            getTotalAssetsLentByOrder(_borrowedOrderId);
        require(availableAssets >= _borrowedQuantity,
            "Insufficient available assets"
        );

        // userEquity is excess deposits available to collateralize additional debt
        require(getUserEquity(msg.sender, borrowedOrder.isBuyOrder) >= borrowedOrder.quantity,
            "Insufficient equity to borrow assets, deposit more collateral"
        );

        // update users: check if borrower already borrows from order, 
        // if not, add orderId in borrowFromIds array
        addBorrowFromIdsInUsers(msg.sender, _borrowedOrderId);

        // update positions: create new or update existing borrowing position in positions
        // output the id of the new or updated borrowing position
        uint256 positionId = _addPositionToPositions(msg.sender, _borrowedOrderId, _borrowedQuantity);

        // update orders: add new positionId in positionIds array
        _pushNewPositionIdInOrders(positionId, _borrowedOrderId);

        // update borrowable orderList: remove order from list if no more assets available
        if (getTotalAssetsLentByOrder(_borrowedOrderId) == orders[_borrowedOrderId].quantity) {
            _removeOrderFromorderList(_borrowedOrderId);
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
    )
        external
        orderExists(_repaidOrderId) 
        isPositive(_repaidQuantity)
    {
        Orders memory repaidOrder = orders[_repaidOrderId];
        uint256 positionId = getPositionIdInPositions(_repaidOrderId, msg.sender);

        require(positionId != 2**256 - 1 && position[positionId].borrowedAssets > 0,
            "repayBorrowing: No borrowing position found"
        );

        require(_repaidQuantity <= position[positionId].borrowedAssets,
            "repayBorrowing: Repaid quantity exceeds borrowed quantity"
        );

        _checkAllowanceAndBalance(ms.sender, _repaidQuantity, repaidOrder.isBuyOrder);
        
        // update positions: decrease borrowedAssets
        position[positionId].borrowedAssets -= _repaidQuantity;

        // if borrowing is fully repaid, delete position in positions
        removePositionFromPositions(positionId);

        // and delete positionId from positionIds in orders
        removePositionIdFromPositionIdsInOrders(positionId, _repaidOrderId);

        // if user is not a borrower anymore, his own orders become borrowable
        // => include all his orders in the borrowable list

        function includeAllOrdersInOrderList(address _user)
            internal
            userExists(_user)
        {
            for (uint256 i = 0; i < users[_user].depositIds.length; i++) {
                uint256 orderId = users[_user].depositIds[i];
                _pushOrderIdInBorrowables(orderId);
            }
        }

        if (positions[borrowingId].borrowedAssets == 0) {
            if (!isMakerBorrower(msg.sender)) {
                for (uint256 i = 0; i < users[msg.sender].depositIds.length; i++) {
                    uint256 orderId = users[msg.sender].depositIds[i];
                    _pushOrderIdInBorrowables(orderId);
                }
            }
        }

        _transferTokenFrom(ms.sender, _repaidQuantity, repaidOrder.isBuyOrder);

        emit repayLoan(
            msg.sender,
            _repaidOrderId,
            _repaidQuantity,
            repaidOrder.isBuyOrder
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
        _pushNewPositionIdInOrders(positionId, _toOrderId);

        // update users: add toOrderId in borrowFromIds array if doesn't exist alrady
        _addOrderToBorrowFromIdsinUsers(positionId, borrower);
      
        // update users: delete fromOrderId in borrowFromIds array (reposiiton is full)
        _removeOrderIdFromBorrowFromIdsinUsers(getMaker(fromOrderId), fromOrderId);
 
        // update orders: delete positionId from positionIds array of fromOrderId (reposiiton is full)
        _removeOrderIdFromPositionIdsInOrders(fromOrderId, borrower);
  
        // update positions: delete previous position (reposiiton is full)
        delete positions[_fromPositionId];
    }
    
    // displace assets from an order to another or liquidate
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
    ) internal returns (uint256 displacedQuantity)
    {
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
    ) internal orderExists(_fromOrderId)
    {
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
        internal
        userExists(_to)
        isPositive(_quantity)
        returns (bool success)
    {
        if (_isBuyOrder) {
            quoteToken.transfer(_to, _quantity);
        } else {
            baseToken.transfer(_to, _quantity);
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
        uint256[] _positionIds
    ) internal returns (uint256 orderId)
    {
        uint256[] memory borrowingIds; // Empty array
        Order memory newOrder = Order({
            maker: _maker,
            isBuyOrder: _isBuyOrder,
            quantity: _quantity,
            price: _price,
            positionIds: _positionIds
        });
        orders[lastOrderId] = newOrder;
        orderId = lastOrderId;
        lastOrderId++;
    }

    // userExists() checks that _maker has placed at least one order
    // if _orderId is not in depositIds array, push it, otherwise do nothing

    function pushOrderIdInDepositIdsInUsers(
        uint256 _orderId,
        address _maker            
    ) intenal orderIdExists(_orderId) userExists(_maker)
    {
        uint256 row = getDepositIdsRowInUsers(_maker, _orderId);
        if (row == 2**256 - 1) {
            users[_maker].depositIds.push(_orderId);
        }
    }
        
    function _removeOrderIdFromBorrowFromIdsinUsers(
        address _user,
        uint256 _orderId
    )
        internal userExists(_user) orderExists(_orderId)
    {
        uint256 row = getBorrowFromIdsRowInUsers(_user, _orderId);
        if (row != 2**256 - 1) {
            uint256[] borrowFromIds = users[_user].borrowFromIds;
            borrowFromIds[row] = borrowFromIds[borrowFromIds.length - 1];
            borrowFromIds.pop();
        }
    }

    function _removeOrderIdFromPositionIdsInOrders(
        uint256 orderId,
        address borrower) 
    internal userExists(_maker) orderExists(_orderId)
    {
        uint256 row = getPositionIdsRowInOrders(orderId, borrower);
        if (row != 2**256 - 1) {
            uint256[] positionIds = orders[orderId].positionIds;
            positionIds[row] = positionIds[positionIds.length - 1];
            positionIds.pop();
        }
    }

    // update users: check if borrower already borrows from order, 
    // if not, add orderId in borrowFromIds array
    function addBorrowFromIdsInUsers(address borrower, uint256 orderId)
    internal userExists(borrower) orderExists(orderId)
    {
        uint256 row = getBorrowFromIdsRowInUsers(borrower, orderId);
        if (row == 2**256 - 1) {
            users[borrower].borrowFromIds.push(orderId);
        }
    }

    function _removeOrderFromDepositIdsInUsers(address _maker, uint256 _orderId)
        internal userExists(_maker) orderExists(_orderId)
    {
        uint256 row = getDepositIdsRowInUsers(_maker, _orderId);
        if (row != 2**256 - 1) {
            users[_maker].depositIds[row] 
            = users[_maker].depositIds[users[_maker].depositIds.length - 1];
            users[_maker].depositIds.pop();
        }
    }

    // push order id in borrowable orderList, outputs the row in orderlist
    function _pushOrderIdInBorrowables(
        uint256 _orderId
    ) internal orderExists(_orderId) returns (unit256 orderListRow)
    {
        // uint256 row = getOrderIdRowInOrderList(_orderId);
        if (orders[orderId].orderListRow == 2**256 - 1) {
            if (orders[_orderId].isBuyOrder) {
                buyOrderList.push(_orderId);
                orderListRow = buyOrderList.length - 1;
            } else {
                sellOrderList.push(_orderId);
                orderListRow = sellOrderList.length - 1;
            }
        }
    }

    // remove order from the list of borrowable orders
    function _removeOrderFromorderList(uint256 _orderId)
    internal orderExists(_orderId)
    {
        uint256 row = getOrderIdRowInOrderList(_orderId);
        if (row != 2**256 - 1) {
            uint256[] orderList = orders[_orderId].isBuyOrder ? buyOrderList : sellOrderList;
            orderList[row] = orderList[orderList.length - 1];
            if (orders[_orderId].isBuyOrder) {
                buyOrderList.pop();
            } else {
                sellOrderList.pop();
            }
        }
    }

    // update orders: add new positionId in positionIds array
    // check first that borrower does not borrow from _orderTo already
    // returns existing or new position id in positions mapping

    function _addPositionToPositions(
        address _borrower,
        uint256 _orderId,
        uint256 _borrowedQuantity
    ) internal userExists(_maker) orderExists(_orderId) isPositive(_borrowedQuantity)
    returns (uint256 positionId) 
    {
        uint256 positionId = getPositionIdInPositions(_orderId, borrower);
        if (positionId != 2**256 - 1) {
            positions[_positionId].borrowedAssets += _borrowedQuantity;
        } else {
            Position memory newPosition = Position({
                borrower: borrower,
                orderId: _toOrderId,
                borrowedAssets: _borrowedQuantity
            });
            positions[lastPositionId] = newPosition;
            positionId = lastPositionId;
            lastPositionId ++;
        }
    }

    // update orders: add new positionId in positionIds array if borrower does not borrow from orderId already

    function _pushNewPositionIdInOrders(
        uint256 _positionId,
        uint256 _orderId
    ) internal orderExists(_orderId) positionExists(_positionId)
    {
        uint256 row = getPositionIdRowInOrders(_orderId, positions[_positionId].borrower);
        if (row == 2**256 - 1) {
            orders[_orderId].positionIds.push(_positionId);
        }
    }

    function removePositionFromPositions(uint256 _positionId) 
        internal 
        positionExists(_positionId)
    {
        if (positions(_positionId).borrowedAssets == 0) {
            delete positions[_positionId];
        }
    }

    function removePositionIdFromPositionIdsInOrders(
        uint256 _positionId,
        uint256 _orderId) 
        internal
        positionExists(_positionId)
        orderExists(_orderId)
    {
        Position memory position = positions[_positionId];
        if position.borrowedAssets == 0) {
            uint256 row = getPositionIdsRowInOrders(_orderId, position.borrower);
            if (row != 2**256 - 1) {
                orders[_orderId].positionIds[row] 
                = orders[_repaidOrderId].positionIds[orders[_repaidOrderId].positionIds.length - 1];
                orders[_repaidOrderId].positionIds.pop();
            }
        }
    }


    //////////********* View functions *********/////////

    function getQuoteTokenAddress() public view returns (address) {
        return (address(quoteToken));
    }

    function getBaseTokenAddress() public view returns (address) {
        return (address(baseToken));
    }

    // function getBookSize() public view returns (uint256) {
    //     return orders.length;
    // }

    // get the address of the maker of a given order
    function getMaker(
        uint256 _orderId
    ) public view orderExists(_orderId) returns (address) {
        return orders[_orderId].maker;
    }

    // check if the maker is a borrower
    function isMakerBorrower(
        address _maker
    ) internal view userExists(_maker) returns (bool isBorrower) {
        uint256[] memory borrowFromIds = users[_maker].borrowFromIds;
        if (borrowFromIds.length > 0) {
            for (uint256 i = 0; i < borrowFromIds.length; i++) {
                if (orders[depositIds[i]].isBuyOrder == _isQuoteToken) {
                    totalDeposit += orders[depositIds[i]].quantity;
                }
            }
        }
        }
    }

    // check allowance and balance before ERC20 transfer
    
    function _checkAllowanceAndBalance(
        address _user, 
        uint256 _quantity,
        bool _isBuyOrder
    )
        internal view
        userExists(_user)
        isPositive
        returns(bool success)
    {
        success = false;
        if (_isBuyOrder) {
            require(quoteToken.balanceOf(_user) >= _quantity,
                "quote token: Insufficient balance");
            require(quoteToken.allowance(_user, address(this)) >= quantity,
                "quote token: Insufficient allowance");
        } else {
            require(baseToken.balanceOf(_user) >= quantity,
                "base token: Insufficient balance");
            require(baseToken.allowance(_user, address(this)) >= quantity,
                "base token: Insufficient allowance"
            );
        }
        success = true;
    }

    // get all assets deposited by a trader/borrower backing his limit orders, in the quote or base token
    function getUserTotalDeposit(
        address _borrower,
        bool _isQuoteToken
    ) internal view userExists(_borrower) returns (uint256 totalDeposit) {
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
    ) internal view userExists(_borrower) returns (uint256 totalDebt) {
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
    ) internal view userExists(_borrower) returns (uint256 totalNeededCollateral) {
        uint256[] memory borrowedIds = users[_borrower].borrowFromIds;
        totalNeededCollateral = 0;
        for (uint256 i = 0; i < borrowedIds.length; i++) {
            Position memory position = positions[borrowedIds[i]];
            Orders memory order = orders[position.orderId];
            if (order.isBuyOrder == _isQuoteToken) {
                totalNeededCollateral += position.borrowedAssets / order.price;
            } else {
                totalNeededCollateral += position.borrowedAssets * order.price;
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

    // get quantity of assets lent by order
    function getTotalAssetsLentByOrder(
        uint256 _orderId
    ) internal view orderExists(_orderId) returns (uint256 totalLentAssets) {
        uint256[] memory positionIds = orders[_orderId].positionIds;
        uint256 totalLentAssets = 0;
        for (uint256 i = 0; i < positionIds.length; i++) {
            totalLentAssets += positions[positionIds[i]].borrowedAssets;
        }
    }

    // find in users if _maker has made _orderId
    // and, if so, what is its row in the depositIds array

    function getDepositIdsRowInUsers(
        address _maker,
        uint256 _orderId // in the depositIds array of users
    ) internal view userExists(_maker) orderExists(_orderId) returns (uint256 depositIdsRow) {
        depositIdsRow = 2**256 - 1;
        uint256[] memory depositds = users[_maker].depositIds;
        for (uint256 i = 0; i < depositIds.length; i++) {
            if (orders[depositIds[i]] == _orderId) {
                depositIdsRow = i;
                break;
            }
        }
    }
    
    // check if user borrows from order
    // if so, returns the row in the borrowFromIds array

    getBorrowFromIdsRowInUsers(
        address _borrower,
        uint256 _orderId // in the borrowFromIds array of users
    ) internal view userExists(_borrower) orderExists(_orderId) 
    returns (uint256 borrowFromIdsRow) {
        borrowFromIdsRow = 2**256 - 1;
        uint256[] memory borrowFromIds = users[_borrower].borrowFromIds;
        for (uint256 i = 0; i < borrowFromIds.length; i++) {
            if (orders[borrowFromIds[i]] == _orderId) {
                borrowFromIdsRow = i;
                break;
            }
        }
    }

    // find in positionIds from orders if _borrower borrows from _orderId
    // and, if so, at which row in the positionId array

    function getPositionIdsRowInOrders(
        uint256 _orderId,
        address _borrower
    ) internal view userExists(_borrower) orderExists(_orderId) 
    returns (uint256 positionIdRow) {
        PositionIdRow = 2**256 - 1;
        uint256[] memory positionIds = orders[_orderId].positionIds;
        for (uint256 i = 0; i < positionIds.length; i++) {
            if (positions[positionIds[i]].borrower == _borrower) {
                PositionIdRow = i;
                break
            }
        }
    }

    function getPositionIdInPositions(uint256 _orderId, address _borrower)
    intenal view userExists(_borrower) orderExists(_orderId) 
    returns (uint256 positionId) {
        positionId = 2**256 - 1;
        uint256 row = getPositionIdsRowInOrders(_orderId, _borrower);
        if (row != 2**256 - 1) {
            positionId = orders[_orderId].positionIds[row];
        }
    }

    // 
    
    function getOrderIdRowInOrderList(
        uint256 _orderId
    ) internal view orderExists(_orderId)  returns (uint256 orderIdRow) {
        orderIdRow = 2**256 - 1;
        bool isBuyOrder = orders[_orderId].isBuyOrder;
        uint256 orderId = isBuyOrder ? buyOrderList[] : sellOrderList;
        for (uint256 i = 0; i < orderList.length; i++) {
            if (orderList[i] == _orderId) {
                orderIdRow = i;
                break
            }
        }
    }
}
