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

    // Removal is subject to reallocation of borrowed assets
    // can remove less than the total quantity: _quantityToBeRemoved < removedOrder.quantity
    // actually removed can be less than expressed: removedQuantity <= _quantityToBeRemoved

    function removeOrder(
        uint256 _removedId,
        uint256 _quantityToBeRemoved
    ) external orderExists(_removedId) {
        Order memory removedOrder = orders[_removedId];

        require(
            removedOrder.maker == msg.sender,
            "removeOrder: Only maker can remove order"
        );

        require(
            removedOrder.quantity >= _quantityToBeRemoved,
            "removeOrder: Removed quantity exceeds deposit"
        );

        // Equity is excess collateral to secure existing debt

        uint256 borrowerEquity = getUserTotalDeposit(
            msg.sender,
            removedOrder.isBuyOrder
        ) - getBorrowerTotalDebt(msg.sender, removedOrder.isBuyOrder);
        require(
            _quantityToBeRemoved <= borrowerEquity,
            "removeOrder: Close your borrowing positions before removing your orders"
        );

        // reposition as much as possible borrowers liability in the order book
        // but just enough to cover the removed quantity
        // the loop detects the borrowing positions. The assets to reposition are the minimum between
        // the quantity borrowed by the position and the remaining quantity to be repositioned

        uint256 repositionedQuantity = 0;

        for (uint256 i = 0; i < borrowers.length; i++) {
            if (borrowers[i].orderId == _removedId) {
                uint256 quantityToReposition = borrowers[i].borrowedAssets.min(
                    _quantityToBeRemoved - repositionedQuantity
                );
                uint256 newId = repositionDebt(
                    borrowers[i].borrower,
                    _removedId,
                    quantityToReposition
                );
                if (newId != _removedId) {
                    // transfer debt to new order
                    repositionedQuantity += quantityToReposition;
                    if (repositionedQuantity == _quantityToBeRemoved) {
                        break;
                    }
                }
            }
        }

        if (repositionedQuantity > 0) {
            if (removedOrder.isBuyOrder) {
                quoteToken.transfer(msg.sender, repositionedQuantity);
            } else {
                baseToken.transfer(msg.sender, repositionedQuantity);
            }
        }

        // if removal is complete and all borrowed assets can be repositioned,
        // remove the order from the order book

        if (repositionedQuantity == _quantityToBeRemoved) {
            updateOrderBookAfterRemoval(_removedId);
        }

        emit RemoveOrder(
            msg.sender,
            repositionedQuantity,
            removedOrder.price,
            removedOrder.isBuyOrder
        );
    }

    // Assets can be partially taken from the order book
    // Taking triggers liquidation of associated borrowing positions which cannot be repositioned

    function takeOrder(
        uint256 _takenId,
        uint256 _takenQuantity
    ) external orderExists(_takenId) {
        Order memory takenOrder = orders[_takenId];
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

        // tries to reposition borrowing positions (if any) in the order book
        // reposition as much as possible but just enough to cover the taken quantity
        // the loop detects the borrowing positions. The assets to reposition are the minimum between
        // the quantity borrowed by the position and the remaining quantity to be repositioned

        uint256 repositionedQuantity = 0;

        for (uint256 i = 0; i < borrowers.length; i++) {
            if (borrowers[i].orderId == _takenId) {
                uint256 quantityToReposition = borrowers[i].borrowedAssets.min(
                    _takenQuantity - repositionedQuantity
                );
                uint256 newId = repositionDebt(
                    borrowers[i].borrower,
                    _takenId,
                    quantityToReposition
                );

                // the borrowing position could be successfully repositioned to newId
                if (newId != _takenId) {
                    repositionedQuantity += quantityToReposition;
                    if (repositionedQuantity == _takenQuantity) {
                        break;
                    } else {
                        liquidate(borrowers[i].borrower, _takenId);
                    }
                }
            }
        }

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

        updateOrderBookAfterRemoval(_takenId);

        emit TakeOrder(
            msg.sender,
            takenOrder.maker,
            takenOrder.quantity,
            takenOrder.price,
            takenOrder.isBuyOrder
        );
    }

    // create a borrowing position or increase an existing one
    // orders are borrowable if the maker is not a borrower (i.e. the assets are not used as collateral)
    // and if the borrower does not demand more than what is available
    // and if the borrower has enough equity to borrow the assets

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

        uint256 borrowerEquity = getUserTotalDeposit(
            msg.sender,
            borrowedOrder.isBuyOrder
        ) - getBorrowerNeededCollateral(msg.sender, borrowedOrder.isBuyOrder);
        require(
            borrowedOrder.quantity <= borrowerEquity,
            "borrowOrder: Insufficient collateral"
        );

        if (borrowedOrder.isBuyOrder) {
            quoteToken.transfer(msg.sender, _borrowedQuantity);
        } else {
            baseToken.transfer(msg.sender, _borrowedQuantity);
        }

        // update the array borrowers which records the borrowing positions
        // search for an existing borrowing position to update

        bool borrowerExists = false;
        for (uint256 i = 0; i < borrowers.length; i++) {
            if (
                borrowers[i].borrower == msg.sender &&
                borrowers[i].orderId == _orderId
            ) {
                borrowers[i].borrowedAssets =
                    borrowers[i].borrowedAssets +
                    _borrowedQuantity;
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

    // decrease or close a borrowing position

    function repayBorrowedAssets(
        uint256 _orderId,
        uint256 _repaidQuantity
    ) external orderExists(_orderId) {
        bool borrowerExists = false;
        for (uint256 i = 0; i < borrowers.length; i++) {
            if (
                borrowers[i].borrower == msg.sender &&
                borrowers[i].orderId == _orderId
            ) {
                borrowers[i].borrowedAssets =
                    borrowers[i].borrowedAssets -
                    _repaidQuantity;
                borrowerExists = true;
                break;
            }
        }
        require(
            borrowerExists,
            "repayBorrowedAssets: no borrowing position found"
        );

        if (orders[_orderId].isBuyOrder) {
            require(
                quoteToken.balanceOf(msg.sender) >= _repaidQuantity,
                "repayOrder, quote token: Insufficient balance"
            );
            require(
                quoteToken.allowance(msg.sender, address(this)) >=
                    _repaidQuantity,
                "takeOrder, quote token: Insufficient allowance"
            );
            quoteToken.transferFrom(msg.sender, address(this), _repaidQuantity);
        } else {
            require(
                baseToken.balanceOf(msg.sender) >= _repaidQuantity,
                "repayOrder, base token: Insufficient balance"
            );
            require(
                baseToken.allowance(msg.sender, address(this)) >=
                    _repaidQuantity,
                "repayOrder, base token: Insufficient allowance"
            );
            baseToken.transferFrom(msg.sender, address(this), _repaidQuantity);
        }

        emit RepayBorrowedAssets(
            msg.sender,
            _orderId,
            _repaidQuantity,
            orders[_orderId].isBuyOrder
        );
    }

    ///////******* Internal functions *******///////

    // update the order book after an order has been removed:
    // a) update row index of the last order
    // b) move last order into the place to delete
    // c) remove last element

    function updateOrderBookAfterRemoval(
        uint256 _removedOrderId
    ) internal orderExists(_removedOrderId) {
        orders[orders.length - 1].rowIndex = _removedOrderId;
        orders[_removedOrderId] = orders[orders.length - 1];
        orders.pop();
    }

    // check if the maker is a borrower
    function isMakerBorrower(
        address _maker
    ) internal view returns (bool isBorrower) {
        for (uint256 i = 0; i < borrowers.length; i++) {
            if (borrowers[i].borrower == _maker) {
                isBorrower = true;
                break;
            }
        }
        isBorrower = false;
    }

    // check if the maker is not a borrower
    // only assets which do not serve as collateral are borrowable

    function isOrderBorrowable(uint256 _orderId) internal view returns (bool) {
        return !isMakerBorrower(getMaker(_orderId));
    }

    // borrowed assets from a given order are repositioned in the order book as much as possible
    // the function takes as input the borrower's address and the order taken or canceled
    // finds if possible another order to which the borrower's position is repositioned
    // transfers the debt to the order which assets are available
    // but don't perform the final removing or taking of the order
    // returns the id of the new order to which it is succesfully repositioned
    // or the id of the order taken or canceled if the borrower's position could not be repositioned

    function repositionDebt(
        address _borrower,
        uint256 _orderId,
        uint256 _quantityToReposition
    ) internal orderExists(_orderId) returns (uint256 newOrderId) {
        newOrderId = _orderId;
        // uint256 bestId = _orderId;
        bool isBid = orders[_orderId].isBuyOrder; // type of the order which is taken or canceled (bid or ask)

        // screen all orders to find the ones borrowable, which:
        // have the same type (buy or sell) as the order taken or canceled
        // are not the order taken or canceled
        // have available assets to be borrowed, at least equal to the borrowed quantity (no fragmentation)
        // have the best price (highest for buy orders, lowest for sell orders)

        uint256 bestPrice = 0;

        for (uint256 i = 0; i < orders.length; i++) {
            if (orders[i].isBuyOrder == isBid && i != _orderId) {
                if (
                    orders[i].quantity - getTotalAssetsLentByOrder(i) >=
                    _quantityToReposition
                ) {
                    if (isOrderBorrowable(i)) {
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
            }
        }

        // still need to check whether the borrower has enough equity to switch

        uint256 increasedCollateral; // additional collateral needed to secure the increased debt

        if (newOrderId != _orderId) {
            uint256 orderExecutionPrice = orders[_orderId].price;
            uint256 nextExecutionPrice = orders[newOrderId].price;

            // Bob borrows 2000 USDC from Alice's buy order of 2 ETH at 1800, needed collateral is 2000/1800 = 1.11 ETH
            // Alice's order is taken. Next buy order is 2 ETH at 1700, needed collateral is 2000/1700 = 1.18 ETH
            // Increased needed collateral is 2000/1700 - 2000/1800 = 0.07 ETH
            // Bob borrows 1.5 ETH from Alice's sell order of 2 ETH at 2000, needed collateral is 1.5*2000 = 3000 USDC
            // Alice's order is taken. Next sell order is 1.5 ETH at 2200, needed collateral is 1.5*2200 = 3300 USDC
            // Increased needed collateral is 1.5*2200-1.5*2000 = 300 USDC

            if (orders[_orderId].isBuyOrder) {
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
            if (
                getUserTotalDeposit(_borrower, isBid) >=
                getBorrowerNeededCollateral(_borrower, isBid) +
                    increasedCollateral
            ) {
                // retrieve the borrowing position of the canceled/taken order
                // retrieve the borrower of the new order to which the debt is transferred
                // transfer the debt to the new order
                // reorganize the borrowers array

                (, uint256 borrowingOldId) = getBorrowerPosition(
                    _borrower,
                    _orderId
                );

                borrowers[borrowingOldId]
                    .borrowedAssets -= _quantityToReposition;
                if (borrowers[borrowingOldId].borrowedAssets == 0) {
                    borrowers[borrowingOldId] = borrowers[borrowers.length - 1];
                    borrowers.pop();
                }
                (
                    uint256 borrowedQuantity,
                    uint256 borrowingNewId
                ) = getBorrowerPosition(_borrower, newOrderId);
                if (borrowedQuantity == 0) {
                    // create a new borrowing position
                    Borrower memory newBorrower = Borrower({
                        borrower: _borrower,
                        orderId: _orderId,
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

    function updateOrderBokAfterRemoval(
        uint256 _removedOrderId
    ) internal orderExists(_removedOrderId) {
        orders[_removedOrderId] = orders[orders.length - 1];
        orders.pop();
    }

    function liquidate(
        address _borrower,
        uint256 _orderId
    ) internal orderExists(_orderId) {}

    //*****************************************//
    ///////******* View functions *******///////

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

    // get borrower's loan and borrower array id from a given order
    // returns loan = 0 if the borrower doesn't borrow from the order

    function getBorrowerPosition(
        address _borrowerAddress,
        uint256 _orderId
    )
        internal
        view
        orderExists(_orderId)
        returns (uint256 borrowerLoan, uint256 borroweingId)
    {
        borrowerLoan = 0;
        for (uint256 i = 0; i < borrowers.length; i++) {
            if (
                borrowers[i].borrower == _borrowerAddress &&
                borrowers[i].orderId == _orderId
            ) {
                borroweingId = i;
                borrowerLoan = borrowers[i].borrowedAssets;
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
        for (uint256 i = 0; i < borrowers.length; i++) {
            if (
                borrowers[i].borrower == _borrowerAddress &&
                orders[borrowers[i].orderId].isBuyOrder == _isQuoteToken
            ) {
                totalDebt += borrowers[i].borrowedAssets;
            }
        }
    }

    // get borrower's total collateral needed to secure his debt in the quote or base token
    // if order is a buy order, borrowed assets are in quote token and collateral needed is in base token
    // Ex: Alice deposits 2000 USDC to buy ETH at 2000; Bob borrows 1000 and put as collateral 1000/2000 1 ETH

    function getBorrowerNeededCollateral(
        address _borrowerAddress,
        bool _isQuoteToken
    ) internal view returns (uint256 totalNeededCollateral) {
        totalNeededCollateral = 0;
        for (uint256 i = 0; i < borrowers.length; i++) {
            if (borrowers[i].borrower == _borrowerAddress) {
                uint256 orderId = borrowers[i].orderId;
                if (orders[orderId].isBuyOrder == _isQuoteToken) {
                    totalNeededCollateral +=
                        borrowers[i].borrowedAssets /
                        orders[orderId].price;
                } else {
                    totalNeededCollateral +=
                        borrowers[i].borrowedAssets *
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
        for (uint256 i = 0; i < borrowers.length; i++) {
            if (borrowers[i].orderId == _orderId) {
                totalLentAssets = totalLentAssets + borrowers[i].borrowedAssets;
            }
        }
        return totalLentAssets;
    }
}
