// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

interface IOrderBook {
    function placeOrder(
        uint256 _quantity,
        uint256 _price,
        bool _isBuyOrder
    ) external;

    function removeOrder(uint256 _removedId) external;

    function takeOrder(uint256 _takenId) external;

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
        address lender,
        uint256 quantity,
        uint256 price,
        bool isBuyOrder
    );
}
