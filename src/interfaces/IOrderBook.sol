// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

interface IOrderBook {
    function placeOrder(
        uint256 _quantity,
        uint256 _price,
        bool _isBuyOrder
    ) external;

    function removeOrder(uint256 _removedId, uint256 removedQuantity) external;

    function takeOrder(uint256 _takenId, uint256 takenQuantity) external;

    function borrowOrder(
        uint256 _borrowedId,
        uint256 borrowedQuantity
    ) external;

    function repayBorrowing(uint256 _repaidId, uint256 repaidQuantity) external;

    event PlaceOrder(
        address maker,
        uint256 quantity,
        uint256 price,
        bool isBuyOrder
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
