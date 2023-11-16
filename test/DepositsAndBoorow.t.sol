// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

/// @notice tests of aggegate lending and borrowing

import {Test, console} from "forge-std/Test.sol";
import {Setup} from "./Setup.sol";
import {MathLib, WAD} from "../lib/MathLib.sol";

contract DepositsAndBorrow is Setup {
    
    // Total assets increase after deposit buy order
    function test_TotalAssetsIncreaseAfterDepositBuyOrder() public {
        uint256 totalQuoteAssets = book.totalQuoteAssets();
        depositBuyOrder(acc[1], 2000, 90);
        assertEq(book.totalQuoteAssets(), totalQuoteAssets + 2000 * WAD);
    }

    // Total assets increase after seposit sell order
    function test_TotalAssetsIncreaseAfterDepositSellOrder() public {
        uint256 totalBaseAssets = book.totalBaseAssets();
        depositSellOrder(acc[1], 20, 110);
        assertEq(book.totalBaseAssets(), totalBaseAssets + 20 * WAD);
    }

    // Total assets decrease after withdraw buy order
    function test_TotalAssetsDecreaseAfterWithdrawBuyOrder() public {
        depositBuyOrder(acc[1], 2000, 90);
        uint256 totalQuoteAssets = book.totalQuoteAssets();
        withdraw(acc[1], 1, 1000);
        assertEq(book.totalQuoteAssets(), totalQuoteAssets - 1000 * WAD);
    }

    // Total assets decrease after withdraw sell order
    function test_TotalAssetsDecreaseAfterWithdrawSellOrder() public {
        depositSellOrder(acc[1], 20, 110);
        uint256 totalBaseAssets = book.totalBaseAssets();
        withdraw(acc[1], 1, 10);
        assertEq(book.totalBaseAssets(), totalBaseAssets - 10 * WAD);
    }

    // Total borrow increase after borrow buy order
    function test_TotalBorrowIncreaseAfterBorrowBuyOrder() public {
        depositBuyOrder(acc[1], 2000, 90);
        depositSellOrder(acc[2], 30, 110);
        uint256 totalQuoteBorrow = book.totalQuoteBorrow();
        borrow(acc[2], 1, 1500);
        assertEq(book.totalQuoteBorrow(), totalQuoteBorrow + 1500 * WAD);
    }

    // Total borrow increase after borrow sell order
    function test_TotalBorrowIncreaseAfterBorrowSellOrder() public {
        depositSellOrder(acc[1], 20, 110);
        depositBuyOrder(acc[2], 3000, 90);
        uint256 totalBaseBorrow = book.totalBaseBorrow();
        borrow(acc[2], 1, 15);
        assertEq(book.totalBaseBorrow(), totalBaseBorrow + 15 * WAD);
    }

    // Total borrow decrease after borrow buy order
    function test_TotalBorrowDecreaseAfterRepayBuyOrder() public {
        depositBuyOrder(acc[1], 2000, 90);
        depositSellOrder(acc[2], 30, 110);
        borrow(acc[2], 1, 1500);
        uint256 totalQuoteBorrow = book.totalQuoteBorrow();
        repay(acc[2], 1, 1000);
        assertEq(book.totalQuoteBorrow(), totalQuoteBorrow - 1000 * WAD);
    }

    // Total borrow decrease after borrow sell order
    function test_TotalBorrowDecreaseAfterRepaySellOrder() public {
        depositSellOrder(acc[1], 20, 110);
        depositBuyOrder(acc[2], 3000, 90);
        borrow(acc[2], 1, 15);
        uint256 totalBaseBorrow = book.totalBaseBorrow();
        repay(acc[2], 1, 10);
        assertEq(book.totalBaseBorrow(), totalBaseBorrow - 10 * WAD);
    }

    // taking of buy order decreases total assets
    function test_TakeBuyOrderdecreaseTotalAssets() public {
        depositBuyOrder(acc[1], 1800, 90);
        uint256 totalQuoteAssets = book.totalQuoteAssets();
        take(acc[2], 1, 1800);
        assertEq(book.totalQuoteBorrow(), totalQuoteAssets - 1800 * WAD);
    }

    // taking of sell order decreases total assets
    function test_TakeSellOrderdecreaseTotalAssets() public {
        depositSellOrder(acc[1], 20, 110);
        uint256 totalBaseAssets = book.totalBaseAssets();
        take(acc[2], 1, 18);
        assertEq(book.totalBaseAssets(), totalBaseAssets - 18 * WAD);
    }

    // [2] borrows 2000 from [1], then [1] is partially taken => [2] is liquidated
    
    function test_TakeBuyOrderWithBorrowedAssets() public {
        depositBuyOrder(acc[1], 3000, 100); // + 3000 quote tokens assets
        depositSellOrder(acc[2], 30, 110); // + 30 base tokens assets
        borrow(acc[2], 1, 2000); // + 2000 quote tokens borrow
        uint256 totalQuoteAssets = book.totalQuoteAssets();
        uint256 totalBaseAssets = book.totalBaseAssets();
        uint256 totalQuoteBorrow = book.totalQuoteBorrow();
        uint256 totalBaseBorrow = book.totalBaseBorrow();
        take(acc[3], 1, 1000);
        assertEq(book.totalQuoteAssets(), totalQuoteAssets - 3000 * WAD); // quantity taken + liquidated
        assertEq(book.totalBaseAssets(), totalBaseAssets - 20 * WAD); // seized collateral
        assertEq(book.totalQuoteBorrow(), totalQuoteBorrow - 2000 * WAD);
        assertEq(book.totalBaseBorrow(), totalBaseBorrow);
    }

    // [2] borrows 20 from [1], then [1] is partially taken => [2] is liquidated
    
    function test_TakeSellOrderWithBorrowedAssets() public {
        depositSellOrder(acc[1], 30, 100); // + 30 base tokens assets
        depositBuyOrder(acc[2], 5000, 90); // + 5000 quote tokens assets
        borrow(acc[2], 1, 20); // + 20 base tokens borrow
        uint256 totalQuoteAssets = book.totalQuoteAssets();
        uint256 totalBaseAssets = book.totalBaseAssets();
        uint256 totalQuoteBorrow = book.totalQuoteBorrow();
        uint256 totalBaseBorrow = book.totalBaseBorrow();
        take(acc[3], 1, 10);
        assertEq(book.totalQuoteAssets(), totalQuoteAssets - 2000 * WAD); // seized collateral
        assertEq(book.totalBaseAssets(), totalBaseAssets - 30 * WAD); // quantity taken + liquidated
        assertEq(book.totalQuoteBorrow(), totalQuoteBorrow);
        assertEq(book.totalBaseBorrow(), totalBaseBorrow - 20 * WAD);
    }

    // Close borrowing position after taking a collateral buy order
    function test_ClosePositionFromBuyOrder() public {
        depositBuyOrder(acc[1], 2000, 90); // + 2000 quote tokens assets 
        depositSellOrder(acc[2], 10, 100); // + 10 base tokens assets
        borrow(acc[2], 1, 900); // + 900 quote tokens borrow 
        uint256 totalQuoteAssets = book.totalQuoteAssets();
        uint256 totalBaseAssets = book.totalBaseAssets();
        uint256 totalQuoteBorrow = book.totalQuoteBorrow();
        uint256 totalBaseBorrow = book.totalBaseBorrow();
        take(acc[3], 2, 10);
        assertEq(book.totalQuoteAssets(), totalQuoteAssets);
        assertEq(book.totalBaseAssets(), totalBaseAssets - 10 * WAD); // seized collateral
        assertEq(book.totalQuoteBorrow(), totalQuoteBorrow - 900 * WAD);
        assertEq(book.totalBaseBorrow(), totalBaseBorrow);
    }

    // Close borrowing position after taking a collateral sell order
    function test_ClosePositionFromSellOrder() public {
        depositSellOrder(acc[1], 20, 110); // + 20 base tokens assets 
        depositBuyOrder(acc[2], 5000, 100); // + 5000 quote tokens assets
        borrow(acc[2], 1, 10); // + 10 base tokens borrow 
        uint256 totalQuoteAssets = book.totalQuoteAssets();
        uint256 totalBaseAssets = book.totalBaseAssets();
        uint256 totalQuoteBorrow = book.totalQuoteBorrow();
        uint256 totalBaseBorrow = book.totalBaseBorrow();
        take(acc[3], 2, 5000);
        assertEq(book.totalQuoteAssets(), totalQuoteAssets - 5000 * WAD); // seized collateral
        assertEq(book.totalBaseAssets(), totalBaseAssets); 
        assertEq(book.totalQuoteBorrow(), totalQuoteBorrow);
        assertEq(book.totalBaseBorrow(), totalBaseBorrow - 10 * WAD);
    }


    
}
