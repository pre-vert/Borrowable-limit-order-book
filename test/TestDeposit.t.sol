// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Setup} from "./Setup.sol";
import {StdCheats} from "forge-std/StdCheats.sol";

//   - 
//   - 
// - Transfer token to contract
// - Emit

contract TestDeposit is Setup {

    // if new limit order, create order in orders
    function testDepositOneBuyOrder() public {
        depositBuyOrder(USER1, 2000, 90);
        (address maker, bool isBuyOrder, uint256 quantity, uint256 price) = book.orders(1);
        assertEq(quantity, 2000);
        assertEq(price, 90);
        assertEq(isBuyOrder, true);
        assertEq(maker, USER1);
    }

    function testDepositOneSellOrder() public {
        depositSellOrder(USER2, 20, 110);
        (address maker, bool isBuyOrder, uint256 quantity, uint256 price) = book.orders(1);
        assertEq(quantity, 20);
        assertEq(price, 110);
        assertEq(isBuyOrder, false);
        assertEq(maker, USER2);
        assertEq(book.countOrdersOfUser(USER2), 1);
        assertEq(book.countOrdersOfUser(USER2), 1);
    }

    function testDepositOneBuyOrderCheckBalances() public {
        uint256 orderBookBalance = quoteToken.balanceOf(address(book));
        uint256 userBalance = quoteToken.balanceOf(USER1);
        depositBuyOrder(USER1, 2000, 90);
        assertEq(quoteToken.balanceOf(address(book)), orderBookBalance + 2000);
        assertEq(quoteToken.balanceOf(USER1), userBalance - 2000);
    }

    function testDepositOneSellOrderCheckBalances() public {
        uint256 orderBookBalance = baseToken.balanceOf(address(book));
        uint256 userBalance = baseToken.balanceOf(USER1);
        depositSellOrder(USER1, 20, 110);
        assertEq(baseToken.balanceOf(address(book)), orderBookBalance + 20);
        assertEq(baseToken.balanceOf(USER1), userBalance - 20);
    }

    function testDepositTwoBuyOrders() public {
        uint256 orderBookBalance = quoteToken.balanceOf(address(book));
        depositBuyOrder(USER1, 2000, 90);
        depositBuyOrder(USER1, 3000, 95);
        assertEq(quoteToken.balanceOf(address(book)), orderBookBalance + 5000);
    }

    function testDepositThreeOrders() public {
        uint256 bookBalance = baseToken.balanceOf(address(book));
        depositSellOrder(USER1, 20, 110);
        depositBuyOrder(USER1, 2000, 90);
        depositSellOrder(USER2, 15, 105);
        assertEq(baseToken.balanceOf(address(book)), bookBalance + 35);
        assertEq(book.countOrdersOfUser(USER1), 2);
        assertEq(book.countOrdersOfUser(USER2), 1);
        assertEq(book.countOrdersOfUser(USER3), 0);
    }

    // When deposit is less than min deposit, revert
    function testRevertIfZeroDeposit() public {
        vm.expectRevert("Quantity exceeds limit");
        depositBuyOrder(USER1, 99, 90);
    }

    // When price is zero, revert
    function testRevertIfZeroPrice() public {
        vm.expectRevert("Must be positive");
        depositBuyOrder(USER1, 1000, 0);
    }

    // When an identical order exists, call increaseDeposit()
    function testAggregateIdenticalOrder() public {
        depositBuyOrder(USER1, 3000, 110);
        depositBuyOrder(USER1, 2000, 110);
        (,, uint256 quantity1,) = book.orders(1);
        (,, uint256 quantity2,) = book.orders(2);
        assertEq(quantity1, 5000);
        assertEq(quantity2, 0);
        assertEq(book.countOrdersOfUser(USER1), 1);
    }

    // add order id in depositIds in users
    function testAddDepositIdInUsers() public {
        depositBuyOrder(USER1, 3000, 110);
        depositBuyOrder(USER1, 2000, 120);
    }
}
