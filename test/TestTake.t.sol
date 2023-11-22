// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Setup} from "./Setup.sol";
import {MathLib, WAD} from "../lib/MathLib.sol";

contract TestTake is Setup {

    // taking fails if non-existing buy order
    function test_TakingFailsIfNonExistingBuyOrder() public {
        depositBuyOrder(Alice, 2000, 90);
        vm.expectRevert("Order has zero assets");
        take(Bob, Carol_Order, 0);
    }

    // taking fails if non existing sell order
    function test_TakingFailsIfNonExistingSellOrder() public {
        depositSellOrder(Alice, 20, 110);
        vm.expectRevert("Order has zero assets");
        take(Bob, Carol_Order, 0);
    }

    // taking is ok if zero taken, buy order
    function test_TakeBuyOrderWithZero() public {
        depositBuyOrder(Alice, 2000, 90);
        take(Bob, Alice_Order, 0);
        checkOrderQuantity(Alice_Order, 2000);
    }

    // taking is ok if zero taken, sell order
    function test_TakeSellOrderWithZero() public {
        depositSellOrder(Alice, 20, 110);
        take(Bob, Alice_Order, 0);
        checkOrderQuantity(Alice_Order, 20);
    }

    // taking fails if greater than buy order
    function test_TakeBuyOrderFailsIfTooMuch() public {
        depositBuyOrder(Alice, 2000, 90);
        assertEq(book.outable(Alice_Order, 2001 * WAD), false);
        vm.expectRevert("Too much assets taken");
        take(Bob, Alice_Order, 2001);
    }

    // taking fails if greater than sell order
    function test_TakeSellOrderFailsIfTooMuch() public {
        depositSellOrder(Alice, 20, 110);
        assertEq(book.outable(Alice_Order, 21 * WAD), false);
        vm.expectRevert("Too much assets taken");
        take(Bob, Alice_Order, 21);
    }

    // taking of buy order correctly adjusts external balances
    function test_TakeBuyOrderCheckBalances() public {
        depositBuyOrder(Alice, 1800, 90);
        uint256 contractQuoteBalance = quoteToken.balanceOf(OrderBook);
        uint256 makerQuoteBalance = quoteToken.balanceOf(Alice);
        uint256 makerBaseBalance = baseToken.balanceOf(Alice);
        uint256 takerQuoteBalance = quoteToken.balanceOf(Bob);
        uint256 takerBaseBalance = baseToken.balanceOf(Bob);
        take(Bob, Alice_Order, 1800);
        assertEq(quoteToken.balanceOf(OrderBook), contractQuoteBalance - 1800 * WAD);
        assertEq(quoteToken.balanceOf(Alice), makerQuoteBalance);
        assertEq(baseToken.balanceOf(Alice), makerBaseBalance + 20 * WAD);
        assertEq(quoteToken.balanceOf(Bob), takerQuoteBalance + 1800 * WAD);
        assertEq(baseToken.balanceOf(Bob), takerBaseBalance - 20 * WAD);
    }

    // taking of sell order correctly adjusts external balances
    function test_TakeSellOrderCheckBalances() public {
        depositSellOrder(Alice, 20, 110);
        uint256 contractBaseBalance = baseToken.balanceOf(OrderBook);
        uint256 makerBaseBalance = baseToken.balanceOf(Alice);
        uint256 makerQuoteBalance = quoteToken.balanceOf(Alice);
        uint256 takerBaseBalance = baseToken.balanceOf(Bob);
        uint256 takerQuoteBalance = quoteToken.balanceOf(Bob);
        take(Bob, Alice_Order, 20);
        assertEq(baseToken.balanceOf(OrderBook), contractBaseBalance - 20 * WAD);
        assertEq(baseToken.balanceOf(Alice), makerBaseBalance);
        assertEq(quoteToken.balanceOf(Alice), makerQuoteBalance + 20 * 110 * WAD);
        assertEq(baseToken.balanceOf(Bob), takerBaseBalance + 20 * WAD);
        assertEq(quoteToken.balanceOf(Bob), takerQuoteBalance - 20 * 110 * WAD);
    }

    // taking of buy order by maker herself correctly adjusts external balances
    function test_MakerTakesBuyOrderCheckBalances() public {
        depositBuyOrder(Alice, 1800, 90);
        uint256 contractQuoteBalance = quoteToken.balanceOf(OrderBook);
        uint256 makerQuoteBalance = quoteToken.balanceOf(Alice);
        uint256 makerBaseBalance = baseToken.balanceOf(Alice);
        take(Alice, Alice_Order, 900);
        assertEq(quoteToken.balanceOf(OrderBook), contractQuoteBalance - 900 * WAD);
        assertEq(quoteToken.balanceOf(Alice), makerQuoteBalance + 900 * WAD);
        assertEq(baseToken.balanceOf(Alice), makerBaseBalance);
    }

}
