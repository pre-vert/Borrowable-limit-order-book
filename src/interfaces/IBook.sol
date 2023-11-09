// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

interface IBook {

    /// @notice lets users place orders in the order book
    /// @dev Update ERC20 balances
    /// @param _quantity The quantity of assets deposited (quoteToken for buy orders, baseToken for sell orders)
    /// @param _price price of the buy or sell order
    /// @param _isBuyOrder true for buy orders, false for sell orders
    
    function deposit(uint256 _quantity, uint256 _price, bool _isBuyOrder) external;

    /// @notice lets user partially or fully remove her order from the book
    /// Only non-borrowed assets can be removed
    /// @param _removedOrderId id of the order to be removed
    /// @param _quantityToRemove desired quantity of assets removed
    
    function withdraw(uint256 _removedOrderId, uint256 _quantityToRemove) external;

    /// @notice Let users take limit orders, regardless the orders' assets are borrowed or not
    /// taking liquidates **all** borrowing positions even if taking is partial
    /// taking of a collateral order triggers the borrower's liquidation for enough assets
    /// @param _takenOrderId id of the order to be taken
    /// @param _takenQuantity quantity of assets taken from the order

    function take(uint256 _takenOrderId, uint256 _takenQuantity) external;

    /// @notice Lets users borrow assets from orders (create or increase TO DO a borrowing position)
    /// Borrowers need to place orders first on the other side of the book with enough assets
    /// order is borrowable up to order's available assets or user's excess collateral
    /// @param _borrowedOrderId id of the order which assets are borrowed
    /// @param _borrowedQuantity quantity of assets borrowed from the order

    function borrow(uint256 _borrowedOrderId, uint256 _borrowedQuantity) external;

    /// @notice lets users decrease or close a borrowing position
    /// @param _repaidOrderId id of the order which assets are paid back
    /// @param _repaidQuantity quantity of assets paid back
    
    function repay(uint256 _repaidOrderId, uint256 _repaidQuantity) external;

    // Events

    event Deposit(
        address maker,
        uint256 quantity,
        uint256 price,
        bool isBuyOrder
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
