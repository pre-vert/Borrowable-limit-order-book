// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Setup} from "./Setup.sol";
import {StdCheats} from "forge-std/StdCheats.sol";

contract TestTake is Setup {

    // taking fails if non-existing buy order
    function testTakingFailsIfNonExistingBuyOrder() public {
        depositBuyOrder(acc[1], 2000, 90);
        vm.expectRevert("Order has zero assets");
        vm.prank(acc[2]);
        book.take(2, 0);
    }

    // taking fails if non existing sell order
    function testTakingFailsIfNonExistingSellOrder() public {
        depositSellOrder(acc[1], 20, 110);
        vm.expectRevert("Order has zero assets");
        vm.prank(acc[2]);
        book.take(2, 0);
    }

    // taking fails if zero taken
    function testTakeBuyOrderFailsIfZero() public {
        depositBuyOrder(acc[1], 2000, 90);
        vm.expectRevert("Must be positive");
        vm.prank(acc[2]);
        book.take(1, 0);
    }

    // taking fails if zeo taken
    function testTakeSellOrderFailsIfZero() public {
        depositSellOrder(acc[1], 20, 110);
        vm.expectRevert("Must be positive");
        vm.prank(acc[1]);
        book.take(1, 0);
    }

    // taking fails if greater than buy order
    function testTakeBuyOrderFailsIfTooMuch() public {
        depositBuyOrder(acc[1], 2000, 90);
        vm.expectRevert("Quantity exceeds limit");
        vm.prank(acc[2]);
        book.take(1, 3000);
    }

    // taking fails if greater than sell order
    function testTakeSellOrderFailsIfTooMuch() public {
        depositSellOrder(acc[1], 20, 110);
        vm.expectRevert("Quantity exceeds limit");
        vm.prank(acc[2]);
        book.take(1, 22);
    }

    // taking of buy order correctly adjusts external balances
    function testTakeBuyOrderCheckBalances() public {
        depositBuyOrder(acc[1], 1800, 90);
        uint256 contractQuoteBalance = quoteToken.balanceOf(address(book));
        uint256 makerQuoteBalance = quoteToken.balanceOf(acc[1]);
        uint256 makerBaseBalance = baseToken.balanceOf(acc[1]);
        uint256 takerQuoteBalance = quoteToken.balanceOf(acc[2]);
        uint256 takerBaseBalance = baseToken.balanceOf(acc[2]);
        vm.prank(acc[2]);
        book.take(1, 1800);
        assertEq(quoteToken.balanceOf(address(book)), contractQuoteBalance - 1800);
        assertEq(quoteToken.balanceOf(acc[1]), makerQuoteBalance);
        assertEq(baseToken.balanceOf(acc[1]), makerBaseBalance + 1800 / 90);
        assertEq(quoteToken.balanceOf(acc[2]), takerQuoteBalance + 1800);
        assertEq(baseToken.balanceOf(acc[2]), takerBaseBalance - 1800 / 90);
    }

    function testTakeSellOrderCheckBalances() public {
        depositSellOrder(acc[1], 20, 110);
        uint256 contractBaseBalance = baseToken.balanceOf(address(book));
        uint256 makerBaseBalance = baseToken.balanceOf(acc[1]);
        uint256 makerQuoteBalance = quoteToken.balanceOf(acc[1]);
        uint256 takerBaseBalance = baseToken.balanceOf(acc[2]);
        uint256 takerQuoteBalance = quoteToken.balanceOf(acc[2]);
        vm.prank(acc[2]);
        book.take(1, 20);
        assertEq(baseToken.balanceOf(address(book)), contractBaseBalance - 20);
        assertEq(baseToken.balanceOf(acc[1]), makerBaseBalance);
        assertEq(quoteToken.balanceOf(acc[1]), makerQuoteBalance + 20 * 110);
        assertEq(baseToken.balanceOf(acc[2]), takerBaseBalance + 20);
        assertEq(quoteToken.balanceOf(acc[2]), takerQuoteBalance - 20 * 110);
    }

    // taking of buy order by maker herself correctly adjusts external balances
    function testMakerTakesBuyOrderCheckBalances() public {
        depositBuyOrder(acc[1], 1800, 90);
        uint256 contractQuoteBalance = quoteToken.balanceOf(address(book));
        uint256 makerQuoteBalance = quoteToken.balanceOf(acc[1]);
        uint256 makerBaseBalance = baseToken.balanceOf(acc[1]);
        vm.prank(acc[1]);
        book.take(1, 900);
        assertEq(quoteToken.balanceOf(address(book)), contractQuoteBalance - 900);
        assertEq(quoteToken.balanceOf(acc[1]), makerQuoteBalance + 900);
        assertEq(baseToken.balanceOf(acc[1]), makerBaseBalance);
    }



}
