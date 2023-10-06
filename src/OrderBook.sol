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

// import "./lib/MathLib.sol";

contract OrderBook is IOrderBook {
    // using Math for uint256;
    // using MathLib for uint256;
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

    uint256 constant ABSENT = 2 ** 256 - 1; // id for non existing order, position, user, etc.

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
    uint256 lastOrderId = 0; // id of the last order in orders
    uint256 lastPositionId = 0; // id of the last position in positions

    constructor(address _quoteToken, address _baseToken) {
        quoteToken = IERC20(_quoteToken);
        baseToken = IERC20(_baseToken);
    }

    modifier userExists(address _user) {
        require(users[_user].depositIds.length > 0, "User does not exist");
        _;
    }

    modifier orderExists(uint256 _orderId) {
        require(orders[_orderId].maker != address(0), "Order does not exist");
        _;
    }

    modifier positionExists(uint256 _positionId) {
        require(positions[_positionId].borrower != address(0),
            "Borrowing position does not exist");
        _;
    }

    modifier isPositive(uint256 _var) {
        require(_var > 0, "Must be positive");
        _;
    }

    modifier onlyMaker(address maker) {
        require(maker == msg.sender,
            "removeOrder: Only the maker can remove the order");
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
    )
        external
        isPositive(_quantity)
        isPositive(_price)
    {
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
        orderListRow = _pushOrderIdInOrderList(newOrderId);

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
    /// @param _quantityToRemove desired quantity of assets removed

    function removeOrder(
        uint256 _removedOrderId,
        uint256 _quantityToRemove
    )
        external
        orderExists(_removedOrderId)
        isPositive(_quantityToRemove)
        onlyMaker(getMaker(_removedOrderId))
    {
        Order memory removedOrder = orders[_removedOrderId];
        address remover = removedOrder.maker;

        require(
            removedOrder.quantity >= _quantityToRemove,
            "removeOrder: Removed quantity exceeds deposit"
        );

        // Remaining total deposits must be enough to secure existing borrowing positions
        require(
            _quantityToRemove <=  getUserExcessCollateral(remover, removedOrder.isBuyOrder),
            "removeOrder: Close your borrowing positions before removing your orders"
        );

        // remove borrowing positions eqyivalent to the removed quantity
        // output the quantity actually repositioned
        bool afterRemoving = false;
        uint256 repositionedQuantity = _displaceAssets(
            _removedOrderId,
            _quantityToRemove,
            afterRemoving
        );

        // removal is allowed for the quantity actually relocated
        uint256 transferredQuantity = min(repositionedQuantity, _quantityToRemove);

        // remove orderId in depositIds array in users (if fully removed)
        _removeOrderIdFromDepositIdsInUsers(remover, _removedOrderId);

        // regardless removal is partial or full, withdraw order from the list of borrowable orders
        _removeOrderIdFromOrderList(_removedOrderId);

        if (transferredQuantity > 0) {
            _transferTokenTo(
                msg.sender,
                transferredQuantity,
                removedOrder.isBuyOrder
            );
        }

        // reduce quantity in order, delete order if emptied
        _reduceOrderByQuantity(_removedOrderId, transferredQuantity);

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
        require(
            _takenQuantity <= takenOrder.quantity,
            "takeOrder: Taken quantity exceeds deposit"
        );

        // liquidate enough borrowing positions
        // output the quantity actually displaced, whtakenOrderich must be >= taken quantity
        bool afterRemoving = true;
        uint256 displacedQuantity = _displaceAssets(
            _takenOrderId,
            _takenQuantity,
            afterRemoving
        );

        // quantity given by taker in exchange of _takenQuantity

        uint256 exchangedQuantity = _converts(
            _takenQuantity,
            takenOrder.price,
            takenOrder.isBuyOrder
        );

        _checkAllowanceAndBalance(
            msg.sender,
            exchangedQuantity,
            !takenOrder.isBuyOrder
        );

        // remove orderId in depositIds array in users (if taking is full)
        _removeOrderIdFromDepositIdsInUsers(takenOrder.maker, _takenOrderId);

        // remove order from borrowable orderList (if taking is full)
        _removeOrderIdFromOrderList(_takenOrderId);

        // remove order in orders if taking is full, otherwise adjust internal balances
        _reduceOrderByQuantity(_takenOrderId, _takenQuantity);

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

    /// @notice Lets users borrow assets from orders (creates or increases a borrowing position)
    /// Borrowers need to place orders first on the other side of the book with enough assets
    /// orders are borrowable if:
    /// - the maker is not a borrower (his assets are not used as collateral)
    /// - the borrower does not demand more assets than available
    /// - the borrower has enough excess collateral to borrow the assets
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
        // For Bob to borrow USDC (quote token) from Alice's buy order, one must check that
        // Alice doesn't borrow ETH (base token) collateralized with her buy order

        bool inQuoteToken = !orders[_borrowedOrderId].isBuyOrder;
        require(!isUserBorrower(getMaker(_borrowedOrderId), inQuoteToken),
            "Assets used as collateral are not available for borrowing"
        );

        uint256 availableAssets = borrowedOrder.quantity -
            getTotalAssetsLentByOrder(_borrowedOrderId);
        require(
            availableAssets >= _borrowedQuantity,
            "Insufficient available assets"
        );

        // note enough deposits available to collateralize additional debt
        require(
            getUserExcessCollateral(msg.sender, borrowedOrder.isBuyOrder) >=
                borrowedOrder.quantity,
            "Insufficient collateral to borrow assets, deposit more collateral"
        );

        // update users: check if borrower already borrows from order,
        // if not, add orderId in borrowFromIds array
        _addOrderIdInBorrowFromIdsInUsers(msg.sender, _borrowedOrderId);

        // update positions: create new or update existing borrowing position in positions
        // output the id of the new or updated borrowing position
        uint256 positionId = _addPositionToPositions(
            msg.sender,
            _borrowedOrderId,
            _borrowedQuantity
        );

        // update orders: add new positionId in positionIds array
        _pushNewPositionIdInOrders(positionId, _borrowedOrderId);

        // update borrowable orderList: remove order from list if no more assets available
        if (
            getTotalAssetsLentByOrder(_borrowedOrderId) ==
            orders[_borrowedOrderId].quantity
        ) {
            _removeOrderIdFromOrderList(_borrowedOrderId);
        }

        _transferTokenTo(
            msg.sender,
            _borrowedQuantity,
            borrowedOrder.isBuyOrder
        );

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
    ) external orderExists(_repaidOrderId) isPositive(_repaidQuantity)
    {
        Order memory repaidOrder = orders[_repaidOrderId];
        uint256 positionId = getPositionIdInPositions(
            _repaidOrderId,
            msg.sender
        );

        require(
            positionId != ABSENT && positions[positionId].borrowedAssets > 0,
            "repayBorrowing: No borrowing position found"
        );

        require(
            _repaidQuantity <= positions[positionId].borrowedAssets,
            "repayBorrowing: Repaid quantity exceeds borrowed quantity"
        );

        _checkAllowanceAndBalance(
            msg.sender,
            _repaidQuantity,
            repaidOrder.isBuyOrder
        );

        // update positions: decrease borrowedAssets
        positions[positionId].borrowedAssets -= _repaidQuantity;

        // if borrowing is fully repaid, delete position in positions
        _deletePositionFromPositions(positionId);

        // and remove positionId from positionIds in orders
        _removePositionIdFromPositionIdsInOrders(positionId, _repaidOrderId);

        // and remove repaid order id from borrowFromIds in users
        _removeOrderIdFromBorrowFromIdsInUsers(msg.sender, _repaidOrderId);

        // if user is not a borrower anymore, his own orders become borrowable
        // => include all his orders in the borrowable list
        // Bob repays his debt in USDC from Alice's buy order
        // His own sell orders become borrowable
        if (positions[positionId].borrowedAssets == 0) {
            bool buyOrders = !repaidOrder.isBuyOrder;
            _includeOrdersInOrderList(msg.sender, buyOrders);
        }

        _transferTokenFrom(msg.sender, _repaidQuantity, repaidOrder.isBuyOrder);

        emit repayLoan(
            msg.sender,
            _repaidOrderId,
            _repaidQuantity,
            repaidOrder.isBuyOrder
        );
    }

    ///////******* Internal functions *******///////

    // displace assets from an order to another or liquidate
    // called by removeOrder() if _afterRemoving (never liquidate) and takeOrder() if !_afterRemoving (always liquidate)
    // if removal, relocate enough assets or forbid removal of non-relocated assets
    // positions are fully relocated to one order (1 to 1), or locked
    // => total quantity actually removed can be greater or lower than the quantity to be removed
    // if taking is partial, liquidate enough borrowing positions (randomly)
    // outputs the quantity actually relocated (removal) or liquidated (taking)
    // doesn't perform the final transfers (removing or taking)

    function _displaceAssets(
        uint256 _fromOrderId, // order from which borrowing positions must be cleared
        uint256 _quantityToDisplace, // quantity removed or taken
        bool _afterRemoving // true if removing, false if taking
    ) internal returns (uint256 displacedQuantity)
    {
        displacedQuantity = 0;
        uint256[] memory positionIds = orders[_fromOrderId].positionIds;

        // iterate on the borrowing ids of the order to be removed
        for (uint256 i = 0; i < positionIds.length; i++) {
            Position memory fromPosition = positions[positionIds[i]];
            if (_afterRemoving) {
                // try to reposition borrowing position in full
                uint256 toOrderId = _findNewPosition(positionIds[i]);
                // if a new order is found, reposition the borrowing position
                if (toOrderId != _fromOrderId) {
                    _reposition(positionIds[i], toOrderId);
                    // update displacedQuantity
                    displacedQuantity += fromPosition.borrowedAssets;
                }
            } else {
                // liquidate borrowing position
                _liquidate(positionIds[i]);
                displacedQuantity += fromPosition.borrowedAssets;
            }
            // if enough assets are displaced, removal or taking is completed
            if (displacedQuantity >= _quantityToDisplace) {
                break;
            }
        }
    }

    // relocates borrowing position to new order, selected by _findNewPosition()
    // update all internal balances: orders, users, positions and orderList

    function _reposition(
        uint256 _fromPositionId, // position id to be removed
        uint256 _toOrderId // order id to which the borrowing is relocated
    )
        internal
        positionExists(_fromPositionId)
        orderExists(_toOrderId)
    {
        address borrower = positions[_fromPositionId].borrower;
        uint256 fromOrderId = positions[_fromPositionId].orderId;

        // update positions: create a new or update existing borrowing position in positions
        // output the position id of the new or updated borrowing position
        uint256 positionId = _addPositionToPositions(
            borrower,
            _toOrderId,
            positions[_fromPositionId].borrowedAssets
        );

        // update users: remove _toOrderId in borrowFromIds array (reposiiton is full)
        _removeOrderIdFromBorrowFromIdsInUsers(borrower, _toOrderId);

        // update users: add _toOrderId in borrowFromIds array it if doesn't already exist
        _addOrderIdInBorrowFromIdsInUsers(borrower, _toOrderId);

        // update orders: remove position id from positionIds array (reposiiton is full)
        _removeOrderIdFromPositionIdsInOrders(borrower, fromOrderId);

        // update orders: push new position id in positionIds array
        _pushNewPositionIdInOrders(positionId, _toOrderId);

        // update positions: delete previous position (reposiiton is full)
        _deletePositionFromPositions(_fromPositionId);
    }

    // liquidate a position: seize collateral and write off debt for the same amount
    // liquidation is always full, i.e. borrower's debt is fully written off
    // as multiple orders by the same borrower may collateralize the liquidated position:
    //  - iterate on collateral orders made by borrower in the opposite currency
    //  - seize collateral orders as they come, stops when borrower's debt is fully written off
    //  - change internal balances
    // doesn't execute final external transfer of assets

    function _liquidate(
        uint256 _positionId
    )
        internal
        positionExists(_positionId)
    {
        Position memory position = positions[_positionId]; // position to be liquidated
        uint256 takenOrderId = position.orderId;
        // collateral to seize given borrowed quantity:
        uint256 collateralToSeize = _converts(
            position.borrowedAssets,
            orders[takenOrderId].price,
            orders[takenOrderId].isBuyOrder
        );
        // order id list of collateral orders to seize:
        uint256[] memory depositIds = users[position.borrower].depositIds;
        for (uint256 i = 0; i < depositIds.length; i++) {
            // order id from which assets are seized:
            uint256 id = depositIds[i];
            if (collateralToSeize > orders[id].quantity) {
                // borrower's order is fully seized
                collateralToSeize -= orders[id].quantity;
                // update users: remove seized order id from depositIds array
                _removeOrderIdFromDepositIdsInUsers(position.borrower, id);
                // update users: remove taken order id in borrowFromIds array
                _removeOrderIdFromBorrowFromIdsInUsers(position.borrower, takenOrderId);
                // update orders: remove position id from positionIds array
                _removeOrderIdFromPositionIdsInOrders(position.borrower, id);
                // update orders: delete emptied order
                _reduceOrderByQuantity(id, orders[id].quantity);
            } else {
                // enough collateral assets are seized before borrower's order is fully seized
                collateralToSeize = 0;
                orders[id].quantity -= collateralToSeize;
                break;
            }
        }
        require(collateralToSeize == 0, "Some collateral couldn't be seized");
    }

    // tranfer ERC20 from contract to user/taker/borrower
    function _transferTokenTo(
        address _to,
        uint256 _quantity,
        bool _isBuyOrder
    ) internal isPositive(_quantity) returns (bool success)
    {
        if (_isBuyOrder) {
            quoteToken.transfer(_to, _quantity);
        } else {
            baseToken.transfer(_to, _quantity);
        }
        success = true;
    }

    // transfer ERC20 from user/taker/repayBorrower to contract
    function _transferTokenFrom(
        address _from,
        uint256 _quantity,
        bool _isBuyOrder
    ) internal isPositive(_quantity) returns (bool success)
    {
        if (_isBuyOrder) {
            quoteToken.transferFrom(_from, address(this), _quantity);
        } else {
            baseToken.transferFrom(_from, address(this), _quantity);
        }
        success = true;
    }

    // returns id of the new order
    function _addOrderToOrders(
        address _maker,
        bool _isBuyOrder,
        uint256 _quantity,
        uint256 _price,
        uint256[] memory _positionIds,
        uint256 _orderListRow
    )
        internal 
        returns (uint256 orderId)
    {
        Order memory newOrder = Order({
            maker: _maker,
            isBuyOrder: _isBuyOrder,
            quantity: _quantity,
            price: _price,
            positionIds: _positionIds,
            orderListRow: _orderListRow
        });
        orders[lastOrderId] = newOrder;
        orderId = lastOrderId;
        lastOrderId++;
    }

    // if order id is not in depositIds array, push it, otherwise do nothing
    function _pushOrderIdInDepositIdsInUsers(
        uint256 _orderId,
        address _maker
    )
        internal
        orderExists(_orderId) // checks that _maker has placed at least one order
        userExists(_maker)
    {
        uint256 row = getDepositIdsRowInUsers(_maker, _orderId);
        if (row == ABSENT) {
            users[_maker].depositIds.push(_orderId);
        }
    }

    function _removeOrderIdFromBorrowFromIdsInUsers(
        address _user,
        uint256 _orderId
    )
        internal
        userExists(_user)
        orderExists(_orderId)
    {
        uint256 row = getBorrowFromIdsRowInUsers(_user, _orderId);
        if (row != ABSENT) {
            users[_user].borrowFromIds[row] = 
            users[_user].borrowFromIds[users[_user].borrowFromIds.length - 1];
            users[_user].borrowFromIds.pop();
        }
    }

    function _removeOrderIdFromPositionIdsInOrders(
        address _borrower,
        uint256 _orderId
    ) internal userExists(_borrower) orderExists(_orderId)
    {
        uint256 row = getPositionIdsRowInOrders(_orderId, _borrower);
        if (row != ABSENT) {
            orders[_orderId].positionIds[row]
            = orders[_orderId].positionIds[orders[_orderId].positionIds.length - 1];
            orders[_orderId].positionIds.pop();
        }
    }

    // update users: check if borrower already borrows from order,
    // if not, add order id in borrowFromIds array

    function _addOrderIdInBorrowFromIdsInUsers(
        address _borrower,
        uint256 _orderId
    )
        internal
        userExists(_borrower)
        orderExists(_orderId)
    {
        uint256 row = getBorrowFromIdsRowInUsers(_borrower, _orderId);
        if (row == ABSENT) {
            users[_borrower].borrowFromIds.push(_orderId);
        }
    }

    function _removeOrderIdFromDepositIdsInUsers(
        address _user,
        uint256 _orderId
    ) internal userExists(_user) orderExists(_orderId) {
        if (orders[_orderId].quantity == 0) {
            uint256 row = getDepositIdsRowInUsers(_user, _orderId);
            if (row != ABSENT) {
                users[_user].depositIds[row] = users[_user].depositIds[
                    users[_user].depositIds.length - 1
                ];
                users[_user].depositIds.pop();
            }
        }
    }

    // push order id in borrowable orderList, outputs the row in orderlist
    function _pushOrderIdInOrderList(
        uint256 _orderId
    ) internal orderExists(_orderId) returns (uint256 orderListRow) {
        orderListRow == ABSENT;
        uint256 row = getOrderIdRowInOrderList(_orderId);
        if (row == ABSENT) {
            if (orders[_orderId].isBuyOrder) {
                buyOrderList.push(_orderId);
                orderListRow = buyOrderList.length - 1;
            } else {
                sellOrderList.push(_orderId);
                orderListRow = sellOrderList.length - 1;
            }
        }
    }

    // remove order id from borrowable orderList

    function _removeOrderIdFromOrderList(
        uint256 _orderId
    )
        internal
        orderExists(_orderId)
    {
        if (orders[_orderId].quantity == 0) {
            uint256 row = getOrderIdRowInOrderList(_orderId);
            if (row != ABSENT) {
                uint256[] memory orderList = orders[_orderId].isBuyOrder
                    ? buyOrderList
                    : sellOrderList;
                orderList[row] = orderList[orderList.length - 1];
                if (orders[_orderId].isBuyOrder) {
                    buyOrderList.pop();
                } else {
                    sellOrderList.pop();
                }
            }
        }
    }

    // update positions: add new position in positions mapping
    // check first that position doesn't exist already
    // returns existing or new position id in positions mapping

    function _addPositionToPositions(
        address _borrower,
        uint256 _orderId,
        uint256 _borrowedQuantity
    )
        internal
        userExists(_borrower)
        orderExists(_orderId)
        isPositive(_borrowedQuantity)
        returns (uint256 positionId)
    {
        positionId = getPositionIdInPositions(_orderId, _borrower);
        if (positionId != ABSENT) {
            positions[positionId].borrowedAssets += _borrowedQuantity;
        } else {
            Position memory newPosition = Position({
                borrower: _borrower,
                orderId: _orderId,
                borrowedAssets: _borrowedQuantity
            });
            positions[lastPositionId] = newPosition;
            positionId = lastPositionId;
            lastPositionId++;
        }
    }

    function _deletePositionFromPositions(
        uint256 _positionId
    )
        internal
        positionExists(_positionId)
    {
        if (positions[_positionId].borrowedAssets == 0) {
            delete positions[_positionId];
        }
    }

    // update orders: add new position id in positionIds array
    // check first that borrower does not borrow from order already

    function _pushNewPositionIdInOrders(
        uint256 _positionId,
        uint256 _orderId
    )
        internal
        orderExists(_orderId)
        positionExists(_positionId)
    {
        uint256 row = getPositionIdsRowInOrders(
            _orderId,
            positions[_positionId].borrower
        );
        if (row == ABSENT) {
            orders[_orderId].positionIds.push(_positionId);
        }
    }

    function _removePositionIdFromPositionIdsInOrders(
        uint256 _positionId,
        uint256 _orderId
    )
        internal
        positionExists(_positionId)
        orderExists(_orderId)
    {
        Position memory position = positions[_positionId];
        if (position.borrowedAssets == 0) {
            uint256 row = getPositionIdsRowInOrders(
                _orderId,
                position.borrower
            );
            if (row != ABSENT) {
                orders[_orderId].positionIds[row]
                = orders[_orderId].positionIds[orders[_orderId].positionIds.length - 1];
                orders[_orderId].positionIds.pop();
            }
        }
    }

    // include **all** orders of users in the borrowable list
    // check before that user is not a borrower anymore
    // if user doesn't borrow quoteToken anymore, his sell orders become borrowable

    function _includeOrdersInOrderList(
        address _user,
        bool _buyOrders // if true, include buy orders, otherwise include sell orders
    )
        internal
        userExists(_user)
    {
        // to include user's buy orders, check if he doesn't borrow quote token
        // if Bob borrows quote tokens from buy orders, his sell orders are not borrowable
        bool inQuoteToken = !_buyOrders;
        if (!isUserBorrower(_user, inQuoteToken)) {
            uint256[] memory depositIds = users[msg.sender].depositIds;
            for (uint256 i = 0; i < depositIds.length; i++) {
                if (orders[depositIds[i]].isBuyOrder == !_buyOrders) {
                    _pushOrderIdInOrderList(depositIds[i]);
                }
            }
        }
    }

    // reduce quantity offered in order, delete order if emptied

    function _reduceOrderByQuantity(
        uint256 _orderId,
        uint256 _quantity
    )
        internal
        orderExists(_orderId)
    {
        if (_quantity < orders[_orderId].quantity) {
            orders[_orderId].quantity -= _quantity;
        } else {
            delete orders[_orderId];
        }
    }

    //////////********* View functions *********/////////

    function getQuoteTokenAddress() public view returns (address)
    {
        return (address(quoteToken));
    }

    function getBaseTokenAddress() public view returns (address) {
        return (address(baseToken));
    }

    // get address of maker based on order
    function getMaker(
        uint256 _orderId
    )
        public view
        orderExists(_orderId)
        returns (address)
    {
        return orders[_orderId].maker;
    }

    // check if user is a borrower of quote or base token
    // a user who borrows from buy oders borrows quote token

    function isUserBorrower(
        address _user,
        bool _inQuoteToken
    ) 
        public view
        userExists(_user)
        returns (bool isBorrower)
    {
        isBorrower = false;
        uint256[] memory borrowFromIds = users[_user].borrowFromIds;
        for (uint256 i = 0; i < borrowFromIds.length; i++) {
            Order memory borrowedOrder = orders[borrowFromIds[i]];
            if (
                borrowedOrder.isBuyOrder == _inQuoteToken &&
                borrowedOrder.quantity > 0
            ) {
                isBorrower = true;
                break;
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
        isPositive(_quantity)
        returns (bool success)
    {
        success = false;
        if (_isBuyOrder) {
            require(quoteToken.balanceOf(_user) >= _quantity,
                "quote token: Insufficient balance");
            require(quoteToken.allowance(_user, address(this)) >= _quantity,
                "quote token: Insufficient allowance");
        } else {
            require(baseToken.balanceOf(_user) >= _quantity,
                "base token: Insufficient balance");
            require(baseToken.allowance(_user, address(this)) >= _quantity,
                "base token: Insufficient allowance");
        }
        success = true;
    }

    // sum all assets deposited by user in the quote or base token

    function getUserTotalDeposit(
        address _borrower,
        bool _isQuoteToken
    )
        internal view
        userExists(_borrower)
        returns (uint256 totalDeposit)
    {
        uint256[] memory depositIds = users[_borrower].depositIds;
        totalDeposit = 0;
        for (uint256 i = 0; i < depositIds.length; i++) {
            if (orders[depositIds[i]].isBuyOrder == _isQuoteToken) {
                totalDeposit += orders[depositIds[i]].quantity;
            }
        }
    }

    // in case of order removal, select new order if its price is closest to target price
    // and if borrower has enough excess collateral to borrow the assets
    // outputs previous or new best price

    function _evaluateNewOrder(
        uint256 targetPrice, // ideal price (price of removed order)
        uint256 closestPrice, // best price so far
        uint256 newPrice, // price of next order in order list
        address borrower, // borrower of displaced order
        uint256 borrowedQuantity, // quantity of assets borrowed
        bool isBuyOrder // type of removed order (buy or sell)
    )
        internal view
        returns (uint256 bestPrice)
    {
        bestPrice = closestPrice;
        if (
            closestPrice == 0 ||
            distance(newPrice, targetPrice) < distance(closestPrice, targetPrice)
        ) {
            bool moreCollateralNeeded = isBuyOrder
                ? newPrice < targetPrice
                : newPrice >= targetPrice;
            if (moreCollateralNeeded) {
                // if removed order is sell order, borrower's colateral is in quote token and vice versa
                bool inQuoteToken = !isBuyOrder;
                uint256 neededExcessCollateral = 
                    _converts(borrowedQuantity, newPrice, inQuoteToken) -
                    _converts(borrowedQuantity, targetPrice, inQuoteToken);

                if (
                    getUserExcessCollateral(borrower, inQuoteToken) >
                    neededExcessCollateral
                ) {
                    bestPrice = newPrice;
                }
            } else {
                bestPrice = newPrice;
            }
        }
    }

    // following removeOrder(), screen orders to find one borrowable, which:
    // has the same type (buy or sell) as borrowedOrder, but is not borrowedOrder
    // has available assets at least equal to the borrowed quantity to displace
    // has the closest price to the one of borrowedOrder

    function _findNewPosition(
        uint256 _positionId
    )
        internal view
        positionExists(_positionId)
        returns (uint256 bestOrderId)
    {
        Position memory position = positions[_positionId];
        Order memory borrowedOrder = orders[position.orderId];
        bool isBuyOrder = borrowedOrder.isBuyOrder;
        uint256[] memory orderList = isBuyOrder ? buyOrderList : sellOrderList;
        uint256 maxIterations = min(maxListSize / borrowedOrder.positionIds.length, orderList.length);
        uint256 bestPrice = 0;
        bestOrderId = ABSENT;

        for (uint256 i = 0; i < maxIterations; i++) {
            uint256 j = orderList[i];
            if (
                j != position.orderId &&
                (orders[j].quantity - getTotalAssetsLentByOrder(j) >=
                    position.borrowedAssets)
            ) {
                uint256 newPrice = _evaluateNewOrder(
                    borrowedOrder.price,
                    bestPrice,
                    orders[j].price,
                    position.borrower,
                    position.borrowedAssets,
                    isBuyOrder
                );
                if (newPrice != bestPrice) {
                    bestPrice = newPrice;
                    bestOrderId = j;
                }
            }
        }
    }
    
    // get borrower's total Debt in the quote or base token
    // to be corrected (orderId, not positionId)
    function getBorrowerTotalDebt(
        address _borrower,
        bool _inQuoteToken
    )
        internal view
        userExists(_borrower)
        returns (uint256 totalDebt)
    {
        uint256[] memory borrowFromIds = users[_borrower].borrowFromIds;
        totalDebt = 0;
        for (uint256 i = 0; i < borrowFromIds.length; i++) {
            uint256 row = getPositionIdsRowInOrders(borrowFromIds[i], _borrower);
            if (orders[borrowFromIds[i]].isBuyOrder == _inQuoteToken) {
                totalDebt += positions[row].borrowedAssets;
            }
        }
    }

    // get borrower's total collateral needed to secure his debt in the quote or base token
    // if needed collateral is in quote token, the borrowed order is a sell order
    // Ex: Alice deposits 3 ETH to sell at 2100; Bob borrows 2 ETH and needs 2*2100 = 4200 USDC as collateral

    function getBorrowerNeededCollateral(
        address _borrower,
        bool _inQuoteToken
    )
        internal
        view
        userExists(_borrower)
        returns (uint256 totalNeededCollateral)
    {
        uint256[] memory borrowedIds = users[_borrower].borrowFromIds;
        totalNeededCollateral = 0;
        for (uint256 i = 0; i < borrowedIds.length; i++) {
            Position memory position = positions[borrowedIds[i]];
            Order memory order = orders[position.orderId];
            if (order.isBuyOrder != _inQuoteToken) {
                uint256 collateral = _converts(
                    position.borrowedAssets,
                    order.price,
                    order.isBuyOrder
                );
                totalNeededCollateral += collateral;
            }
        }
    }

    function getUserExcessCollateral(
        address _user,
        bool _isQuoteToken
    )
        internal view
        userExists(_user)
        returns (uint256 excessCollateral) {
        excessCollateral =
            getUserTotalDeposit(_user, _isQuoteToken) -
            getBorrowerNeededCollateral(_user, _isQuoteToken);
    }

    // get quantity of assets lent by order
    function getTotalAssetsLentByOrder(
        uint256 _orderId
    )
        internal view
        orderExists(_orderId)
        returns (uint256 totalLentAssets)
    {
        uint256[] memory positionIds = orders[_orderId].positionIds;
        totalLentAssets = 0;
        for (uint256 i = 0; i < positionIds.length; i++) {
            totalLentAssets += positions[positionIds[i]].borrowedAssets;
        }
    }

    // find if user posted order id
    // if so, outputs its row in depositIds array

    function getDepositIdsRowInUsers(
        address _user,
        uint256 _orderId // in the depositIds array of users
    )
        internal
        view
        userExists(_user)
        orderExists(_orderId)
        returns (uint256 depositIdsRow)
    {
        depositIdsRow = ABSENT;
        uint256[] memory depositIds = users[_user].depositIds;
        for (uint256 i = 0; i < depositIds.length; i++) {
            if (depositIds[i] == _orderId) {
                depositIdsRow = i;
                break;
            }
        }
    }

    // check if user borrows from order
    // if so, returns row in borrowFromIds array

    function getBorrowFromIdsRowInUsers(
        address _borrower,
        uint256 _orderId // in the borrowFromIds array of users
    )
        internal
        view
        userExists(_borrower)
        orderExists(_orderId)
        returns (uint256 borrowFromIdsRow)
    {
        borrowFromIdsRow = ABSENT;
        uint256[] memory borrowFromIds = users[_borrower].borrowFromIds;
        for (uint256 i = 0; i < borrowFromIds.length; i++) {
            if (borrowFromIds[i] == _orderId) {
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
    )
        internal
        view
        userExists(_borrower)
        orderExists(_orderId)
        returns (uint256 positionIdRow)
    {
        positionIdRow = ABSENT;
        uint256[] memory positionIds = orders[_orderId].positionIds;
        for (uint256 i = 0; i < positionIds.length; i++) {
            if (positions[positionIds[i]].borrower == _borrower) {
                positionIdRow = i;
                break;
            }
        }
    }

    function getPositionIdInPositions(
        uint256 _orderId,
        address _borrower
    )
        internal
        view
        userExists(_borrower)
        orderExists(_orderId)
        returns (uint256 positionId)
    {
        uint256 row = getPositionIdsRowInOrders(_orderId, _borrower);
        if (row != ABSENT) {
            positionId = orders[_orderId].positionIds[row];
        } else {
            positionId = ABSENT;
        }
    }

    function getOrderIdRowInOrderList(
        uint256 _orderId
    )
        internal view
        orderExists(_orderId)
        returns (uint256 orderIdRow)
    {
        orderIdRow = ABSENT;
        uint256[] memory orderList = orders[_orderId].isBuyOrder ?
            buyOrderList : sellOrderList;
        for (uint256 i = 0; i < orderList.length; i++) {
            if (orderList[i] == _orderId) {
                orderIdRow = i;
                break;
            }
        }
    }

    //////////********* Pure functions *********/////////

    function _converts(
        uint256 _quantity,
        uint256 _price,
        bool _isBuyOrder
    )
        internal pure
        returns (uint256 convertedQuantity)
    {
        convertedQuantity = _isBuyOrder
            ? _quantity / _price
            : _quantity * _price;
    }

    function min(
        uint256 _a,
        uint256 _b
    )
        public pure
    returns (uint256 __min)
    {
        __min = _a < _b ? _a : _b;
    }
        
    function distance(
        uint256 _a,
        uint256 _b
    ) 
        public pure
        returns (uint256 dif)
    {
        dif = _a >= _b ? _a - _b : _b - _a;
    }
}
