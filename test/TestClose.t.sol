// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Setup} from "./Setup.sol";
import {MathLib, WAD} from "../lib/MathLib.sol";

contract TestClose is Setup {

    // liquidate one position after taking a buy order, correctly adjusts balances
    // Alice (the contract) receives 500 / 100 = 5 BT from Carol, she (contract) gives Carol 500 QT
    // Bb is liquidated for 1000/100 = 10 BT
    // Alice's budget is 10 + 5 = 15 BT which is used for creating a sell order


    function test_LiquidatePositionFromBuyOrderOk() public {
        setPriceFeed(105);
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
        setPriceFeed(95);
        take(Carol, Alice_Order, 500);
        assertEq(quoteToken.balanceOf(OrderBook), bookQuoteBalance - 500 * WAD);
        assertEq(quoteToken.balanceOf(Alice), lenderQuoteBalance);
        assertEq(quoteToken.balanceOf(Bob), borrowerQuoteBalance);
        assertEq(quoteToken.balanceOf(Carol), takerQuoteBalance + 500 * WAD);
        assertEq(baseToken.balanceOf(OrderBook), bookBaseBalance + 5 * WAD);
        assertEq(baseToken.balanceOf(Alice), lenderBaseBalance); // + 15 * WAD);
        assertEq(baseToken.balanceOf(Bob), borrowerBaseBalance);
        assertEq(baseToken.balanceOf(Carol), takerBaseBalance - 5 * WAD);
        checkOrderQuantity(Alice_Order, 2000 - 1000 - 500);
        checkOrderQuantity(Bob_Order, 30 - 10);
        checkOrderQuantity(Alice_Order + 2, 15);
    }

    // liquidate one position after taking a sell order, correctly adjusts balances
    // Carol takes 5 BT from Alice and gives her 500 QT
    // Bob's position is liquidated for 2000 QT
    // Alice gets 2500 QT which are used to place a buy order
    // The contract gives Carol 5 BT and receives 500 QT which are kept in the new buy order

    function test_LiquidatePositionFromSellOrder() public {
        setPriceFeed(95);
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
        setPriceFeed(105);
        take(Carol, Alice_Order, 5);
        assertEq(baseToken.balanceOf(OrderBook), bookbaseBalance - 5 * WAD);
        assertEq(baseToken.balanceOf(Alice), lenderbaseBalance);
        assertEq(baseToken.balanceOf(Bob), borrowerbaseBalance);
        assertEq(baseToken.balanceOf(Carol), takerbaseBalance + 5 * WAD);
        assertEq(quoteToken.balanceOf(OrderBook), bookquoteBalance + 500 * WAD);
        assertEq(quoteToken.balanceOf(Alice), lenderquoteBalance); // + 2500 * WAD);
        assertEq(quoteToken.balanceOf(Bob), borrowerquoteBalance);
        assertEq(quoteToken.balanceOf(Carol), takerquoteBalance - 500 * WAD);
        checkOrderQuantity(Alice_Order, 30 - 25);
        checkOrderQuantity(Bob_Order, 5000 - 2000);
    }

    // liquidate one position after taking a buy order for zero quantity, correctly adjusts balances
    // Alice receives (0 + 1000)/100 = 10 BT which are used to create a sell order

    function test_LiquidatePositionFromBuyOrderWithZero() public {
        setPriceFeed(105);
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
        setPriceFeed(95);
        take(Carol, Alice_Order, 0);
        assertEq(quoteToken.balanceOf(OrderBook), bookQuoteBalance);
        assertEq(quoteToken.balanceOf(Alice), lenderQuoteBalance);
        assertEq(quoteToken.balanceOf(Bob), borrowerQuoteBalance);
        assertEq(quoteToken.balanceOf(Carol), takerQuoteBalance);
        assertEq(baseToken.balanceOf(OrderBook), bookBaseBalance); // - 10 * WAD);
        assertEq(baseToken.balanceOf(Alice), lenderBaseBalance); // + 10 * WAD);
        assertEq(baseToken.balanceOf(Bob), borrowerBaseBalance);
        assertEq(baseToken.balanceOf(Carol), takerBaseBalance);
        checkOrderQuantity(Alice_Order, 2000 - 1000);
        checkOrderQuantity(Bob_Order, 30 - 10);
        checkOrderQuantity(Alice_Order + 2, 10);
    }
    
    // liquidate two positions after taking a buy order, correctly adjusts balances
    // Alice receives (1000 + 400 + 600)/100 = 20 BT, which are used to create a sell order

    function test_LiquidateTwoPositionsFromBuyOrder() public {
        setPriceFeed(105);
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
        setPriceFeed(95);
        take(Dave, Alice_Order, 1000);
        assertEq(quoteToken.balanceOf(OrderBook), bookQuoteBalance - 1000 * WAD);
        assertEq(quoteToken.balanceOf(Dave), takerQuoteBalance + 1000 * WAD);
        assertEq(quoteToken.balanceOf(Alice), lenderQuoteBalance);
        assertEq(quoteToken.balanceOf(Bob), borrower1QuoteBalance);
        assertEq(quoteToken.balanceOf(Carol), borrower2QuoteBalance);
        assertEq(baseToken.balanceOf(OrderBook), bookBaseBalance + 10 * WAD); 
        assertEq(baseToken.balanceOf(Alice), lenderBaseBalance); // + 20 * WAD);
        assertEq(baseToken.balanceOf(Bob), borrower1BaseBalance);
        assertEq(baseToken.balanceOf(Carol), borrower2BaseBalance);
        assertEq(baseToken.balanceOf(Dave), takerBaseBalance - 10 * WAD);
        checkOrderQuantity(Alice_Order, 0);
        checkOrderQuantity(Bob_Order, 30 - 4);
        checkOrderQuantity(Carol_Order, 40 - 6);
        //checkOrderQuantity(Carol_Order + 3, 20);
    }

    // liquidate two positions after taking a sell order, balances
    // Dave takes 5 BT from Alice's order and gives her 500 QT
    // Bob and Carol's positions are liquidated for 700 and 800 QT respectively
    // Alice gets 2000 QT which are used to place a buy order

    function test_LiquidateTwoPositionsFromSellOrder() public {
        setPriceFeed(95);
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
        setPriceFeed(105);
        take(Dave, Alice_Order, 5);
        assertEq(baseToken.balanceOf(OrderBook), bookBaseBalance - 5 * WAD);
        assertEq(baseToken.balanceOf(Alice), lenderBaseBalance);
        assertEq(baseToken.balanceOf(Bob), borrower1BaseBalance);
        assertEq(baseToken.balanceOf(Carol), borrower2BaseBalance);
        assertEq(baseToken.balanceOf(Dave), takerBaseBalance + 5 * WAD);
        assertEq(quoteToken.balanceOf(OrderBook), bookQuoteBalance + 500 * WAD); // - 1500 * WAD);
        assertEq(quoteToken.balanceOf(Alice), lenderQuoteBalance); // + 2000 * WAD);
        assertEq(quoteToken.balanceOf(Bob), borrower1QuoteBalance);
        assertEq(quoteToken.balanceOf(Carol), borrower2QuoteBalance);
        assertEq(quoteToken.balanceOf(Dave), takerQuoteBalance - 500 * WAD);
        checkOrderQuantity(Alice_Order, 0);
        checkOrderQuantity(Bob_Order, 3000 - 700);
        checkOrderQuantity(Carol_Order, 4000 - 800);
        checkOrderQuantity(Alice_Order + 3, 2000);
    }

    // Close borrowing position after taking a collateral buy order, correctly adjusts balances
    // Bob receives 10 ETH against 1000 USDC, from which 900 is used to close his borrowing
    // Remains 100 USDC which are used to place a buy order
    // The contract keeps 900 USDC as loan pay back + 100 USDC as new order
    // Bob's sell order is closed but gest a buy order in return

    function test_ClosePositionFromBuyOrder() public {
        setPriceFeed(95);
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
        assertEq(quoteToken.balanceOf(OrderBook), bookQuoteBalance + (900 + 100) * WAD);
        assertEq(quoteToken.balanceOf(Bob), borrowerQuoteBalance);
        assertEq(quoteToken.balanceOf(Alice), lenderQuoteBalance);
        assertEq(quoteToken.balanceOf(Carol), takerQuoteBalance - 1000 * WAD);
        checkOrderQuantity(Alice_Order, 2000);
        checkOrderQuantity(Bob_Order, 0);
        checkOrderQuantity(Bob_Order + 1, 100);
        checkOrderMaker(Alice_Order, Alice);
        checkOrderMaker(Bob_Order, Bob);
        checkOrderMaker(Bob_Order + 1, Bob);
        assertEq(book.countOrdersOfUser(Alice), 1);
        assertEq(book.countOrdersOfUser(Bob), 1);
    }

    // Close two borrowing positions after taking a collateral buy order, correctly adjusts balances
    function test_TakeOrderWithTwoPositionsFromBuyOrder() public {
        setPriceFeed(95);
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
        setPriceFeed(105);
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
    // Bob receives 25*100 = 2500 from Carol, from which 900 + 800 = 1700 is used to close his borrowings
    // He's left with 800 USDC which are used to place a buy order
    // The contract gives Carol 25 BT and keeps the 2500, 1700 USDC as loan pay back + 800 USDC as new order

    function test_CloseTwoPositionsFromBuyOrder() public {
        setPriceFeed(95);
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
        setPriceFeed(105);
        take(Carol, Bob_Order + 1, 25);
        assertEq(baseToken.balanceOf(OrderBook), bookBaseBalance - 25 * WAD);
        assertEq(baseToken.balanceOf(Bob), borrowerBaseBalance);
        assertEq(baseToken.balanceOf(Alice), lenderBaseBalance);
        assertEq(baseToken.balanceOf(Carol), takerBaseBalance + 25 * WAD);
        assertEq(quoteToken.balanceOf(OrderBook), bookQuoteBalance + 2500 * WAD);
        assertEq(quoteToken.balanceOf(Bob), borrowerQuoteBalance);
        assertEq(quoteToken.balanceOf(Alice), lenderQuoteBalance);
        assertEq(quoteToken.balanceOf(Carol), takerQuoteBalance - 2500 * WAD);
        checkOrderQuantity(Alice_Order, 1800);
        checkOrderQuantity(Alice_Order + 1, 1600);
        checkOrderQuantity(Bob_Order + 1, 0);
        checkOrderQuantity(Bob_Order + 2, 800);
        checkBorrowingQuantity(1, 0);
        checkBorrowingQuantity(2, 0);
    }

    // Close one over two borrowing positions after taking a collateral buy order, correctly adjusts balances
    // Bob has a budget of 15*100 = 1500 USDC to reduce his borrowings, first 900, then 600 from 800
    // this means that Bob gets nothing from the take, only closes 1 position and a half

    function test_CloseOneOverTwoPositionsFromBuyOrder() public {
        depositBuyOrder(Alice, 1800, 90);
        depositBuyOrder(Alice, 1600, 80);
        setPriceFeed(95);
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
        setPriceFeed(105);
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
    // Liquidate assets: take 10 * 100 QT from Carol, transfer 1000 QT to Bob
    // Taker gives Bob 10 * 100 = 1000 QT, takes 10 BT from Bob
    // Bob has no more base tokens to collateralize his borrow, which is closed:
    // Bob gets 20 * 100 - 900 = 1100 QT which are used to create a new buy order

    function test_ClosePositionsFromTwoSides() public {
        setPriceFeed(95);
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
        setPriceFeed(105);
        take(Dave, Bob_Order, 10);
        assertEq(baseToken.balanceOf(OrderBook), bookBaseBalance - 10 * WAD);
        assertEq(baseToken.balanceOf(Alice), lenderBaseBalance);
        assertEq(baseToken.balanceOf(Bob), user2BaseBalance);
        assertEq(baseToken.balanceOf(Carol), borrowerBaseBalance);
        assertEq(baseToken.balanceOf(Dave), takerBaseBalance + 10 * WAD);
        assertEq(quoteToken.balanceOf(OrderBook), bookQuoteBalance + (1100 - 1000 + 900) * WAD);
        assertEq(quoteToken.balanceOf(Alice), lenderQuoteBalance);
        assertEq(quoteToken.balanceOf(Bob), user2QuoteBalance);
        assertEq(quoteToken.balanceOf(Carol), borrowerQuoteBalance);
        assertEq(quoteToken.balanceOf(Dave), takerQuoteBalance - 1000 * WAD);
        checkOrderQuantity(Alice_Order, 2700);
        checkOrderQuantity(Bob_Order, 0);
        checkOrderQuantity(Carol_Order, 3200 - 1000);
        checkOrderQuantity(Bob_Order + 2, 1100);
    }

    function test_ClosePositionFromTwoSidesWithZeroTaken() public {
        setPriceFeed(95);
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
        setPriceFeed(105);
        take(Dave, Bob_Order, 0);
        assertEq(baseToken.balanceOf(OrderBook), bookBaseBalance);
        assertEq(baseToken.balanceOf(Alice), lenderBaseBalance);
        assertEq(baseToken.balanceOf(Bob), user2BaseBalance);
        assertEq(baseToken.balanceOf(Carol), borrowerBaseBalance);
        assertEq(baseToken.balanceOf(Dave), takerBaseBalance);
        assertEq(quoteToken.balanceOf(OrderBook), bookQuoteBalance); // - (1000 - 900) * WAD);
        assertEq(quoteToken.balanceOf(Alice), lenderQuoteBalance);
        assertEq(quoteToken.balanceOf(Bob), user2QuoteBalance); // + (1000 - 900) * WAD);
        assertEq(quoteToken.balanceOf(Carol), borrowerQuoteBalance);
        assertEq(quoteToken.balanceOf(Dave), takerQuoteBalance);
        checkOrderQuantity(Alice_Order, 2700);
        checkOrderQuantity(Bob_Order, 10);
        checkOrderQuantity(Carol_Order, 3200 - 1000);
    }

    // maker cross-borrows her own orders, then is liquidated
    // buy order taken: Book gives taker 540 QT
    // Alice is liquidated for her borrow of 900: transfers 900/90 = 10 to maker
    // budget to deleverage: 540/90 (take) + 10 (liquidate) = 16 base tokens
    // max deleveraging on her second position = 10: second borrowing fully closed
    // the difference 16 - 10 = 6 is used to create a sell order

    function test_MakerCrossBorrowsHerOrdersThenLiquidated() public {
        setPriceFeed(95);
        depositBuyOrder(Alice, 3600, 90);
        depositSellOrder(Alice, 60, 100);
        borrow(Alice, Alice_Order, 900);
        borrow(Alice, Alice_Order + 1, 10);
        uint256 bookQuoteBalance = quoteToken.balanceOf(OrderBook);
        uint256 lenderBorrowerQuoteBalance = quoteToken.balanceOf(Alice);
        uint256 bookBaseBalance = baseToken.balanceOf(OrderBook);
        uint256 lenderBorrowerBaseBalance = baseToken.balanceOf(Alice);
        uint256 takerQuoteBalance = quoteToken.balanceOf(Bob);
        setPriceFeed(80);
        take(Bob, Alice_Order, 540);
        assertEq(quoteToken.balanceOf(OrderBook), bookQuoteBalance - 540 * WAD);
        assertEq(quoteToken.balanceOf(Bob), takerQuoteBalance + 540 * WAD);
        assertEq(quoteToken.balanceOf(Alice), lenderBorrowerQuoteBalance);
        assertEq(baseToken.balanceOf(OrderBook), bookBaseBalance + 6 * WAD);
        assertEq(baseToken.balanceOf(Alice), lenderBorrowerBaseBalance);
        checkOrderQuantity(Alice_Order, 3600 - 900 - 540); // 
        checkOrderQuantity(Alice_Order + 1, 60 - 10);
        checkOrderQuantity(Alice_Order + 2, 6);
        checkBorrowingQuantity(1, 0);
        checkBorrowingQuantity(2, 0);
    }

    // maker loop-borrows her own orders, correctly adjusts balances
    // buy order taken: Bob receives 900 QT, Alice receives 900/90 = 10 BT
    // Alice borrow is liquidated for 1800: transfers 1800/90 = 20 to maker (herself)
    // budget to deleverage: 10 (take) + 20 (liquidate) = 30 base tokens
    // no deleveraging => a sell order is created for 30

    function test_MakerLoopBorrowsHerOrdersThenLiquidated() public {
        setPriceFeed(95);
        depositBuyOrder(Alice, 900 + 1800, 90);
        depositSellOrder(Alice, 60, 100);
        borrow(Alice, Alice_Order, 1800);
        // depositBuyOrder(Alice, 1800, 90);
        uint256 bookQuoteBalance = quoteToken.balanceOf(OrderBook);
        uint256 lenderBorrowerQuoteBalance = quoteToken.balanceOf(Alice);
        uint256 takerQuoteBalance = quoteToken.balanceOf(Bob);
        uint256 bookBaseBalance = baseToken.balanceOf(OrderBook);
        uint256 lenderBorrowerBaseBalance = baseToken.balanceOf(Alice);
        uint256 takerBaseBalance = baseToken.balanceOf(Bob);
        setPriceFeed(80);
        take(Bob, Alice_Order, 900);
        setPriceFeed(80);
        assertEq(quoteToken.balanceOf(OrderBook), bookQuoteBalance - 900 * WAD);
        assertEq(quoteToken.balanceOf(Alice), lenderBorrowerQuoteBalance + (-1800 + 1800) * WAD);
        assertEq(quoteToken.balanceOf(Bob), takerQuoteBalance + 900 * WAD);
        assertEq(baseToken.balanceOf(OrderBook), bookBaseBalance + 10 * WAD); // - 30 * WAD
        assertEq(baseToken.balanceOf(Alice), lenderBorrowerBaseBalance); // + 30 * WAD);
        assertEq(baseToken.balanceOf(Bob), takerBaseBalance - 10 * WAD);
        checkOrderQuantity(Alice_Order, 900 + 1800 - 1800 - 900);
        checkOrderQuantity(Alice_Order + 1, 60 - 20);
        checkOrderQuantity(Alice_Order + 2, 30);
        checkBorrowingQuantity(Alice_Position, 0);
    }
}
