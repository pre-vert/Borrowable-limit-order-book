// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Setup} from "./Setup.sol";
import {StdCheats} from "forge-std/StdCheats.sol";

contract TestLiquidate is Setup {

    // liquidate one position after taking a buy order, check balances
    function test_LiquidatePositionFromBuyOrder() public {
        depositBuyOrder(acc[1], 2000, 100);
        depositSellOrder(acc[2], 30, 110);
        borrow(acc[2], 1, 1000);
        uint256 bookQuoteBalance = quoteToken.balanceOf(address(book));
        uint256 lenderQuoteBalance = quoteToken.balanceOf(acc[1]);
        uint256 borrowerQuoteBalance = quoteToken.balanceOf(acc[2]);
        uint256 takerQuoteBalance = quoteToken.balanceOf(acc[3]);
        uint256 bookBaseBalance = baseToken.balanceOf(address(book));
        uint256 takerBaseBalance = baseToken.balanceOf(acc[3]);
        uint256 lenderBaseBalance = baseToken.balanceOf(acc[1]);
        uint256 borrowerBaseBalance = baseToken.balanceOf(acc[2]);
        take(acc[3], 1, 500);
        assertEq(quoteToken.balanceOf(address(book)), bookQuoteBalance - 500);
        assertEq(quoteToken.balanceOf(acc[1]), lenderQuoteBalance);
        assertEq(quoteToken.balanceOf(acc[2]), borrowerQuoteBalance);
        assertEq(quoteToken.balanceOf(acc[3]), takerQuoteBalance + 500);
        assertEq(baseToken.balanceOf(address(book)), bookBaseBalance - 10);
        assertEq(baseToken.balanceOf(acc[1]), lenderBaseBalance + 15);
        assertEq(baseToken.balanceOf(acc[2]), borrowerBaseBalance);
        assertEq(baseToken.balanceOf(acc[3]), takerBaseBalance - 5);
        checkOrderQuantity(1, 2000 - 1500);
        checkOrderQuantity(2, 30 - 10);
    }

    // liquidate one position after taking a sell order, check balances
    function test_LiquidatePositionFromSellOrder() public {
        depositSellOrder(acc[1], 30, 100);
        depositBuyOrder(acc[2], 5000, 90);
        borrow(acc[2], 1, 20);
        uint256 bookbaseBalance = baseToken.balanceOf(address(book));
        uint256 lenderbaseBalance = baseToken.balanceOf(acc[1]);
        uint256 borrowerbaseBalance = baseToken.balanceOf(acc[2]);
        uint256 takerbaseBalance = baseToken.balanceOf(acc[3]);
        uint256 bookquoteBalance = quoteToken.balanceOf(address(book));
        uint256 lenderquoteBalance = quoteToken.balanceOf(acc[1]);
        uint256 borrowerquoteBalance = quoteToken.balanceOf(acc[2]);
        uint256 takerquoteBalance = quoteToken.balanceOf(acc[3]);
        take(acc[3], 1, 5);
        assertEq(baseToken.balanceOf(address(book)), bookbaseBalance - 5);
        assertEq(baseToken.balanceOf(acc[1]), lenderbaseBalance);
        assertEq(baseToken.balanceOf(acc[2]), borrowerbaseBalance);
        assertEq(baseToken.balanceOf(acc[3]), takerbaseBalance + 5);
        assertEq(quoteToken.balanceOf(address(book)), bookquoteBalance - 2000);
        assertEq(quoteToken.balanceOf(acc[1]), lenderquoteBalance + 2500);
        assertEq(quoteToken.balanceOf(acc[2]), borrowerquoteBalance);
        assertEq(quoteToken.balanceOf(acc[3]), takerquoteBalance - 500);
        checkOrderQuantity(1, 30 - 25);
        checkOrderQuantity(2, 5000 - 2000);
    }

    // liquidate two positions after taking a buy order, check balances
    function test_LiquidateTwoPositionsFromBuyOrder() public {
        depositBuyOrder(acc[1], 2000, 100);
        depositSellOrder(acc[2], 30, 110);
        depositSellOrder(acc[3], 40, 120);
        borrow(acc[2], 1, 400);
        borrow(acc[3], 1, 600);
        uint256 bookQuoteBalance = quoteToken.balanceOf(address(book));
        uint256 lenderQuoteBalance = quoteToken.balanceOf(acc[1]);
        uint256 borrower1QuoteBalance = quoteToken.balanceOf(acc[2]);
        uint256 borrower2QuoteBalance = quoteToken.balanceOf(acc[3]);
        uint256 takerQuoteBalance = quoteToken.balanceOf(acc[4]);
        uint256 bookBaseBalance = baseToken.balanceOf(address(book));
        uint256 lenderBaseBalance = baseToken.balanceOf(acc[1]);
        uint256 borrower1BaseBalance = baseToken.balanceOf(acc[2]);
        uint256 borrower2BaseBalance = baseToken.balanceOf(acc[3]);
        uint256 takerBaseBalance = baseToken.balanceOf(acc[4]);
        take(acc[4], 1, 1000);
        assertEq(quoteToken.balanceOf(address(book)), bookQuoteBalance - 1000);
        assertEq(quoteToken.balanceOf(acc[1]), lenderQuoteBalance);
        assertEq(quoteToken.balanceOf(acc[2]), borrower1QuoteBalance);
        assertEq(quoteToken.balanceOf(acc[3]), borrower2QuoteBalance);
        assertEq(quoteToken.balanceOf(acc[4]), takerQuoteBalance + 1000);
        assertEq(baseToken.balanceOf(address(book)), bookBaseBalance - 10); // 2 * 500/100 of base collateral
        assertEq(baseToken.balanceOf(acc[1]), lenderBaseBalance + 20);
        assertEq(baseToken.balanceOf(acc[2]), borrower1BaseBalance);
        assertEq(baseToken.balanceOf(acc[3]), borrower2BaseBalance);
        assertEq(baseToken.balanceOf(acc[4]), takerBaseBalance - 10);
        checkOrderQuantity(1, 0);
        checkOrderQuantity(2, 30 - 4);
        checkOrderQuantity(3, 40 - 6);
    }

    // liquidate two positions after taking a sell order, balances
    function test_LiquidateTwoPositionsFromSellOrder() public {
        depositSellOrder(acc[1], 20, 100);
        depositBuyOrder(acc[2], 3000, 90);
        depositBuyOrder(acc[3], 4000, 80);
        borrow(acc[2], 1, 7);
        borrow(acc[3], 1, 8);
        uint256 bookBaseBalance = baseToken.balanceOf(address(book));
        uint256 lenderBaseBalance = baseToken.balanceOf(acc[1]);
        uint256 borrower1BaseBalance = baseToken.balanceOf(acc[2]);
        uint256 borrower2BaseBalance = baseToken.balanceOf(acc[3]);
        uint256 takerBaseBalance = baseToken.balanceOf(acc[4]);
        uint256 bookQuoteBalance = quoteToken.balanceOf(address(book));
        uint256 lenderQuoteBalance = quoteToken.balanceOf(acc[1]);
        uint256 borrower1QuoteBalance = quoteToken.balanceOf(acc[2]);
        uint256 borrower2QuoteBalance = quoteToken.balanceOf(acc[3]);
        uint256 takerQuoteBalance = quoteToken.balanceOf(acc[4]);
        take(acc[4], 1, 5);
        assertEq(baseToken.balanceOf(address(book)), bookBaseBalance - 5);
        assertEq(baseToken.balanceOf(acc[1]), lenderBaseBalance);
        assertEq(baseToken.balanceOf(acc[2]), borrower1BaseBalance);
        assertEq(baseToken.balanceOf(acc[3]), borrower2BaseBalance);
        assertEq(baseToken.balanceOf(acc[4]), takerBaseBalance + 5);
        assertEq(quoteToken.balanceOf(address(book)), bookQuoteBalance - 1500); // (7 + 8) * 100 of quote collateral
        assertEq(quoteToken.balanceOf(acc[1]), lenderQuoteBalance + 2000);
        assertEq(quoteToken.balanceOf(acc[2]), borrower1QuoteBalance);
        assertEq(quoteToken.balanceOf(acc[3]), borrower2QuoteBalance);
        assertEq(quoteToken.balanceOf(acc[4]), takerQuoteBalance - 500);
        checkOrderQuantity(1, 0);
        checkOrderQuantity(2, 3000 - 700);
        checkOrderQuantity(3, 4000 - 800);
    }

    // Close borrowing position after taking a collateral buy order, check balances
    function test_ClosePositionFromBuyOrder() public {
        depositBuyOrder(acc[1], 2000, 90);
        depositSellOrder(acc[2], 10, 100);
        borrow(acc[2], 1, 900);
        uint256 bookBaseBalance = baseToken.balanceOf(address(book));
        uint256 borrowerBaseBalance = baseToken.balanceOf(acc[2]);
        uint256 lenderBaseBalance = baseToken.balanceOf(acc[1]);
        uint256 takerBaseBalance = baseToken.balanceOf(acc[3]);
        uint256 bookQuoteBalance = quoteToken.balanceOf(address(book));
        uint256 borrowerQuoteBalance = quoteToken.balanceOf(acc[2]);
        uint256 lenderQuoteBalance = quoteToken.balanceOf(acc[1]);
        uint256 takerQuoteBalance = quoteToken.balanceOf(acc[3]);
        take(acc[3], 2, 10);
        assertEq(baseToken.balanceOf(address(book)), bookBaseBalance - 10);
        assertEq(baseToken.balanceOf(acc[2]), borrowerBaseBalance);
        assertEq(baseToken.balanceOf(acc[1]), lenderBaseBalance);
        assertEq(baseToken.balanceOf(acc[3]), takerBaseBalance + 10);
        assertEq(quoteToken.balanceOf(address(book)), bookQuoteBalance + 900);
        assertEq(quoteToken.balanceOf(acc[2]), borrowerQuoteBalance + 10 * 100 - 900);
        assertEq(quoteToken.balanceOf(acc[1]), lenderQuoteBalance);
        assertEq(quoteToken.balanceOf(acc[3]), takerQuoteBalance - 1000);
        checkOrderQuantity(1, 2000);
        checkOrderQuantity(2, 0);
    }

    // Close borrowing and borrowed position after taking a collateral buy order, check balances
    function test_ClosePositionsFromTwoSides() public {
        depositBuyOrder(acc[1], 2700, 90);
        depositSellOrder(acc[2], 20, 100);
        depositBuyOrder(acc[3], 3200, 80);
        borrow(acc[2], 1, 900);
        borrow(acc[3], 2, 10);
        uint256 bookBaseBalance = baseToken.balanceOf(address(book));
        uint256 lenderBaseBalance = baseToken.balanceOf(acc[1]);
        uint256 user2BaseBalance = baseToken.balanceOf(acc[2]);
        uint256 borrowerBaseBalance = baseToken.balanceOf(acc[3]);
        uint256 takerBaseBalance = baseToken.balanceOf(acc[4]);
        uint256 bookQuoteBalance = quoteToken.balanceOf(address(book));
        uint256 lenderQuoteBalance = quoteToken.balanceOf(acc[1]);
        uint256 user2QuoteBalance = quoteToken.balanceOf(acc[2]);
        uint256 borrowerQuoteBalance = quoteToken.balanceOf(acc[3]);
        uint256 takerQuoteBalance = quoteToken.balanceOf(acc[4]);
        take(acc[4], 2, 10);
        assertEq(baseToken.balanceOf(address(book)), bookBaseBalance - 10);
        assertEq(baseToken.balanceOf(acc[1]), lenderBaseBalance);
        assertEq(baseToken.balanceOf(acc[2]), user2BaseBalance);
        assertEq(baseToken.balanceOf(acc[3]), borrowerBaseBalance);
        assertEq(baseToken.balanceOf(acc[3]), takerBaseBalance + 10);
        assertEq(quoteToken.balanceOf(address(book)), bookQuoteBalance - 100);
        assertEq(quoteToken.balanceOf(acc[1]), lenderQuoteBalance);
        assertEq(quoteToken.balanceOf(acc[2]), user2QuoteBalance + 1100);
        assertEq(quoteToken.balanceOf(acc[3]), borrowerQuoteBalance);
        assertEq(quoteToken.balanceOf(acc[4]), takerQuoteBalance - 1000);
        checkOrderQuantity(1, 2700);
        checkOrderQuantity(2, 0);
        checkOrderQuantity(3, 3200 - 1000);
    }
}
