// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

interface IOrderBook {

    function placeOrder(
        uint256 _quantity,
        uint256 _price,
        bool _isBuyOrder
    ) external;

    function increaseDeposit(
        uint256 _orderId,
        uint256 _increasedQuantity
    ) external;

    function removeOrder(
        uint256 _removedOrderId,
        uint256 _quantityToBeRemoved
    ) external;

    function takeOrder(uint256 _takenOrderId, uint256 _takenQuantity) external;

    function borrowOrder(
        uint256 _borrowedOrderId,
        uint256 _borrowedQuantity
    ) external;

    function repayBorrowing(
        uint256 _repaidOrderId,
        uint256 _repaidQuantity
    ) external;

    // Events

    event PlaceOrder(
        address maker,
        uint256 quantity,
        uint256 price,
        bool isBuyOrder
    );

    event increaseOrder(
        address maker,
        uint256 orderId,
        uint256 increasedQuantity
    );

    event RemoveOrder(
        address maker,
        uint256 quantity,
        uint256 price,
        bool isBuyOrder
    );

    event TakeOrder(
        address taker,
        address maker,
        uint256 quantity,
        uint256 price,
        bool isBuyOrder
    );
    event BorrowOrder(
        address borrower,
        uint256 orderId,
        uint256 quantity,
        bool isBuyOrder
    );

    event repayLoan(
        address borrower,
        uint256 orderId,
        uint256 quantity,
        bool isBuyOrder
    );
}
