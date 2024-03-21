// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

interface IBook {

    /// @notice lets users place orders in a pool
    /// @param _poolId id of pool in which user deposits
    /// @param _quantity The quantity of assets deposited (quoteToken for buy orders, baseToken for sell orders)
    /// @param _pairedPoolId id of pool in which the assets taken are reposted

    function deposit(uint256 _poolId, uint256 _quantity, uint256 _pairedPoolId) external;

    /// @notice lets user partially or fully remove her liquidity from the book
    ///         Only non-borrowed assets can be removed from pool
    /// @param _orderId id of pool from which assets are removed
    /// @param _removedQuantity desired quantity of assets removed
    
    function withdraw(uint256 _orderId, uint256 _removedQuantity) external;

    /// @notice Lets users borrow assets from pool (create or increase a borrowing position)
    ///         Borrowers need to place orders first on the other side of the book with enough assets
    ///         pool is borrowable up to pool's available assets or user's excess collateral
    /// @param _poolId id of the pool which assets are borrowed
    /// @param _quantity quantity of assets borrowed from the order

    function borrow(uint256 _poolId, uint256 _quantity) external;

    /// @notice lets users decrease or close a borrowing position
    /// @param _positionId id of position repaid by user
    /// @param _quantity quantity of assets paid back
    
    function repay(uint256 _positionId, uint256 _quantity) external;

    /// @param _poolId id of pool which available assets are taken
    /// @param _takenQuantity amount of quote assets received by taker in exchange of base assets

    function take(uint256 _poolId, uint256 _takenQuantity) external;

    /// @notice liquidate borrowing positions from users whose excess collateral is zero or negative
    ///         iterate on borrower's positions
    ///         cancel debt in quote tokens and seize an equivalent amount of deposits in base tokens at discount
    /// @param  _user borrower whose positions are liquidated
    /// @param _suppliedQuotes: quantity of quote assets supplied by liquidator in exchange of base collateral assets

    function liquidateUser(address _user, uint256 _suppliedQuotes) external;

    /// @notice let maker change limit price of her order
    /// @param _orderId id of order which limit price is changed
    /// @param _newPoolId id of pool with new limit price

    /// @notice let maker change limit price of her order
    /// @param _orderId id of order which paired limit price is changed
    /// @param _newPairedPoolId id of pool with new paired limit price
    
    function changePairedPrice(uint256 _orderId, uint256 _newPairedPoolId) external;

    //** EVENTS **//

    event Deposit(
        address maker,
        uint256 poolId,
        uint256 orderId,
        uint256 quantity,
        uint256 pairedPoolId
    );

    event Withdraw(
        uint256 orderId,
        uint256 quantity    
    );

    event Borrow(
        address borrower,
        uint256 poolId,
        uint256 positionId,
        uint256 quantity
    );

    event Repay(
        uint256 positionId,
        uint256 quantity
    );

    event Take(
        address taker,
        uint256 poolId,
        uint256 quantity,
        bool inQuote
    );

    event LiquidateBorrower(
        address borrower,
        uint256 reducedDebt
    );

    event ChangePairedPrice(
        uint256 orderId,
        uint256 newPairedPollId
    );
}