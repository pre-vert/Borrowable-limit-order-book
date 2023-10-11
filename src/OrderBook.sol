// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

/// @title A lending order book for ERC20 tokens
/// @author Pré-vert
/// @notice Allows users to place limit orders on the book, take orders, and borrow assets
/// @dev A money market for the pair base/quote is handled by a single contract
/// which manages both order book operations lending/borrowing operations

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IOrderBook} from "./interfaces/IOrderBook.sol";
import {console} from "forge-std/Test.sol";

contract OrderBook is IOrderBook {

    IERC20 private quoteToken;
    IERC20 private baseToken;

    /// @notice provide core public functions (place, increase deposit, remove, take, borrow, repay),
    /// internal functions (liquidate) and view functions
    /// @dev mapping orders stores orders in a struct Order
    /// mapping users stores users (makers and borrowers) in a struct User
    /// mapping positions links orders and borrowers ina P2P fashion and stores borrowing positions in a struct Position

    struct Order {
        address maker; // address of the maker
        bool isBuyOrder; // true for buy orders, false for sell orders
        uint256 quantity; // assets deposited (quoteToken for buy orders, baseToken for sell orders)
        uint256 price; // price of the order
        uint256[] positionIds; // stores positions id in mapping positions who borrow from order
    }

    struct User {
        uint256[] depositIds; // stores orders id in mapping orders in which borrower deposits
        uint256[] borrowFromIds; // stores orders id in mapping orders from which borrower borrows
    }

    struct Position {
        address borrower; // address of the borrower
        uint256 orderId; // stores orders id in mapping orders, from which assets are borrowed
        uint256 borrowedAssets; // quantity of assets borrowed (quoteToken for buy orders, baseToken for sell orders)
    }

    uint256 constant ABSENT = 2 ** 256 - 1; // id for non existing order or position

    mapping(uint256 orderId => Order) private orders;
    mapping(address user => User) private users;
    mapping(uint256 positionId => Position) private positions;

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
        uint256[] memory positionIds = new uint256[](0);
        uint256 newOrderId = _addOrderToOrders(
            msg.sender,
            _isBuyOrder,
            _quantity,
            _price,
            positionIds
        );

        // Update users: add orderId in depositIds array
        _pushOrderIdInDepositIdsInUsers(newOrderId, msg.sender);

        _transferTokenFrom(msg.sender, _quantity, _isBuyOrder);

        emit PlaceOrder(msg.sender, _quantity, _price, _isBuyOrder);
    }

    /// @notice lets users increase deposited assets in their order
    /// @param _orderId id of the order in which assets are deposited
    /// @param _increasedQuantity quantity of assets added

    function increaseDeposit(
        uint256 _orderId,
        uint256 _increasedQuantity
    )
        external
        orderExists(_orderId)
        isPositive(_increasedQuantity)
        onlyMaker(getMaker(_orderId))
    {
        bool isBid = orders[_orderId].isBuyOrder;
        
        _checkAllowanceAndBalance(msg.sender, _increasedQuantity, isBid);

        // update orders: add quantity to orders
        _increaseOrderByQuantity(_orderId, _increasedQuantity);

        _transferTokenFrom(msg.sender, _increasedQuantity, isBid);

        emit increaseOrder(msg.sender, _orderId, _increasedQuantity);
    }

    /// @notice lets user partially or fully remove her order from the book
    /// Only non-borrowed assets can be removed
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

        require(removedOrder.quantity >= _quantityToRemove,
            "removeOrder: Removed quantity exceeds deposit"
        );

        // Remaining total deposits must be enough to secure existing borrowing positions
        require(_quantityToRemove <=  
            getUserExcessCollateral(removedOrder.maker, removedOrder.isBuyOrder),
            "removeOrder: Close your borrowing positions before removing your orders"
        );

        // removal is allowed for non-borrowed assets
        uint256 transferredQuantity = 
            min(getNonBorrowedAssets(_removedOrderId), _quantityToRemove);

        // reduce quantity in order, delete order if emptied
        _reduceOrderByQuantity(_removedOrderId, transferredQuantity);

        // remove orderId in depositIds array in users, if fully removed
        _removeOrderIdFromDepositIdsInUsers(removedOrder.maker, _removedOrderId);

        _transferTokenTo(msg.sender, transferredQuantity, removedOrder.isBuyOrder);

        emit RemoveOrder(
            removedOrder.maker,
            transferredQuantity,
            removedOrder.price,
            removedOrder.isBuyOrder
        );
    }

    /// @notice Let users take limit orders, regardless the orders' assets are borrowed or not
    /// full taking liquidates all borrowing positions
    /// Assets can be partially taken
    /// partial taking liquidates enough borrowing positions to cover taken quantity
    /// if a positions is liquidated, it is in full
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
            "Taken quantity exceeds deposit");

        // liquidate enough borrowing positions
        // output the quantity actually liquidated (can be >= taken quantity)
        uint256 liquidatedQuantity = _liquidateAssets(_takenOrderId, _takenQuantity);

        require(liquidatedQuantity >= _takenQuantity,
            "Not enough quantity displaced");

        // quantity given by taker in exchange of _takenQuantity
        uint256 exchangedQuantity = _converts(
            _takenQuantity,
            takenOrder.price,
            takenOrder.isBuyOrder
        );

        _checkAllowanceAndBalance(msg.sender, exchangedQuantity, !takenOrder.isBuyOrder);

        // reduce quantity in order, delete if emptied
        _reduceOrderByQuantity(_takenOrderId, _takenQuantity);

        // remove orderId in depositIds array in users (check taking is full before)
        _removeOrderIdFromDepositIdsInUsers(takenOrder.maker, _takenOrderId);

        // if a buy order is taken, the taker pays the quoteToken and receives the baseToken
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
        require(availableAssets >= _borrowedQuantity,
            "Insufficient available assets"
        );

        // note enough deposits available to collateralize additional debt
        require(getUserExcessCollateral(msg.sender, borrowedOrder.isBuyOrder) >=
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
        Order memory repaidOrder = orders[_repaidOrderId];
        uint256 positionId = getPositionIdInPositions(_repaidOrderId, msg.sender);

        require(positionId != ABSENT && positions[positionId].borrowedAssets > 0,
            "repayBorrowing: No borrowing position found");

        require(_repaidQuantity <= positions[positionId].borrowedAssets,
            "repayBorrowing: Repaid quantity exceeds borrowed quantity");

        _checkAllowanceAndBalance(msg.sender, _repaidQuantity, repaidOrder.isBuyOrder);

        // update positions: decrease borrowedAssets, delete position if emptied
        _reduceBorrowingByQuantity(positionId, _repaidQuantity);

        // remove positionId from positionIds in orders (check if removal is full before)
        _removePositionIdFromPositionIdsInOrders(positionId, _repaidOrderId);

        // remove repaid order id from borrowFromIds in users (check if removal is full before)
        _removeOrderIdFromBorrowFromIdsInUsers(msg.sender, _repaidOrderId);

        _transferTokenFrom(msg.sender, _repaidQuantity, repaidOrder.isBuyOrder);

        emit repayLoan(
            msg.sender,
            _repaidOrderId,
            _repaidQuantity,
            repaidOrder.isBuyOrder
        );
    }

    ///////******* Internal functions *******///////

    /// @notice Liquidate borrowing positions after taking an order
    /// if taking is partial, liquidate enough borrowing positions (one by one as they come)
    /// outputs the quantity liquidated
    /// doesn't perform the final transfers (removing or taking)
    /// @param _fromOrderId order from which borrowing positions must be cleared
    /// @param _takenQuantity quantity taken

    function _liquidateAssets(
        uint256 _fromOrderId,
        uint256 _takenQuantity
    )
        internal
        returns (uint256 liquidatedQuantity)
    {
        liquidatedQuantity = 0;
        uint256[] memory positionIds = orders[_fromOrderId].positionIds;

        // iterate on the position ids which borrow frOm the order to be taken
        for (uint256 i = 0; i < positionIds.length; i++) {
            Position memory fromPosition = positions[positionIds[i]];
            // liquidate borrowing position one by one
            _liquidate(positionIds[i]);
            liquidatedQuantity += fromPosition.borrowedAssets;
            // if liquidated assets are at least taken quantity, stop liquidation
            if (liquidatedQuantity >= _takenQuantity) {
                break;
            }
        }
    }

    /// @notice liquidate a borrowing position: seize collateral and write off debt for the same amount
    /// liquidation of a position is always full, i.e. borrower's debt is fully written off
    /// as multiple orders by the same borrower may collateralize the liquidated position:
    ///  - iterate on collateral orders made by borrower in the opposite currency
    ///  - seize collateral orders as they come, stops when borrower's debt is fully written off
    ///  - change internal balances
    /// doesn't execute final external transfer of assets
    /// @param _positionId id of the position to be liquidated

    function _liquidate(
        uint256 _positionId
    )
        internal
        positionExists(_positionId)
    {
        Position memory position = positions[_positionId]; // position to be liquidated
        uint256 takenOrderId = position.orderId; // id of the order from which assets are taken
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
                // update users: remove taken order id in borrowFromIds array
                _removeOrderIdFromBorrowFromIdsInUsers(position.borrower, takenOrderId);
                // update orders: remove position id from positionIds array
                _removeOrderIdFromPositionIdsInOrders(position.borrower, id);
                // update orders: delete emptied order
                _reduceOrderByQuantity(id, orders[id].quantity);
                // update users: remove seized order id from depositIds array
                _removeOrderIdFromDepositIdsInUsers(position.borrower, id);
            } else {
                // enough collateral assets are seized before borrower's order is fully seized
                collateralToSeize = 0;
                _reduceOrderByQuantity(id, collateralToSeize);
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
        uint256[] memory _positionIds
    )
        internal 
        returns (uint256 orderId)
    {
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
            _removeElementFromArray(users[_user].borrowFromIds, row);
        }
    }

    function _removeElementFromArray(
        uint256[] storage _array,
        uint256 row
    )
        internal
    {
        require(row < _array.length, "Row out of bounds");
        _array[row] = _array[_array.length - 1];
        _array.pop();
    }


    function _removeOrderIdFromPositionIdsInOrders(
        address _borrower,
        uint256 _orderId
    ) internal userExists(_borrower) orderExists(_orderId)
    {
        uint256 row = getPositionIdsRowInOrders(_orderId, _borrower);
        if (row != ABSENT) {
            _removeElementFromArray(orders[_orderId].positionIds, row);
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
                _removeElementFromArray(users[_user].depositIds, row);
            }
        }
    }

    /// @notice update positions: add new position in positions mapping
    /// check first that position doesn't exist already
    /// returns existing or new position id in positions mapping
    /// @param _borrower address of the borrower
    /// @param _orderId id of the order from which assets are borrowed
    /// @param _borrowedQuantity quantity of assets borrowed (quoteToken for buy orders, baseToken for sell orders)

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

    // update positions: decrease borrowedAssets, delete position if no more borrowing
    function _reduceBorrowingByQuantity(
        uint256 _positionId,
        uint256 _repaidQuantity
    )
        internal
        positionExists(_positionId)
    {
        positions[_positionId].borrowedAssets -= _repaidQuantity;
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
                _removeElementFromArray(orders[_orderId].positionIds, row);
            }
        }
    }

    // reduce quantity offered in order, delete order if emptied

    function _increaseOrderByQuantity(
        uint256 _orderId,
        uint256 _quantity
    )
        internal
        orderExists(_orderId)
        isPositive(_quantity)
    {
        orders[_orderId].quantity -= _quantity;
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

    // get quantity of assets lent by order
    function getNonBorrowedAssets(
        uint256 _orderId
    )
        internal view
        orderExists(_orderId)
        returns (uint256 nonBorrowedAssets)
    {
        nonBorrowedAssets = getTotalAssetsLentByOrder(_orderId);
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
