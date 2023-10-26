// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Setup} from "./Setup.sol";
import {StdCheats} from "forge-std/StdCheats.sol";

contract TestLiquidate is Setup {

    // liquidate one position after taking a buy order, check external balances
    function testLiquidateOnePositionFromBuyOrder() public {
        depositBuyOrder(USER1, 2000, 100);
        depositSellOrder(USER2, 30, 110);
        borrowOrder(USER2, 1, 1000);
        uint256 bookQuoteBalance = quoteToken.balanceOf(address(book));
        uint256 lenderQuoteBalance = quoteToken.balanceOf(USER1);
        uint256 borrowerQuoteBalance = quoteToken.balanceOf(USER2);
        uint256 takerQuoteBalance = quoteToken.balanceOf(USER3);
        uint256 bookBaseBalance = baseToken.balanceOf(address(book));
        uint256 takerBaseBalance = baseToken.balanceOf(USER3);
        uint256 lenderBaseBalance = baseToken.balanceOf(USER1);
        uint256 borrowerBaseBalance = baseToken.balanceOf(USER2);
        vm.prank(USER3);
        book.take(1, 1000);
        assertEq(quoteToken.balanceOf(address(book)), bookQuoteBalance - 1000);
        assertEq(quoteToken.balanceOf(USER1), lenderQuoteBalance);
        assertEq(quoteToken.balanceOf(USER2), borrowerQuoteBalance);
        assertEq(quoteToken.balanceOf(USER3), takerQuoteBalance + 1000);
        assertEq(baseToken.balanceOf(address(book)), bookBaseBalance - 10);
        assertEq(baseToken.balanceOf(USER1), lenderBaseBalance + 20);
        assertEq(baseToken.balanceOf(USER2), borrowerBaseBalance);
        assertEq(baseToken.balanceOf(USER3), takerBaseBalance - 10);
    }

    // liquidate one position after taking a sell order, check external balances
    function testLiquidateOnePositionFromSellOrder() public {
        depositSellOrder(USER1, 30, 100);
        depositBuyOrder(USER2, 5000, 90);
        borrowOrder(USER2, 1, 20);
        uint256 bookbaseBalance = baseToken.balanceOf(address(book));
        uint256 lenderbaseBalance = baseToken.balanceOf(USER1);
        uint256 borrowerbaseBalance = baseToken.balanceOf(USER2);
        uint256 takerbaseBalance = baseToken.balanceOf(USER3);
        uint256 bookquoteBalance = quoteToken.balanceOf(address(book));
        uint256 lenderquoteBalance = quoteToken.balanceOf(USER1);
        uint256 borrowerquoteBalance = quoteToken.balanceOf(USER2);
        uint256 takerquoteBalance = quoteToken.balanceOf(USER3);
        vm.prank(USER3);
        book.take(1, 10);
        assertEq(baseToken.balanceOf(address(book)), bookbaseBalance - 10);
        assertEq(baseToken.balanceOf(USER1), lenderbaseBalance);
        assertEq(baseToken.balanceOf(USER2), borrowerbaseBalance);
        assertEq(baseToken.balanceOf(USER3), takerbaseBalance + 10);
        assertEq(quoteToken.balanceOf(address(book)), bookquoteBalance - 2000);
        assertEq(quoteToken.balanceOf(USER1), lenderquoteBalance + 3000);
        assertEq(quoteToken.balanceOf(USER2), borrowerquoteBalance);
        assertEq(quoteToken.balanceOf(USER3), takerquoteBalance - 1000);
    }

    // liquidate two positions after taking a buy order, check external balances
    function testLiquidateTwoPositionFromBuyOrder() public {
        depositBuyOrder(USER1, 2000, 100);
        depositSellOrder(USER2, 30, 110);
        depositSellOrder(USER3, 40, 120);
        borrowOrder(USER2, 1, 400);
        borrowOrder(USER3, 1, 600);
        uint256 bookQuoteBalance = quoteToken.balanceOf(address(book));
        uint256 lenderQuoteBalance = quoteToken.balanceOf(USER1);
        uint256 borrower1QuoteBalance = quoteToken.balanceOf(USER2);
        uint256 borrower2QuoteBalance = quoteToken.balanceOf(USER3);
        uint256 takerQuoteBalance = quoteToken.balanceOf(USER4);
        uint256 bookBaseBalance = baseToken.balanceOf(address(book));
        uint256 lenderBaseBalance = baseToken.balanceOf(USER1);
        uint256 borrower1BaseBalance = baseToken.balanceOf(USER2);
        uint256 borrower2BaseBalance = baseToken.balanceOf(USER3);
        uint256 takerBaseBalance = baseToken.balanceOf(USER4);
        vm.prank(USER4);
        book.take(1, 1000);
        assertEq(quoteToken.balanceOf(address(book)), bookQuoteBalance - 1000);
        assertEq(quoteToken.balanceOf(USER1), lenderQuoteBalance);
        assertEq(quoteToken.balanceOf(USER2), borrower1QuoteBalance);
        assertEq(quoteToken.balanceOf(USER3), borrower2QuoteBalance);
        assertEq(quoteToken.balanceOf(USER4), takerQuoteBalance + 1000);
        assertEq(baseToken.balanceOf(address(book)), bookBaseBalance - 10); // 2 * 500/100 of base collateral
        assertEq(baseToken.balanceOf(USER1), lenderBaseBalance + 20);
        assertEq(baseToken.balanceOf(USER2), borrower1BaseBalance);
        assertEq(baseToken.balanceOf(USER3), borrower2BaseBalance);
        assertEq(baseToken.balanceOf(USER4), takerBaseBalance - 10);
    }

    // liquidate two positions after taking a sell order, check external balances
    function testLiquidateTwoPositionFromSellOrder() public {
        depositSellOrder(USER1, 20, 100);
        depositBuyOrder(USER2, 3000, 90);
        depositBuyOrder(USER3, 4000, 80);
        borrowOrder(USER2, 1, 7);
        borrowOrder(USER3, 1, 8);
        uint256 bookBaseBalance = baseToken.balanceOf(address(book));
        uint256 lenderBaseBalance = baseToken.balanceOf(USER1);
        uint256 borrower1BaseBalance = baseToken.balanceOf(USER2);
        uint256 borrower2BaseBalance = baseToken.balanceOf(USER3);
        uint256 takerBaseBalance = baseToken.balanceOf(USER4);
        uint256 bookQuoteBalance = quoteToken.balanceOf(address(book));
        uint256 lenderQuoteBalance = quoteToken.balanceOf(USER1);
        uint256 borrower1QuoteBalance = quoteToken.balanceOf(USER2);
        uint256 borrower2QuoteBalance = quoteToken.balanceOf(USER3);
        uint256 takerQuoteBalance = quoteToken.balanceOf(USER4);
        vm.prank(USER4);
        book.take(1, 5);
        assertEq(baseToken.balanceOf(address(book)), bookBaseBalance - 5);
        assertEq(baseToken.balanceOf(USER1), lenderBaseBalance);
        assertEq(baseToken.balanceOf(USER2), borrower1BaseBalance);
        assertEq(baseToken.balanceOf(USER3), borrower2BaseBalance);
        assertEq(baseToken.balanceOf(USER4), takerBaseBalance + 5);
        assertEq(quoteToken.balanceOf(address(book)), bookQuoteBalance - 1500); // (7 + 8) * 100 of quote collateral
        assertEq(quoteToken.balanceOf(USER1), lenderQuoteBalance + 2000);
        assertEq(quoteToken.balanceOf(USER2), borrower1QuoteBalance);
        assertEq(quoteToken.balanceOf(USER3), borrower2QuoteBalance);
        assertEq(quoteToken.balanceOf(USER4), takerQuoteBalance - 500);
    }


}
