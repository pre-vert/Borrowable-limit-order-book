// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Setup} from "./Setup.sol";
import {StdCheats} from "forge-std/StdCheats.sol";

contract TestLiquidate is Setup {

    // liquidate one position after taking a buy order, check external balances
    function testLiquidateOnePositionFromBuyOrder() public {
        depositBuyOrder(acc[1], 2000, 100);
        depositSellOrder(acc[2], 30, 110);
        borrowOrder(acc[2], 1, 1000);
        uint256 bookQuoteBalance = quoteToken.balanceOf(address(book));
        uint256 lenderQuoteBalance = quoteToken.balanceOf(acc[1]);
        uint256 borrowerQuoteBalance = quoteToken.balanceOf(acc[2]);
        uint256 takerQuoteBalance = quoteToken.balanceOf(acc[3]);
        uint256 bookBaseBalance = baseToken.balanceOf(address(book));
        uint256 takerBaseBalance = baseToken.balanceOf(acc[3]);
        uint256 lenderBaseBalance = baseToken.balanceOf(acc[1]);
        uint256 borrowerBaseBalance = baseToken.balanceOf(acc[2]);
        vm.prank(acc[3]);
        book.take(1, 1000);
        assertEq(quoteToken.balanceOf(address(book)), bookQuoteBalance - 1000);
        assertEq(quoteToken.balanceOf(acc[1]), lenderQuoteBalance);
        assertEq(quoteToken.balanceOf(acc[2]), borrowerQuoteBalance);
        assertEq(quoteToken.balanceOf(acc[3]), takerQuoteBalance + 1000);
        assertEq(baseToken.balanceOf(address(book)), bookBaseBalance - 10);
        assertEq(baseToken.balanceOf(acc[1]), lenderBaseBalance + 20);
        assertEq(baseToken.balanceOf(acc[2]), borrowerBaseBalance);
        assertEq(baseToken.balanceOf(acc[3]), takerBaseBalance - 10);
    }

    // liquidate one position after taking a sell order, check external balances
    function testLiquidateOnePositionFromSellOrder() public {
        depositSellOrder(acc[1], 30, 100);
        depositBuyOrder(acc[2], 5000, 90);
        borrowOrder(acc[2], 1, 20);
        uint256 bookbaseBalance = baseToken.balanceOf(address(book));
        uint256 lenderbaseBalance = baseToken.balanceOf(acc[1]);
        uint256 borrowerbaseBalance = baseToken.balanceOf(acc[2]);
        uint256 takerbaseBalance = baseToken.balanceOf(acc[3]);
        uint256 bookquoteBalance = quoteToken.balanceOf(address(book));
        uint256 lenderquoteBalance = quoteToken.balanceOf(acc[1]);
        uint256 borrowerquoteBalance = quoteToken.balanceOf(acc[2]);
        uint256 takerquoteBalance = quoteToken.balanceOf(acc[3]);
        vm.prank(acc[3]);
        book.take(1, 10);
        assertEq(baseToken.balanceOf(address(book)), bookbaseBalance - 10);
        assertEq(baseToken.balanceOf(acc[1]), lenderbaseBalance);
        assertEq(baseToken.balanceOf(acc[2]), borrowerbaseBalance);
        assertEq(baseToken.balanceOf(acc[3]), takerbaseBalance + 10);
        assertEq(quoteToken.balanceOf(address(book)), bookquoteBalance - 2000);
        assertEq(quoteToken.balanceOf(acc[1]), lenderquoteBalance + 3000);
        assertEq(quoteToken.balanceOf(acc[2]), borrowerquoteBalance);
        assertEq(quoteToken.balanceOf(acc[3]), takerquoteBalance - 1000);
    }

    // liquidate two positions after taking a buy order, check external balances
    function testLiquidateTwoPositionFromBuyOrder() public {
        depositBuyOrder(acc[1], 2000, 100);
        depositSellOrder(acc[2], 30, 110);
        depositSellOrder(acc[3], 40, 120);
        borrowOrder(acc[2], 1, 400);
        borrowOrder(acc[3], 1, 600);
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
        vm.prank(acc[4]);
        book.take(1, 1000);
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
    }

    // liquidate two positions after taking a sell order, check external balances
    function testLiquidateTwoPositionFromSellOrder() public {
        depositSellOrder(acc[1], 20, 100);
        depositBuyOrder(acc[2], 3000, 90);
        depositBuyOrder(acc[3], 4000, 80);
        borrowOrder(acc[2], 1, 7);
        borrowOrder(acc[3], 1, 8);
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
        vm.prank(acc[4]);
        book.take(1, 5);
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
    }


}
