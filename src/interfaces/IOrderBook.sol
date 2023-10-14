// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

interface IOrderBook {

    function deposit(
        uint256 _quantity,
        uint256 _price,
        bool _isBuyOrder
    ) external;

    function increaseDeposit(
        uint256 _orderId,
        uint256 _increasedQuantity
    ) external;

    function withdraw(
        uint256 _removedOrderId,
        uint256 _quantityToBeRemoved
    ) external;

    function take(uint256 _takenOrderId, uint256 _takenQuantity) external;

    function borrow(
        uint256 _borrowedOrderId,
        uint256 _borrowedQuantity
    ) external;

    function repay(
        uint256 _repaidOrderId,
        uint256 _repaidQuantity
    ) external;

    // Events

    event Place(
        address maker,
        uint256 quantity,
        uint256 price,
        bool isBuyOrder
    );

    event Deposit(
        address maker,
        uint256 orderId,
        uint256 increasedQuantity
    );

    event Withdraw(
        address maker,
        uint256 quantity,
        uint256 price,
        bool isBuyOrder
    );

    event Take(
        address taker,
        address maker,
        uint256 quantity,
        uint256 price,
        bool isBuyOrder
    );
    event Borrow(
        address borrower,
        uint256 orderId,
        uint256 quantity,
        bool isBuyOrder
    );

    event Repay(
        address borrower,
        uint256 orderId,
        uint256 quantity,
        bool isBuyOrder
    );
}
