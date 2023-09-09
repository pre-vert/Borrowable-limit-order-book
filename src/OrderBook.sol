// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IOrderBook} from "./interfaces/IOrderBook.sol";

contract OrderBook is IOrderBook {
    using Math for uint256;

    IERC20 private quoteToken;
    IERC20 private baseToken;

    struct Order {
        address maker;
        bool isBuyOrder;
        uint256 quantity; // assets deposited (quoteToken for buy orders, baseToken for sell orders)
        uint256 price;
        // uint256 shareBorrowed; // share of assets borrowed
        // uint256 shareCollateralizing; // share of assets collateralizing borrowing positions
        uint256 rowIndex; // index of the order in the array
    }

    struct Pair {
        uint256 lenderId; // index of the lender order
        uint256 borrowerId; // index of the borrower order
        uint256 borrowedAssets; // assets borrowed
    }

    Order[] private orders; // Arrays to store buy and sell orders
    Pair[] private pairs; // Arrays to store orders pairs

    constructor(address _quoteToken, address _baseToken) {
        quoteToken = IERC20(_quoteToken);
        baseToken = IERC20(_baseToken);
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
            // shareBorrowed: 0,
            // shareCollateralizing: 0,
            rowIndex: orders.length
        });

        orders.push(newOrder);

        emit PlaceOrder(msg.sender, _quantity, _price, _isBuyOrder);
    }

    function removeOrder(uint256 _removedId) external {
        Order memory removedOrder = orders[_removedId];
        require(
            removedOrder.maker == msg.sender,
            "removeOrder: Only maker can remove order"
        );
        require(
            borrowedAssets(_removedId) == 0,
            "removeOrder: Close your borrowing positions first"
        );

        for (uint256 i = 0; i < pairs.length; i++) {
            if (pairs[i].lenderId == _removedId) {
                moveOrEnd(_removedId, pairs[i].borrowerId);
            }
        }

        if (removedOrder.isBuyOrder) {
            quoteToken.transfer(msg.sender, removedOrder.quantity);
        } else {
            baseToken.transfer(msg.sender, removedOrder.quantity);
        }

        updateOrdersAfterRemoval(_removedId);
        updatePairsAfterRemoval(_removedId);

        emit RemoveOrder(
            msg.sender,
            removedOrder.quantity,
            removedOrder.price,
            removedOrder.isBuyOrder
        );
    }

    function takeOrder(uint256 _takenId) external {
        Order memory takenOrder = orders[_takenId];
        if (takenOrder.isBuyOrder) {
            uint256 baseQuantity = takenOrder.quantity / takenOrder.price;
            require(
                baseToken.balanceOf(msg.sender) >= baseQuantity,
                "takeOrder, base token: Insufficient balance"
            );
            require(
                baseToken.allowance(msg.sender, address(this)) >= baseQuantity,
                "takeOrder, base token: Insufficient allowance"
            );
            baseToken.transferFrom(msg.sender, address(this), baseQuantity);
            baseToken.transfer(takenOrder.maker, baseQuantity);
            quoteToken.transfer(msg.sender, takenOrder.quantity);
        } else {
            uint256 quoteQuantity = takenOrder.quantity * takenOrder.price;
            require(
                quoteToken.balanceOf(msg.sender) >= quoteQuantity,
                "takeOrder, quote token: Insufficient balance"
            );
            require(
                quoteToken.allowance(msg.sender, address(this)) >=
                    quoteQuantity,
                "takeOrder, quote token: Insufficient allowance"
            );
            quoteToken.transferFrom(msg.sender, address(this), quoteQuantity);
            quoteToken.transfer(takenOrder.maker, quoteQuantity);
            baseToken.transfer(msg.sender, takenOrder.quantity);
        }

        updateOrdersAfterRemoval(_takenId);

        emit TakeOrder(
            msg.sender,
            takenOrder.maker,
            takenOrder.quantity,
            takenOrder.price,
            takenOrder.isBuyOrder
        );
    }

    function borrowOrder(uint256 _borrowedId, uint256 _collateralId) external {
        Order memory borrowedOrder = orders[_borrowedId];
        Order memory collateralOrder = orders[_collateralId];
        if (borrowedOrder.isBuyOrder) {
            uint256 baseCollateral = borrowedOrder.quantity /
                borrowedOrder.price;
            require(
                collateralOrder.quantity >= baseCollateral,
                "borrowOrder, base token: Insufficient collateral"
            );
            quoteToken.transfer(msg.sender, borrowedOrder.quantity);
        } else {
            uint256 quoteCollateral = borrowedOrder.quantity *
                borrowedOrder.price;
            require(
                collateralOrder.quantity >= quoteCollateral,
                "borrowedOrder, quote token: Insufficient collateral"
            );
            baseToken.transfer(msg.sender, borrowedOrder.quantity);
        }

        updateOrdersAfterRemoval(_borrowedId);

        emit BorrowOrder(
            msg.sender,
            borrowedOrder.maker,
            borrowedOrder.quantity,
            borrowedOrder.price,
            borrowedOrder.isBuyOrder
        );
    }

    function updateOrdersAfterRemoval(uint256 _removedOrderId) internal {
        // update row index of the last order
        orders[orders.length - 1].rowIndex = _removedOrderId;
        // Move last order into the place to delete
        orders[_removedOrderId] = orders[orders.length - 1];
        // Remove last element
        orders.pop();
    }

    function updatePairsAfterRemoval(uint256 _removedOrderId) internal {}

    // Try to reallocate the borrowing position, else liquidate
    function moveOrEnd(uint256 _lenderId, uint256 _borrowerId) internal {}

    // View functions

    function getQuoteTokenAddress() public view returns (address) {
        return (address(quoteToken));
    }

    function getBaseTokenAddress() public view returns (address) {
        return (address(baseToken));
    }

    function getOrder(uint _idOrder) public view returns (Order memory) {
        return (orders[_idOrder]);
    }

    function getBookSize() public view returns (uint256) {
        return orders.length;
    }

    // Quantity of assets borrowed by the order
    function borrowedAssets(
        uint256 _borrowerId
    ) internal view returns (uint256) {
        uint256 totalBorrowedAssets = 0;
        for (uint256 i = 0; i < pairs.length; i++) {
            if (pairs[i].borrowerId == _borrowerId) {
                totalBorrowedAssets =
                    totalBorrowedAssets +
                    pairs[i].borrowedAssets;
            }
        }
        return totalBorrowedAssets;
    }

    // Quantity of assets lent by the order
    function lentAssets(uint256 _lenderId) internal view returns (uint256) {
        uint256 totalLentAssets = 0;
        for (uint256 i = 0; i < pairs.length; i++) {
            if (pairs[i].lenderId == _lenderId) {
                totalLentAssets = totalLentAssets + pairs[i].borrowedAssets;
            }
        }
        return totalLentAssets;
    }
}
