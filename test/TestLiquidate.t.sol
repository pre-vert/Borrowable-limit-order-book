// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Setup} from "./Setup.sol";
import {MathLib, WAD} from "../lib/MathLib.sol";

contract TestLiquidate is Setup {

    function test_LiquidateBuyFailsIfPositionDoesntExist() public {
        depositBuyOrder(Alice, 6000, 50);
        depositSellOrder(Bob, 100, 200);
        borrow(Bob, Alice_Order, 5000);
        setPriceFeed(100);
        vm.expectRevert("Borrowing position does not exist");
        liquidate(Alice, Carol_Position);
    }

    function test_LiquidateSellFailsIfPositionDoesntExist() public {
        depositSellOrder(Alice, 60, 200);
        depositBuyOrder(Bob, 10000, 50);
        borrow(Bob, Alice_Order, 50);
        setPriceFeed(100);
        vm.expectRevert("Borrowing position does not exist");
        liquidate(Alice, Carol_Position);
    }

    // only maker can liquidate buy order
    function test_LiquidateBuyFailsIfNotMaker() public {
        depositBuyOrder(Alice, 6000, 50);
        depositSellOrder(Bob, 100, 200);
        borrow(Bob, Alice_Order, 5000);
        setPriceFeed(100);
        vm.expectRevert("Only maker can remove order");
        liquidate(Carol, Bob_Position);
    }

    // only maker can liquidate sell order
    function test_LiquidateSellFailsIfNotMaker() public {
        depositSellOrder(Alice, 60, 200);
        depositBuyOrder(Bob, 10000, 50);
        borrow(Bob, Alice_Order, 50);
        setPriceFeed(100);
        vm.expectRevert("Only maker can remove order");
        liquidate(Carol, Bob_Position);
    }

    // only borrower of buy order with excess collateral <= 0 can be liquidated
    function test_LiquidateBuyFailsIfExcessCollateralIsPositive() public {
        depositBuyOrder(Alice, 6000, 50);
        depositSellOrder(Bob, 81, 200);
        borrow(Bob, Alice_Order, 4000);
        setPriceFeed(100);
        vm.expectRevert("Borrower's excess collateral is positive");
        liquidate(Alice, Bob_Position);
    }

    // only borrower of sell order with excess collateral <= 0 can be liquidated
    function test_LiquidateSellFailsIfExcessCollateralIsPositive() public {
        depositSellOrder(Alice, 60, 200);
        depositBuyOrder(Bob, 1001, 50);
        borrow(Bob, Alice_Order, 5);
        setPriceFeed(100);
        vm.expectRevert("Borrower's excess collateral is positive");
        liquidate(Alice, Bob_Position);
    }

    // Liquidate position calls take() if buy order is profitable
    // Alice's buy order is taken for 0 by herself: all positions are fully liquidated for 0 fee
    // Bob's and Carol's collateral is transferred to Alice's wallet for (3000 + 2000)/50 = 100 base tokens

    function test_LiquidateBuyIsTakeIfProfitable() public {
        depositBuyOrder(Alice, 6000, 50);
        depositSellOrder(Bob, 60, 200);
        depositSellOrder(Carol, 50, 180);
        borrow(Bob, Alice_Order, 3000);
        borrow(Carol, Alice_Order, 2000);
        uint256 contractQuoteBalance = quoteToken.balanceOf(OrderBook);
        uint256 contractBaseBalance = baseToken.balanceOf(OrderBook);
        uint256 makerQuoteBalance = quoteToken.balanceOf(Alice);
        uint256 makerBaseBalance = baseToken.balanceOf(Alice);
        uint256 borrowerQuoteBalance = quoteToken.balanceOf(Bob);
        uint256 borrowerBaseBalance = baseToken.balanceOf(Bob);
        uint256 borrower2QuoteBalance = quoteToken.balanceOf(Carol);
        uint256 borrower2BaseBalance = baseToken.balanceOf(Carol);
        setPriceFeed(40);
        liquidate(Alice, Bob_Position);
        assertEq(quoteToken.balanceOf(OrderBook), contractQuoteBalance);
        assertEq(baseToken.balanceOf(OrderBook), contractBaseBalance - 100 * WAD);
        assertEq(quoteToken.balanceOf(Alice), makerQuoteBalance);
        assertEq(baseToken.balanceOf(Alice), makerBaseBalance + 100 * WAD);
        assertEq(quoteToken.balanceOf(Bob), borrowerQuoteBalance);
        assertEq(baseToken.balanceOf(Bob), borrowerBaseBalance);
        assertEq(quoteToken.balanceOf(Carol), borrower2QuoteBalance);
        assertEq(baseToken.balanceOf(Carol), borrower2BaseBalance);
    }

    // Liquidate position calls take() if sell order is profitable
    function test_LiquidateSellIsTakeIfProfitable() public {
        depositSellOrder(Alice, 100, 200);
        depositBuyOrder(Bob, 9000, 50);
        depositBuyOrder(Carol, 8000, 50);
        borrow(Bob, Alice_Order, 30);
        borrow(Carol, Alice_Order, 40);
        uint256 contractQuoteBalance = quoteToken.balanceOf(OrderBook);
        uint256 contractBaseBalance = baseToken.balanceOf(OrderBook);
        uint256 makerQuoteBalance = quoteToken.balanceOf(Alice);
        uint256 makerBaseBalance = baseToken.balanceOf(Alice);
        uint256 borrowerQuoteBalance = quoteToken.balanceOf(Bob);
        uint256 borrowerBaseBalance = baseToken.balanceOf(Bob);
        uint256 borrower2QuoteBalance = quoteToken.balanceOf(Carol);
        uint256 borrower2BaseBalance = baseToken.balanceOf(Carol);
        setPriceFeed(210);
        liquidate(Alice, Carol_Position);
        assertEq(quoteToken.balanceOf(OrderBook), contractQuoteBalance - (8000 + 6000) * WAD);
        assertEq(baseToken.balanceOf(OrderBook), contractBaseBalance);
        assertEq(quoteToken.balanceOf(Alice), makerQuoteBalance + (8000 + 6000) * WAD);
        assertEq(baseToken.balanceOf(Alice), makerBaseBalance);
        assertEq(quoteToken.balanceOf(Bob), borrowerQuoteBalance);
        assertEq(baseToken.balanceOf(Bob), borrowerBaseBalance);
        assertEq(quoteToken.balanceOf(Carol), borrower2QuoteBalance);
        assertEq(baseToken.balanceOf(Carol), borrower2BaseBalance);
    }

    // liquidate borrow buy order:
    // - Bob must pay back 5000 + 2% fee rate = 5100 quote tokens
    // - At market price of 100, this means the transfer of 51 base tokens from Bob to Alice's wallet

    function test_LiquidateBorrowPositionFromBuy() public {
        depositBuyOrder(Alice, 6000, 50);
        depositSellOrder(Bob, 100, 200);
        borrow(Bob, Alice_Order, 5000);
        // checkInstantRate(BuyOrder);
        // checkInstantRate(SellOrder);
        uint256 contractQuoteBalance = quoteToken.balanceOf(OrderBook);
        uint256 contractBaseBalance = baseToken.balanceOf(OrderBook);
        uint256 makerQuoteBalance = quoteToken.balanceOf(Alice);
        uint256 makerBaseBalance = baseToken.balanceOf(Alice);
        uint256 borrowerQuoteBalance = quoteToken.balanceOf(Bob);
        uint256 borrowerBaseBalance = baseToken.balanceOf(Bob);
        setPriceFeed(100);
        liquidate(Alice, Bob_Position);
        assertEq(quoteToken.balanceOf(OrderBook), contractQuoteBalance);
        assertEq(baseToken.balanceOf(OrderBook), contractBaseBalance - 51 * WAD);
        assertEq(quoteToken.balanceOf(Alice), makerQuoteBalance);
        assertEq(baseToken.balanceOf(Alice), makerBaseBalance + 51 * WAD);
        assertEq(quoteToken.balanceOf(Bob), borrowerQuoteBalance);
        assertEq(baseToken.balanceOf(Bob), borrowerBaseBalance);
    }

    // liquidate borrow sell order: Bob must pay back 30 + 2% fee rate = 30.6 quote tokens
    // At market price of 100, this means the transfer of 3060 quote tokens from Bob to Alice's wallet

    function test_LiquidateBorrowPositionFromSell() public {
        depositSellOrder(Alice, 100, 200);
        depositBuyOrder(Bob, 6000, 50);
        borrow(Bob, Alice_Order, 30);
        uint256 contractQuoteBalance = quoteToken.balanceOf(OrderBook);
        uint256 contractBaseBalance = baseToken.balanceOf(OrderBook);
        uint256 makerQuoteBalance = quoteToken.balanceOf(Alice);
        uint256 makerBaseBalance = baseToken.balanceOf(Alice);
        uint256 borrowerQuoteBalance = quoteToken.balanceOf(Bob);
        uint256 borrowerBaseBalance = baseToken.balanceOf(Bob);
        setPriceFeed(100);
        liquidate(Alice, Bob_Position);
        assertEq(quoteToken.balanceOf(OrderBook), contractQuoteBalance - 3060 * WAD);
        assertEq(baseToken.balanceOf(OrderBook), contractBaseBalance);
        assertEq(quoteToken.balanceOf(Alice), makerQuoteBalance + 3060 * WAD);
        assertEq(baseToken.balanceOf(Alice), makerBaseBalance);
        assertEq(quoteToken.balanceOf(Bob), borrowerQuoteBalance);
        assertEq(baseToken.balanceOf(Bob), borrowerBaseBalance);
    }

    // liquidate borrow buy order: Bob must pay back 4000 + 2% fee rate + 2*1.499% = 4200 quote tokens
    // At market price of 100, this means the transfer of 42 base tokens from Bob to Alice's wallet
    // Bob's collateral is only 41, which is actually transferred to Alice ¯\_(ツ)_/¯

    function test_LiquidateBorrowAndInterestFromBuy() public {
        depositBuyOrder(Alice, 6000, 99);
        depositSellOrder(Bob, 41, 200);
        borrow(Bob, Alice_Order, 4000);
        checkInstantRate(BuyOrder);
        checkInstantRate(SellOrder);
        uint256 contractBaseBalance = baseToken.balanceOf(OrderBook);
        uint256 makerBaseBalance = baseToken.balanceOf(Alice);
        setPriceFeed(100);
        vm.warp(2 * YEAR);
        liquidate(Alice, Bob_Position);
        assertEq(baseToken.balanceOf(OrderBook), contractBaseBalance - 41 * WAD);
        assertEq(baseToken.balanceOf(Alice), makerBaseBalance + 41 * WAD);
    }

    // liquidate borrow sell order:
    // - Bob must pay back 30 + 2% fee rate = 30.6 quote tokens
    // - At market price of 100, this means the transfer of 3060 quote tokens from Bob to Alice's wallet

    function test_LiquidateBorrowAndInterestFromSell() public {
        depositSellOrder(Alice, 100, 200);
        depositBuyOrder(Bob, 6000, 50);
        borrow(Bob, Alice_Order, 30);
        checkInstantRate(BuyOrder);
        checkInstantRate(SellOrder);
        setPriceFeed(100);
        liquidate(Alice, Bob_Position);
    }

}
