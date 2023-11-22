// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Setup} from "./Setup.sol";
import {MathLib, WAD} from "../lib/MathLib.sol";

contract TestLiquidate is Setup {

    // liquidate one position after taking a buy order, correctly adjusts balances
    function test_LiquidatePositionFromBuyOrder() public {
        depositBuyOrder(Alice, 2000, 100);
        depositSellOrder(Bob, 30, 110);
        borrow(Bob, Alice_Order, 1000);
        uint256 bookQuoteBalance = quoteToken.balanceOf(OrderBook);
        uint256 lenderQuoteBalance = quoteToken.balanceOf(Alice);
        uint256 borrowerQuoteBalance = quoteToken.balanceOf(Bob);
        uint256 takerQuoteBalance = quoteToken.balanceOf(Carol);
        uint256 bookBaseBalance = baseToken.balanceOf(OrderBook);
        uint256 takerBaseBalance = baseToken.balanceOf(Carol);
        uint256 lenderBaseBalance = baseToken.balanceOf(Alice);
        uint256 borrowerBaseBalance = baseToken.balanceOf(Bob);
        take(Carol, Alice_Order, 500);
        assertEq(quoteToken.balanceOf(OrderBook), bookQuoteBalance - 500 * WAD);
        assertEq(quoteToken.balanceOf(Alice), lenderQuoteBalance);
        assertEq(quoteToken.balanceOf(Bob), borrowerQuoteBalance);
        assertEq(quoteToken.balanceOf(Carol), takerQuoteBalance + 500 * WAD);
        assertEq(baseToken.balanceOf(OrderBook), bookBaseBalance - 10 * WAD);
        assertEq(baseToken.balanceOf(Alice), lenderBaseBalance + 15 * WAD);
        assertEq(baseToken.balanceOf(Bob), borrowerBaseBalance);
        assertEq(baseToken.balanceOf(Carol), takerBaseBalance - 5 * WAD);
        checkOrderQuantity(Alice_Order, 2000 - 1500);
        checkOrderQuantity(Bob_Order, 30 - 10);
    }

    // liquidate one position after taking a sell order, correctly adjusts balances
    function test_LiquidatePositionFromSellOrder() public {
        depositSellOrder(Alice, 30, 100);
        depositBuyOrder(Bob, 5000, 90);
        borrow(Bob, Alice_Order, 20);
        uint256 bookbaseBalance = baseToken.balanceOf(OrderBook);
        uint256 lenderbaseBalance = baseToken.balanceOf(Alice);
        uint256 borrowerbaseBalance = baseToken.balanceOf(Bob);
        uint256 takerbaseBalance = baseToken.balanceOf(Carol);
        uint256 bookquoteBalance = quoteToken.balanceOf(OrderBook);
        uint256 lenderquoteBalance = quoteToken.balanceOf(Alice);
        uint256 borrowerquoteBalance = quoteToken.balanceOf(Bob);
        uint256 takerquoteBalance = quoteToken.balanceOf(Carol);
        take(Carol, Alice_Order, 5);
        assertEq(baseToken.balanceOf(OrderBook), bookbaseBalance - 5 * WAD);
        assertEq(baseToken.balanceOf(Alice), lenderbaseBalance);
        assertEq(baseToken.balanceOf(Bob), borrowerbaseBalance);
        assertEq(baseToken.balanceOf(Carol), takerbaseBalance + 5 * WAD);
        assertEq(quoteToken.balanceOf(OrderBook), bookquoteBalance - 2000 * WAD);
        assertEq(quoteToken.balanceOf(Alice), lenderquoteBalance + 2500 * WAD);
        assertEq(quoteToken.balanceOf(Bob), borrowerquoteBalance);
        assertEq(quoteToken.balanceOf(Carol), takerquoteBalance - 500 * WAD);
        checkOrderQuantity(Alice_Order, 30 - 25);
        checkOrderQuantity(Bob_Order, 5000 - 2000);
    }

    // liquidate one position after taking a buy order for zero quantity, correctly adjusts balances
    function test_LiquidatePositionFromBuyOrderWithZero() public {
        depositBuyOrder(Alice, 2000, 100);
        depositSellOrder(Bob, 30, 110);
        borrow(Bob, Alice_Order, 1000);
        uint256 bookQuoteBalance = quoteToken.balanceOf(OrderBook);
        uint256 lenderQuoteBalance = quoteToken.balanceOf(Alice);
        uint256 borrowerQuoteBalance = quoteToken.balanceOf(Bob);
        uint256 takerQuoteBalance = quoteToken.balanceOf(Carol);
        uint256 bookBaseBalance = baseToken.balanceOf(OrderBook);
        uint256 lenderBaseBalance = baseToken.balanceOf(Alice);
        uint256 borrowerBaseBalance = baseToken.balanceOf(Bob);
        uint256 takerBaseBalance = baseToken.balanceOf(Carol);
        take(Carol, Alice_Order, 0);
        assertEq(quoteToken.balanceOf(OrderBook), bookQuoteBalance);
        assertEq(quoteToken.balanceOf(Alice), lenderQuoteBalance);
        assertEq(quoteToken.balanceOf(Bob), borrowerQuoteBalance);
        assertEq(quoteToken.balanceOf(Carol), takerQuoteBalance);
        assertEq(baseToken.balanceOf(OrderBook), bookBaseBalance - 10 * WAD);
        assertEq(baseToken.balanceOf(Alice), lenderBaseBalance + 10 * WAD);
        assertEq(baseToken.balanceOf(Bob), borrowerBaseBalance);
        assertEq(baseToken.balanceOf(Carol), takerBaseBalance);
        checkOrderQuantity(Alice_Order, 2000 - 1000);
        checkOrderQuantity(Bob_Order, 30 - 10);
    }
    
    // liquidate two positions after taking a buy order, correctly adjusts balances
    function test_LiquidateTwoPositionsFromBuyOrder() public {
        depositBuyOrder(Alice, 2000, 100);
        depositSellOrder(Bob, 30, 110);
        depositSellOrder(Carol, 40, 120);
        borrow(Bob, Alice_Order, 400);
        borrow(Carol, Alice_Order, 600);
        uint256 bookQuoteBalance = quoteToken.balanceOf(OrderBook);
        uint256 lenderQuoteBalance = quoteToken.balanceOf(Alice);
        uint256 borrower1QuoteBalance = quoteToken.balanceOf(Bob);
        uint256 borrower2QuoteBalance = quoteToken.balanceOf(Carol);
        uint256 takerQuoteBalance = quoteToken.balanceOf(Dave);
        uint256 bookBaseBalance = baseToken.balanceOf(OrderBook);
        uint256 lenderBaseBalance = baseToken.balanceOf(Alice);
        uint256 borrower1BaseBalance = baseToken.balanceOf(Bob);
        uint256 borrower2BaseBalance = baseToken.balanceOf(Carol);
        uint256 takerBaseBalance = baseToken.balanceOf(Dave);
        take(Dave, Alice_Order, 1000);
        assertEq(quoteToken.balanceOf(OrderBook), bookQuoteBalance - 1000 * WAD);
        assertEq(quoteToken.balanceOf(Alice), lenderQuoteBalance);
        assertEq(quoteToken.balanceOf(Bob), borrower1QuoteBalance);
        assertEq(quoteToken.balanceOf(Carol), borrower2QuoteBalance);
        assertEq(quoteToken.balanceOf(Dave), takerQuoteBalance + 1000 * WAD);
        assertEq(baseToken.balanceOf(OrderBook), bookBaseBalance - 10 * WAD); 
        assertEq(baseToken.balanceOf(Alice), lenderBaseBalance + 20 * WAD);
        assertEq(baseToken.balanceOf(Bob), borrower1BaseBalance);
        assertEq(baseToken.balanceOf(Carol), borrower2BaseBalance);
        assertEq(baseToken.balanceOf(Dave), takerBaseBalance - 10 * WAD);
        checkOrderQuantity(Alice_Order, 0);
        checkOrderQuantity(Bob_Order, 30 - 4);
        checkOrderQuantity(Carol_Order, 40 - 6);
    }

    // liquidate two positions after taking a sell order, balances
    function test_LiquidateTwoPositionsFromSellOrder() public {
        depositSellOrder(Alice, 20, 100);
        depositBuyOrder(Bob, 3000, 90);
        depositBuyOrder(Carol, 4000, 80);
        borrow(Bob, Alice_Order, 7);
        borrow(Carol, Alice_Order, 8);
        uint256 bookBaseBalance = baseToken.balanceOf(OrderBook);
        uint256 lenderBaseBalance = baseToken.balanceOf(Alice);
        uint256 borrower1BaseBalance = baseToken.balanceOf(Bob);
        uint256 borrower2BaseBalance = baseToken.balanceOf(Carol);
        uint256 takerBaseBalance = baseToken.balanceOf(Dave);
        uint256 bookQuoteBalance = quoteToken.balanceOf(OrderBook);
        uint256 lenderQuoteBalance = quoteToken.balanceOf(Alice);
        uint256 borrower1QuoteBalance = quoteToken.balanceOf(Bob);
        uint256 borrower2QuoteBalance = quoteToken.balanceOf(Carol);
        uint256 takerQuoteBalance = quoteToken.balanceOf(Dave);
        take(Dave, Alice_Order, 5);
        assertEq(baseToken.balanceOf(OrderBook), bookBaseBalance - 5 * WAD);
        assertEq(baseToken.balanceOf(Alice), lenderBaseBalance);
        assertEq(baseToken.balanceOf(Bob), borrower1BaseBalance);
        assertEq(baseToken.balanceOf(Carol), borrower2BaseBalance);
        assertEq(baseToken.balanceOf(Dave), takerBaseBalance + 5 * WAD);
        assertEq(quoteToken.balanceOf(OrderBook), bookQuoteBalance - 1500 * WAD);
        assertEq(quoteToken.balanceOf(Alice), lenderQuoteBalance + 2000 * WAD);
        assertEq(quoteToken.balanceOf(Bob), borrower1QuoteBalance);
        assertEq(quoteToken.balanceOf(Carol), borrower2QuoteBalance);
        assertEq(quoteToken.balanceOf(Dave), takerQuoteBalance - 500 * WAD);
        checkOrderQuantity(Alice_Order, 0);
        checkOrderQuantity(Bob_Order, 3000 - 700);
        checkOrderQuantity(Carol_Order, 4000 - 800);
    }

    // Close borrowing position after taking a collateral buy order, correctly adjusts balances
    function test_ClosePositionFromBuyOrder() public {
        depositBuyOrder(Alice, 2000, 90);
        depositSellOrder(Bob, 10, 100);
        borrow(Bob, Alice_Order, 900);
        uint256 bookBaseBalance = baseToken.balanceOf(OrderBook);
        uint256 borrowerBaseBalance = baseToken.balanceOf(Bob);
        uint256 lenderBaseBalance = baseToken.balanceOf(Alice);
        uint256 takerBaseBalance = baseToken.balanceOf(Carol);
        uint256 bookQuoteBalance = quoteToken.balanceOf(OrderBook);
        uint256 borrowerQuoteBalance = quoteToken.balanceOf(Bob);
        uint256 lenderQuoteBalance = quoteToken.balanceOf(Alice);
        uint256 takerQuoteBalance = quoteToken.balanceOf(Carol);
        take(Carol, Bob_Order, 10);
        assertEq(baseToken.balanceOf(OrderBook), bookBaseBalance - 10 * WAD);
        assertEq(baseToken.balanceOf(Bob), borrowerBaseBalance);
        assertEq(baseToken.balanceOf(Alice), lenderBaseBalance);
        assertEq(baseToken.balanceOf(Carol), takerBaseBalance + 10 * WAD);
        assertEq(quoteToken.balanceOf(OrderBook), bookQuoteBalance + 900 * WAD);
        assertEq(quoteToken.balanceOf(Bob), borrowerQuoteBalance + 1000 * WAD - 900 * WAD);
        assertEq(quoteToken.balanceOf(Alice), lenderQuoteBalance);
        assertEq(quoteToken.balanceOf(Carol), takerQuoteBalance - 1000 * WAD);
        checkOrderQuantity(1, 2000);
        checkOrderQuantity(2, 0);
    }

    // Close two borrowing positions after taking a collateral buy order, correctly adjusts balances
    function test_TakeOrderWithTwoPositionsFromBuyOrder() public {
        depositBuyOrder(Alice, 1800, 90);
        depositBuyOrder(Alice, 1600, 80);
        depositSellOrder(Bob, 25, 100);
        borrow(Bob, Alice_Order, 900);
        borrow(Bob, Alice_Order + 1, 800);
        uint256 bookBaseBalance = baseToken.balanceOf(OrderBook);
        uint256 borrowerBaseBalance = baseToken.balanceOf(Bob);
        uint256 lenderBaseBalance = baseToken.balanceOf(Alice);
        uint256 takerBaseBalance = baseToken.balanceOf(Carol);
        uint256 bookQuoteBalance = quoteToken.balanceOf(OrderBook);
        uint256 borrowerQuoteBalance = quoteToken.balanceOf(Bob);
        uint256 lenderQuoteBalance = quoteToken.balanceOf(Alice);
        uint256 takerQuoteBalance = quoteToken.balanceOf(Carol);
        take(Carol, Bob_Order + 1, 5);
        assertEq(baseToken.balanceOf(OrderBook), bookBaseBalance - 5 * WAD);
        assertEq(baseToken.balanceOf(Bob), borrowerBaseBalance);
        assertEq(baseToken.balanceOf(Alice), lenderBaseBalance);
        assertEq(baseToken.balanceOf(Carol), takerBaseBalance + 5 * WAD);
        assertEq(quoteToken.balanceOf(OrderBook), bookQuoteBalance + 500 * WAD);
        assertEq(quoteToken.balanceOf(Bob), borrowerQuoteBalance);
        assertEq(quoteToken.balanceOf(Alice), lenderQuoteBalance);
        assertEq(quoteToken.balanceOf(Carol), takerQuoteBalance - 500 * WAD);
        checkOrderQuantity(Alice_Order, 1800);
        checkOrderQuantity(Alice_Order + 1, 1600);
        checkOrderQuantity(Bob_Order + 1, 20);
        checkBorrowingQuantity(1, 400);
        checkBorrowingQuantity(2, 800);
    }

    // Close two borrowing positions after taking a collateral buy order, correctly adjusts balances
    function test_CloseTwoPositionsFromBuyOrder() public {
        depositBuyOrder(Alice, 1800, 90);
        depositBuyOrder(Alice, 1600, 80);
        depositSellOrder(Bob, 25, 100);
        borrow(Bob, Alice_Order, 900);
        borrow(Bob, Bob_Order, 800);
        uint256 bookBaseBalance = baseToken.balanceOf(OrderBook);
        uint256 borrowerBaseBalance = baseToken.balanceOf(Bob);
        uint256 lenderBaseBalance = baseToken.balanceOf(Alice);
        uint256 takerBaseBalance = baseToken.balanceOf(Carol);
        uint256 bookQuoteBalance = quoteToken.balanceOf(OrderBook);
        uint256 borrowerQuoteBalance = quoteToken.balanceOf(Bob);
        uint256 lenderQuoteBalance = quoteToken.balanceOf(Alice);
        uint256 takerQuoteBalance = quoteToken.balanceOf(Carol);
        take(Carol, Bob_Order + 1, 25);
        assertEq(baseToken.balanceOf(OrderBook), bookBaseBalance - 25 * WAD);
        assertEq(baseToken.balanceOf(Bob), borrowerBaseBalance);
        assertEq(baseToken.balanceOf(Alice), lenderBaseBalance);
        assertEq(baseToken.balanceOf(Carol), takerBaseBalance + 25 * WAD);
        assertEq(quoteToken.balanceOf(OrderBook), bookQuoteBalance + 1700 * WAD);
        assertEq(quoteToken.balanceOf(Bob), borrowerQuoteBalance + 2500 * WAD - 1700 * WAD);
        assertEq(quoteToken.balanceOf(Alice), lenderQuoteBalance);
        assertEq(quoteToken.balanceOf(Carol), takerQuoteBalance - 2500 * WAD);
        checkOrderQuantity(Alice_Order, 1800);
        checkOrderQuantity(Alice_Order + 1, 1600);
        checkOrderQuantity(Bob_Order + 1, 0);
        checkBorrowingQuantity(1, 0);
        checkBorrowingQuantity(2, 0);
    }

    // Close one over two borrowing positions after taking a collateral buy order, correctly adjusts balances
    // Bob has a budget of 15*100 = 1500 USDC to reduce his borrowings, first 900, then 600 from 800
    // this means that Bob gets nothing from the take, only closes 1 position and a half

    function test_CloseOneOverTwoPositionsFromBuyOrder() public {
        depositBuyOrder(Alice, 1800, 90);
        depositBuyOrder(Alice, 1600, 80);
        depositSellOrder(Bob, 25, 100);
        borrow(Bob, Alice_Order, 900);
        borrow(Bob, Alice_Order + 1, 800);
        uint256 bookBaseBalance = baseToken.balanceOf(OrderBook);
        uint256 borrowerBaseBalance = baseToken.balanceOf(Bob);
        uint256 lenderBaseBalance = baseToken.balanceOf(Alice);
        uint256 takerBaseBalance = baseToken.balanceOf(Carol);
        uint256 bookQuoteBalance = quoteToken.balanceOf(OrderBook);
        uint256 borrowerQuoteBalance = quoteToken.balanceOf(Bob);
        uint256 lenderQuoteBalance = quoteToken.balanceOf(Alice);
        uint256 takerQuoteBalance = quoteToken.balanceOf(Carol);
        take(Carol, Bob_Order + 1, 15);
        assertEq(baseToken.balanceOf(OrderBook), bookBaseBalance - 15 * WAD);
        assertEq(baseToken.balanceOf(Bob), borrowerBaseBalance);
        assertEq(baseToken.balanceOf(Alice), lenderBaseBalance);
         assertEq(baseToken.balanceOf(Carol), takerBaseBalance + 15 * WAD);
        assertEq(quoteToken.balanceOf(OrderBook), bookQuoteBalance + 1500 * WAD);
        assertEq(quoteToken.balanceOf(Bob), borrowerQuoteBalance);
        assertEq(quoteToken.balanceOf(Alice), lenderQuoteBalance);
        assertEq(quoteToken.balanceOf(Carol), takerQuoteBalance - 1500 * WAD);
        checkOrderQuantity(Alice_Order, 1800);
        checkOrderQuantity(Alice_Order + 1, 1600);
        checkOrderQuantity(Bob_Order + 1, 25 - 15);
        checkBorrowingQuantity(1, 0);
        checkBorrowingQuantity(2, 800 - 600);
    }

    // Close borrowing and borrowed position after taking a collateral buy order, correctly adjusts balances
    // Liquidate assets: take 10 * 100 quote tokens from [3], transfer 1000 to [2]
    // Taker gives [2] 10 * 100 quote tokens, takes 10 base tokens from [2]
    // [2] has no more base tokens to collateralize his borrow, which is closed:
    // [2] is transferred 20 * 100 - 900 = 1100 quote tokens

    function test_ClosePositionsFromTwoSides() public {
        depositBuyOrder(Alice, 2700, 90);
        depositSellOrder(Bob, 20, 100);
        depositBuyOrder(Carol, 3200, 80);
        borrow(Bob, Alice_Order, 900);
        borrow(Carol, Bob_Order, 10);
        uint256 bookBaseBalance = baseToken.balanceOf(OrderBook);
        uint256 lenderBaseBalance = baseToken.balanceOf(Alice);
        uint256 user2BaseBalance = baseToken.balanceOf(Bob);
        uint256 borrowerBaseBalance = baseToken.balanceOf(Carol);
        uint256 takerBaseBalance = baseToken.balanceOf(Dave);
        uint256 bookQuoteBalance = quoteToken.balanceOf(OrderBook);
        uint256 lenderQuoteBalance = quoteToken.balanceOf(Alice);
        uint256 user2QuoteBalance = quoteToken.balanceOf(Bob);
        uint256 borrowerQuoteBalance = quoteToken.balanceOf(Carol);
        uint256 takerQuoteBalance = quoteToken.balanceOf(Dave);
        take(Dave, Bob_Order, 10);
        assertEq(baseToken.balanceOf(OrderBook), bookBaseBalance - 10 * WAD);
        assertEq(baseToken.balanceOf(Alice), lenderBaseBalance);
        assertEq(baseToken.balanceOf(Bob), user2BaseBalance);
        assertEq(baseToken.balanceOf(Carol), borrowerBaseBalance);
        assertEq(baseToken.balanceOf(Dave), takerBaseBalance + 10 * WAD); // HERE
        assertEq(quoteToken.balanceOf(OrderBook), bookQuoteBalance - (1000 - 900) * WAD);
        assertEq(quoteToken.balanceOf(Alice), lenderQuoteBalance);
        assertEq(quoteToken.balanceOf(Bob), user2QuoteBalance + (2000 * WAD - 900 * WAD));
        assertEq(quoteToken.balanceOf(Carol), borrowerQuoteBalance);
        assertEq(quoteToken.balanceOf(Dave), takerQuoteBalance - 1000 * WAD);
        checkOrderQuantity(Alice_Order, 2700);
        checkOrderQuantity(Bob_Order, 0);
        checkOrderQuantity(Carol_Order, 3200 - 1000);
    }

    function test_ClosePositionsFromTwoSidesWithZeroTaken() public {
        depositBuyOrder(Alice, 2700, 90);
        depositSellOrder(Bob, 20, 100);
        depositBuyOrder(Carol, 3200, 80);
        borrow(Bob, Alice_Order, 900);
        borrow(Carol, Bob_Order, 10);
        uint256 bookBaseBalance = baseToken.balanceOf(OrderBook);
        uint256 lenderBaseBalance = baseToken.balanceOf(Alice);
        uint256 user2BaseBalance = baseToken.balanceOf(Bob);
        uint256 borrowerBaseBalance = baseToken.balanceOf(Carol);
        uint256 takerBaseBalance = baseToken.balanceOf(Dave);
        uint256 bookQuoteBalance = quoteToken.balanceOf(OrderBook);
        uint256 lenderQuoteBalance = quoteToken.balanceOf(Alice);
        uint256 user2QuoteBalance = quoteToken.balanceOf(Bob);
        uint256 borrowerQuoteBalance = quoteToken.balanceOf(Carol);
        uint256 takerQuoteBalance = quoteToken.balanceOf(Dave);
        take(Dave, Bob_Order, 0);
        assertEq(baseToken.balanceOf(OrderBook), bookBaseBalance);
        assertEq(baseToken.balanceOf(Alice), lenderBaseBalance);
        assertEq(baseToken.balanceOf(Bob), user2BaseBalance);
        assertEq(baseToken.balanceOf(Carol), borrowerBaseBalance);
        assertEq(baseToken.balanceOf(Dave), takerBaseBalance);
        assertEq(quoteToken.balanceOf(OrderBook), bookQuoteBalance - (1000 - 900) * WAD);
        assertEq(quoteToken.balanceOf(Alice), lenderQuoteBalance);
        assertEq(quoteToken.balanceOf(Bob), user2QuoteBalance + (1000 - 900) * WAD);
        assertEq(quoteToken.balanceOf(Carol), borrowerQuoteBalance);
        assertEq(quoteToken.balanceOf(Dave), takerQuoteBalance);
        checkOrderQuantity(Alice_Order, 2700);
        checkOrderQuantity(Bob_Order, 10);
        checkOrderQuantity(Carol_Order, 3200 - 1000);
    }

    // maker cross-borrows her own orders, then is liquidated
    // buy order is taken: Alice is liquidated for her borrowing of 900
    // her first borrowing is fully closed => transfers 900/90 = 10 to maker
    // budget to deleverage: 540/90 (take) + 10 (liquidate) = 16 base tokens
    // max deleveraging on her second position: 10 => her second borrowing is also fully closed
    // she takes back 16 - 10 = 6 in her wallet, sourced from taker
    // Book gives taker 540 quote tokens and Alice 10 base tokens

    function test_MakerCrossBorrowsHerOrdersThenLiquidated() public {
        depositBuyOrder(Alice, 3600, 90);
        depositSellOrder(Alice, 60, 100);
        borrow(Alice, Alice_Order, 900);
        borrow(Alice, Alice_Order + 1, 10);
        uint256 bookQuoteBalance = quoteToken.balanceOf(OrderBook);
        uint256 lenderBorrowerQuoteBalance = quoteToken.balanceOf(Alice);
        uint256 bookBaseBalance = baseToken.balanceOf(OrderBook);
        uint256 lenderBorrowerBaseBalance = baseToken.balanceOf(Alice);
        take(Bob, Alice_Order, 540);
        assertEq(quoteToken.balanceOf(OrderBook), bookQuoteBalance - 540 * WAD);
        assertEq(quoteToken.balanceOf(Alice), lenderBorrowerQuoteBalance);
        assertEq(baseToken.balanceOf(OrderBook), bookBaseBalance);
        assertEq(baseToken.balanceOf(Alice), lenderBorrowerBaseBalance + 6 * WAD);
        checkOrderQuantity(Alice_Order, 3600 - 900 - 540);
        checkOrderQuantity(Alice_Order + 1, 60 - 10);
        checkBorrowingQuantity(1, 0);
        checkBorrowingQuantity(2, 0);
    }

    // maker loop-borrows her own orders, correctly adjusts balances
    // buy order is taken: Alice is liquidated for her borrowing of 1800
    // borrowing fully closed: transfers 1800/90 = 20 to maker
    // budget to deleverage: 900/90 (take) + 20 (liquidate) = 30 base tokens
    // no deleveraging => she receives 30 in exchange of 1800 quote tokens

    function test_MakerLoopBorrowsHerOrdersThenLiquidated() public {
        depositBuyOrder(Alice, 4500, 90);
        depositSellOrder(Alice, 60, 100);
        borrow(Alice, Alice_Order, 1800);
        depositBuyOrder(Alice, 1800, 90);
        uint256 bookQuoteBalance = quoteToken.balanceOf(OrderBook);
        uint256 lenderBorrowerQuoteBalance = quoteToken.balanceOf(Alice);
        uint256 takerQuoteBalance = quoteToken.balanceOf(Bob);
        uint256 bookBaseBalance = baseToken.balanceOf(OrderBook);
        uint256 lenderBorrowerBaseBalance = baseToken.balanceOf(Alice);
        uint256 takerBaseBalance = baseToken.balanceOf(Bob);
        take(Bob, Alice_Order, 900);
        assertEq(quoteToken.balanceOf(OrderBook), bookQuoteBalance - 900 * WAD);
        assertEq(quoteToken.balanceOf(Alice), lenderBorrowerQuoteBalance);
        assertEq(quoteToken.balanceOf(Bob), takerQuoteBalance + 900 * WAD);
        assertEq(baseToken.balanceOf(OrderBook), bookBaseBalance - (30 - 10) * WAD); // - 30 * WAD
        assertEq(baseToken.balanceOf(Alice), lenderBorrowerBaseBalance + 30 * WAD);
        assertEq(baseToken.balanceOf(Bob), takerBaseBalance - 10 * WAD);
        checkOrderQuantity(Alice_Order, 4500 + 1800 - 1800 - 900);
        checkOrderQuantity(Alice_Order + 1, 60 - 20);
        checkBorrowingQuantity(1, 0);
    }
}
