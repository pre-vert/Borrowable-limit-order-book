// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

interface IBook {

    /// @notice lets users place orders in the order book
    /// @dev Update ERC20 balances
    /// @param _quantity The quantity of assets deposited (quoteToken for buy orders, baseToken for sell orders)
    /// @param _price price of the buy or sell order
    /// @param _price price of the buy or sell paired order
    /// @param _isBuyOrder true for buy orders, false for sell orders

    function deposit(uint256 _quantity, uint256 _price, uint256 _pairedPrice, bool _isBuyOrder, bool _isBorrowable) external;

    /// @notice lets user partially or fully remove her order from the book
    ///         Only non-borrowed assets can be removed
    /// @param _removedOrderId id of the order to be removed
    /// @param _quantityToRemove desired quantity of assets removed
    
    function withdraw(uint256 _removedOrderId, uint256 _quantityToRemove) external;

    /// @notice Lets users borrow assets from orders (create or increase a borrowing position)
    ///         Borrowers need to place orders first on the other side of the book with enough assets
    ///         order is borrowable up to order's available assets or user's excess collateral
    /// @param _borrowedOrderId id of the order which assets are borrowed
    /// @param _borrowedQuantity quantity of assets borrowed from the order

    function borrow(uint256 _borrowedOrderId, uint256 _borrowedQuantity) external;

    /// @notice lets users decrease or close a borrowing position
    /// @param _positionId id of the order which assets are paid back
    /// @param _repaidQuantity quantity of assets paid back
    
    function repay(uint256 _positionId, uint256 _repaidQuantity) external;

    /// @notice Let users take limit orders, regardless orders' assets are borrowed or not
    ///         taking, even 0, liquidates:
    ///         - all positions borrowing from the order
    ///         - maker's own positions for 100% of the taken order which assets are collateral (transferred to contract)
    ///         net assets are used to fund a new order on the other side of the book at a pre-specified limit price
    /// @param _takenOrderId id of the order to be taken
    /// @param _takenQuantity quantity of assets taken from the order

    function take(uint256 _takenOrderId, uint256 _takenQuantity) external;

    // borrower's excess collateral must be zero or negative
    


    /// @notice If order is profitable, call take() with 0 capital, which liquidates all positions
    ///         Else, _liquidate() one borrowing position which excess collateral is zero or negative
    ///         only maker can liquidate position from his own order
    ///         If _liquidate, borrow is reduced for 100% of the position 
    ///         borrower's collateral is seized for 100% of the position at current price (price feed)
    ///         collateral assets are transferred to maker with a 2% fee
    /// @param _positionId id of the liquidated position

    function liquidate(uint256 _positionId) external;

    /// @notice let maker change limit price of her order
    /// @param _orderId id of the order id which price is changed
    
    function changeLimitPrice(uint256 _orderId, uint256 _price) external;

    /// @notice let maker change paired price of an order
    ///         _pairedPrice can be 0, in this case, is set to limit price +/- 10%
    /// @param _orderId is order id which paired price is changed
    
    function changePairedPrice(uint256 _orderId, uint256 _pairedPrice) external;

    /// @notice make order borrowable if _isBorrowable is true or non borrowable if false
    /// @param _orderId is order id which is made borrowable
    
    function changeBorrowable(uint256 _orderId, bool _isBorrowable) external;

    //** EVENTS **//

    event Deposit(
        address maker,
        uint256 quantity,
        uint256 price,
        uint256 pairedPrice,
        bool isBuyOrder,
        bool isBorrowable,
        uint256 orderId
    );

    event Withdraw(
        address maker,
        uint256 quantity,
        uint256 price,
        bool isBuyOrder,
        uint256 orderId
    );

    event Borrow(
        address borrower,
        uint256 positionId,
        uint256 quantity,
        bool isBuyOrder
    );

    event Repay(
        address borrower,
        uint256 positionId,
        uint256 quantity,
        bool isBuyOrder
    );

    event Take(
        address taker,
        uint256 orderId,
        address maker,
        uint256 quantity,
        uint256 price,
        bool isBuyOrder
    );

    event Liquidate(
        address maker,
        uint256 _positionId
    );

    event ChangeLimitPrice(
        uint256 _orderId,
        uint256 _price
    );

    event ChangePairedPrice(
        uint256 _orderId,
        uint256 _pairedPrice
    );

    event ChangeBorrowable(
        uint256 _orderId,
        bool _isBorrowable
    );

}