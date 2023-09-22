// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IOrderBook} from "./interfaces/IOrderBook.sol";
import {console} from "forge-std/Test.sol";

contract OrderBook is IOrderBook {
    using Math for uint256;

    IERC20 private quoteToken;
    IERC20 private baseToken;

    struct Order {
        address maker;
        bool isBuyOrder;
        uint256 quantity; // assets deposited (quoteToken for buy orders, baseToken for sell orders)
        uint256 price; // price of the order
        uint256 rowIndex; // index of the order in the array
    }

    mapping(address => uint256) private balances; // balances of the users (quoteToken for buy orders, baseToken for sell orders

    struct Borrower {
        address borrower; // address of the borrower
        uint256 orderId; // index in the array orders of the order which assets are borrowed
        uint256 borrowedAssets; // quantity of assets borrowed (quoteToken for buy orders, baseToken for sell orders)
    }

    uint256 public constant minBaseDeposit = 1;
    uint256 public constant minQuoteDeposit = 100;

    Order[] private orders; // Arrays to store buy and sell orders
    Borrower[] private borrowers; // Arrays to store borrowers

    constructor(address _quoteToken, address _baseToken) {
        quoteToken = IERC20(_quoteToken);
        baseToken = IERC20(_baseToken);
    }

    modifier orderExists(uint256 _orderId) {
        require(_orderId < orders.length, "Order does not exist");
        _;
    }

    // let users place orders in the order book
    // transfer the assets to the order book
    // add a balance in the array orders

    function placeOrder(
        uint256 _quantity,
        uint256 _price,
        bool _isBuyOrder
    ) external {
        require(_quantity > 0, "placeOrder: Zero quantity is not allowed");
        require(_price > 0, "placeOrder: Zero price is not allowed");
        if (_isBuyOrder) {
            require(
                quoteToken.balanceOf(msg.sender) >= _quantity,
                "placeOrder: Insufficient balance"
            );
            require(
                _quantity <= quoteToken.allowance(msg.sender, address(this)),
                "placeOrder: Insufficient allowance"
            );
            quoteToken.transferFrom(msg.sender, address(this), _quantity);
        } else {
            require(
                baseToken.balanceOf(msg.sender) >= _quantity,
                "placeOrder: Insufficient balance"
            );
            require(
                _quantity <= baseToken.allowance(msg.sender, address(this)),
                "placeOrder: Insufficient allowance"
            );
            baseToken.transferFrom(msg.sender, address(this), _quantity);
        }

        // Insert order in the book
        Order memory newOrder = Order({
            maker: msg.sender,
            isBuyOrder: _isBuyOrder,
            quantity: _quantity,
            price: _price,
            rowIndex: orders.length
        });

        orders.push(newOrder);

        emit PlaceOrder(msg.sender, _quantity, _price, _isBuyOrder);
    }

    // let users remove their orders from the orderbook
    // the same order can have its assets borrowed by several positions
    // removal is subject to succesful reallocation of borrowed assets
    // desired quantity to be removed can be partial and the quantity actually removed can be even less:
    // orders[_removedOrderId].quantity >= _quantityToBeRemoved >= repositionedQuantity >= 0

    function removeOrder(
        uint256 _removedOrderId,
        uint256 _quantityToBeRemoved
    ) external orderExists(_removedOrderId) {
        Order memory removedOrder = orders[_removedOrderId];

        require(
            removedOrder.maker == msg.sender,
            "removeOrder: Only the maker can remove the order"
        );

        require(
            removedOrder.quantity >= _quantityToBeRemoved,
            "removeOrder: Removed quantity exceeds deposit"
        );

        // Remaining total deposits must be enough to secure existing borrowing positions

        uint256 borrowerTotalDeposit = getUserTotalDeposit(
            msg.sender,
            removedOrder.isBuyOrder
        ) - getBorrowerTotalDebt(msg.sender, removedOrder.isBuyOrder);
        require(
            _quantityToBeRemoved <= borrowerTotalDeposit,
            "removeOrder: Close your borrowing positions before removing your orders"
        );

        // if removal is full, try to reposition *all* related borrowing positions elsewhere in the order book
        // if removal is partial, try to reposition enough to cover removed quantity
        // for each detected borrowing positions, the repositioned assets are either the quantity
        // borrowed by the position (if less) or the remaining quantity to be repositioned (if less)
        // a borrowing positions is either fully repositioned (all borrowed assets are moved) or not at all
        // if not enough assets are repositioned, removal is partial and equal to removed quantity

        uint256 repositionedQuantity = 0;

        for (uint256 j = 0; j < borrowers.length; j++) {
            if (borrowers[j].orderId == _removedOrderId) {
                uint256 quantityToReposition = borrowers[j].borrowedAssets.min(
                    _quantityToBeRemoved - repositionedQuantity
                );

                // try to reposition the borrowing position in full
                uint256 newId = repositionDebt(
                    borrowers[j].borrower,
                    _removedOrderId,
                    quantityToReposition
                );

                // if debt reposition is successful, update repositionedQuantity
                if (newId != _removedOrderId) {
                    repositionedQuantity += quantityToReposition;
                    if (repositionedQuantity == _quantityToBeRemoved) {
                        break;
                    }
                }
            }
        }

        // removal is executed for the quantity actually repositioned
        if (repositionedQuantity > 0) {
            if (removedOrder.isBuyOrder) {
                quoteToken.transfer(msg.sender, repositionedQuantity);
            } else {
                baseToken.transfer(msg.sender, repositionedQuantity);
            }

            // if all borrowed assets could be repositioned, removal is complete
            // in this case, remove the order from the book, otherwise adjust internal balances

            if (repositionedQuantity == removedOrder.quantity) {
                removeOrderFromTheBook(_removedOrderId);
            } else {
                removedOrder.quantity -= repositionedQuantity;
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
    ) external orderExists(_takenOrderId) {
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

        // tries to reposition associated borrowing positions (if any) in the order book
        // reposition as much as possible but just enough to cover the taken quantity
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
        // _takenQuantity - repositionedQuantity >= borrowers[i].borrowedAssets
        // the quantity to reposition is at most the borrowed assets of the order: quantityToReposition = borrowers[i].borrowedAssets
        // 2) the quantity left to be repositioned is less than borrowed assets of a given order
        // the quantity to reposition is at most the quantity left to be repositioned

        for (uint256 j = 0; j < borrowers.length; j++) {
            if (borrowers[j].orderId == _takenOrderId) {
                uint256 quantityToReposition = borrowers[j].borrowedAssets.min(
                    _takenQuantity - repositionedQuantity
                );
                uint256 newId = repositionDebt(
                    borrowers[j].borrower,
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
                    liquidate(borrowers[j].borrower, _takenOrderId);
                }
            }
        }

        // once repositionedQuantity == _takenQuantity, execution of the swap
        // all borrowing positions have been repositioned, liquidated or preserved

        if (takenOrder.isBuyOrder) {
            uint256 baseQuantity = _takenQuantity / takenOrder.price;
            baseToken.transferFrom(msg.sender, address(this), baseQuantity);
            baseToken.transfer(takenOrder.maker, baseQuantity);
            quoteToken.transfer(msg.sender, _takenQuantity);
        } else {
            uint256 quoteQuantity = _takenQuantity * takenOrder.price;
            quoteToken.transferFrom(msg.sender, address(this), quoteQuantity);
            quoteToken.transfer(takenOrder.maker, quoteQuantity);
            baseToken.transfer(msg.sender, _takenQuantity);
        }

        // if the taker swaps all the assets of the order, remove the order from the order book
        // otherwise adjust internal balances

        if (_takenQuantity == takenOrder.quantity) {
            removeOrderFromTheBook(_takenOrderId);
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
        uint256 _orderId,
        uint256 _borrowedQuantity
    ) external orderExists(_orderId) {
        Order memory borrowedOrder = orders[_orderId];

        require(
            isOrderBorrowable(_orderId),
            "borrowOrder: Assets not available for borrowing"
        );

        uint256 availableAssets = borrowedOrder.quantity -
            getTotalAssetsLentByOrder(_orderId);
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

        if (borrowedOrder.isBuyOrder) {
            quoteToken.transfer(msg.sender, _borrowedQuantity);
        } else {
            baseToken.transfer(msg.sender, _borrowedQuantity);
        }

        // update internal records for the new borrowing position
        // begin by searching for an existing borrowing position to update

        bool borrowerExists = false;
        for (uint256 j = 0; j < borrowers.length; j++) {
            if (
                borrowers[j].borrower == msg.sender &&
                borrowers[j].orderId == _orderId
            ) {
                borrowers[j].borrowedAssets += _borrowedQuantity;
                borrowerExists = true;
                break;
            }
        }

        // if no existing borrowing position, create a new one

        if (!borrowerExists) {
            Borrower memory newBorrower = Borrower({
                borrower: msg.sender,
                orderId: _orderId,
                borrowedAssets: _borrowedQuantity
            });
            borrowers.push(newBorrower);
        }

        emit BorrowOrder(
            msg.sender,
            _orderId,
            _borrowedQuantity,
            borrowedOrder.isBuyOrder
        );
    }

    // let users decrease or close a borrowing position

    function repayBorrowing(
        uint256 _repaidOrderId,
        uint256 _repaidQuantity
    ) external orderExists(_repaidOrderId) {
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

        if (orders[_repaidOrderId].isBuyOrder) {
            require(
                quoteToken.balanceOf(msg.sender) >= _repaidQuantity,
                "repayBorrowing, quote token: Insufficient balance"
            );
            require(
                quoteToken.allowance(msg.sender, address(this)) >=
                    _repaidQuantity,
                "repayBorrowing, quote token: Insufficient allowance"
            );
            quoteToken.transferFrom(msg.sender, address(this), _repaidQuantity);
        } else {
            require(
                baseToken.balanceOf(msg.sender) >= _repaidQuantity,
                "repayBorrowing, base token: Insufficient balance"
            );
            require(
                baseToken.allowance(msg.sender, address(this)) >=
                    _repaidQuantity,
                "repayBorrowing, base token: Insufficient allowance"
            );
            baseToken.transferFrom(msg.sender, address(this), _repaidQuantity);
        }

        borrowers[borrowingId].borrowedAssets -= _repaidQuantity;
        if (borrowers[borrowingId].borrowedAssets == 0) {
            borrowers[borrowingId] = borrowers[borrowers.length - 1];
            borrowers.pop();
        }

        emit repayLoan(
            msg.sender,
            _repaidOrderId,
            _repaidQuantity,
            orders[_repaidOrderId].isBuyOrder
        );
    }

    ///////******* Internal functions *******///////

    // update the order book after an order has been removed:
    // a) move last order into the place to delete
    // b) update row index of the last order to the new position
    // c) remove last element

    function removeOrderFromTheBook(
        uint256 _removedOrderId
    ) internal orderExists(_removedOrderId) {
        orders[_removedOrderId] = orders[orders.length - 1];
        orders[_removedOrderId].rowIndex = _removedOrderId;
        orders.pop();
    }

    // the function takes as input the borrower's address and the order id which is taken or canceled ('orderOut')
    // borrowed assets from orderOut are repositioned to the next best-price order ('orderIn'), if exists
    // cannot reposition to more than one order and only if all borrowed assets in orderOut can be transferred to orderIn,
    // some of orderIn's assets could already be borrowed, and the new borrowing doesn't have to exhaust its remaining assets
    // update internal debt balances, but doesn't perform the final transfer (removing or taking of orderOut)
    // returns the id of orderIn if the reposition is successful, or the id of orderOut if a failure

    function repositionDebt(
        address _borrower,
        uint256 _orderOutId,
        uint256 _quantityToReposition
    ) internal orderExists(_orderOutId) returns (uint256 newOrderId) {
        newOrderId = _orderOutId;
        bool isBid = orders[_orderOutId].isBuyOrder; // type (buy or sell order) of orderOut

        // screen orders to find the ones borrowable, which:
        // have the same type (buy or sell) as orderOut, but are not orderOut
        // have available assets to be borrowed, at least equal to the borrowed quantity (no fragmentation)
        // have the best price (highest for buy orders, lowest for sell orders)

        uint256 bestPrice = 0;

        for (uint256 i = 0; i < orders.length; i++) {
            if (
                orders[i].isBuyOrder == isBid &&
                i != _orderOutId &&
                isOrderBorrowable(i) &&
                (orders[i].quantity - getTotalAssetsLentByOrder(i) >=
                    _quantityToReposition)
            ) {
                if (bestPrice == 0) {
                    bestPrice = orders[i].price;
                    newOrderId = i;
                } else if (
                    (isBid && orders[i].price > bestPrice) ||
                    (!isBid && orders[i].price < bestPrice)
                ) {
                    bestPrice = orders[i].price;
                    newOrderId = i;
                }
            }
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

            // if the borrower has enough equity to switch to orderIn, update internal balances:
            // retrieve the borrowing id of orderOut
            // retrieve the borrower of the new order to which the debt is transferred
            // transfer the debt to the new order and update borrowers balances

            if (
                getUserTotalDeposit(_borrower, isBid) >=
                getBorrowerNeededCollateral(_borrower, isBid) +
                    increasedCollateral
            ) {
                (, uint256 borrowingOutId) = getBorrowerPosition(
                    _borrower,
                    _orderOutId
                );

                // if the borrowing line is emptied, remove it from the borrowers array
                borrowers[borrowingOutId]
                    .borrowedAssets -= _quantityToReposition;

                if (borrowers[borrowingOutId].borrowedAssets == 0) {
                    borrowers[borrowingOutId] = borrowers[borrowers.length - 1];
                    borrowers.pop();
                }

                (
                    uint256 borrowedQuantity,
                    uint256 borrowingNewId
                ) = getBorrowerPosition(_borrower, newOrderId);

                // if the borrower doesn't already borrow from the new order, create a new borrowing position
                if (borrowedQuantity == 0) {
                    Borrower memory newBorrower = Borrower({
                        borrower: _borrower,
                        orderId: newOrderId,
                        borrowedAssets: _quantityToReposition
                    });
                    borrowers.push(newBorrower);
                } else {
                    // update the existing borrowing position
                    borrowers[borrowingNewId]
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

        bool isBid = orders[_orderOutId].isBuyOrder; // type (buy or sell order) of orderOut

        uint256 remainingCollateralToWipeOut = borrowedQuantity;

        for (uint256 i = 0; i < orders.length; i++) {
            if (orders[i].maker == _borrower && orders[i].isBuyOrder != isBid) {
                uint256 orderAssets = orders[i].quantity;

                if (remainingCollateralToWipeOut >= orderAssets) {
                    remainingCollateralToWipeOut -= orderAssets;
                    removeOrderFromTheBook(i);
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

            borrowers[borrowingId] = borrowers[borrowers.length - 1];
            borrowers.pop();
        }
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
        uint256 _orderId
    ) public view orderExists(_orderId) returns (address) {
        return orders[_orderId].maker;
    }

    // check if the maker is a borrower
    function isMakerBorrower(
        address _maker
    ) internal view returns (bool isBorrower) {
        isBorrower = false;
        for (uint256 i = 0; i < borrowers.length; i++) {
            if (borrowers[i].borrower == _maker) {
                isBorrower = true;
                break;
            }
        }
    }

    // only assets which do not serve as collateral are borrowable
    // check if the maker is not a borrower

    function isOrderBorrowable(
        uint256 _orderId
    ) internal view orderExists(_orderId) returns (bool) {
        return !isMakerBorrower(getMaker(_orderId));
    }

    // get assets deposited by a trader/borrower in a given order, in the quote or base token
    function getUserDeposit(
        uint256 _orderId
    ) internal view orderExists(_orderId) returns (uint256 userDeposit) {
        userDeposit = orders[_orderId].quantity;
    }

    // get all assets deposited by a trader/borrower in the quote or base token
    function getUserTotalDeposit(
        address _userAddress,
        bool _isQuoteToken
    ) internal view returns (uint256 totalDeposit) {
        totalDeposit = 0;
        for (uint256 i = 0; i < orders.length; i++) {
            if (
                orders[i].maker == _userAddress &&
                orders[i].isBuyOrder == _isQuoteToken
            ) {
                totalDeposit += orders[i].quantity;
            }
        }
    }

    // takes as inputs the borrower's address and the order id from which assets are borrowed
    // returns borrower's borrowed quantity and borrowing id in array borrowers
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
        for (uint256 j = 0; j < borrowers.length; j++) {
            if (
                borrowers[j].borrower == _borrowerAddress &&
                borrowers[j].orderId == _orderId &&
                borrowers[j].borrowedAssets > 0
            ) {
                borrowingId = j;
                borrowerLoan = borrowers[j].borrowedAssets;
                break;
            }
        }
    }

    // get borrower's total Debt in the quote or base token
    function getBorrowerTotalDebt(
        address _borrowerAddress,
        bool _isQuoteToken
    ) internal view returns (uint256 totalDebt) {
        totalDebt = 0;
        for (uint256 j = 0; j < borrowers.length; j++) {
            if (
                borrowers[j].borrower == _borrowerAddress &&
                orders[borrowers[j].orderId].isBuyOrder == _isQuoteToken
            ) {
                totalDebt += borrowers[j].borrowedAssets;
            }
        }
    }

    // get borrower's total collateral needed to secure his debt in the quote or base token
    // if order is a buy order, borrowed assets are in quote token and collateral needed is in base token
    // Ex: Alice deposits 2000 USDC to buy ETH at 2000; Bob borrows 1000 and put as collateral 1000/2000 = 0.5 ETH

    function getBorrowerNeededCollateral(
        address _borrowerAddress,
        bool _isQuoteToken
    ) internal view returns (uint256 totalNeededCollateral) {
        totalNeededCollateral = 0;
        for (uint256 j = 0; j < borrowers.length; j++) {
            if (borrowers[j].borrower == _borrowerAddress) {
                uint256 orderId = borrowers[j].orderId;
                if (orders[orderId].isBuyOrder == _isQuoteToken) {
                    totalNeededCollateral +=
                        borrowers[j].borrowedAssets /
                        orders[orderId].price;
                } else {
                    totalNeededCollateral +=
                        borrowers[j].borrowedAssets *
                        orders[orderId].price;
                }
            }
        }
    }

    // get quantity of assets lent by the order
    function getTotalAssetsLentByOrder(
        uint256 _orderId
    ) internal view orderExists(_orderId) returns (uint256) {
        uint256 totalLentAssets = 0;
        for (uint256 j = 0; j < borrowers.length; j++) {
            if (borrowers[j].orderId == _orderId) {
                totalLentAssets += borrowers[j].borrowedAssets;
            }
        }
        return totalLentAssets;
    }
}
