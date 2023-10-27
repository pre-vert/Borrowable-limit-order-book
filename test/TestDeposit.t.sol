// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Setup} from "./Setup.sol";
import {StdCheats} from "forge-std/StdCheats.sol";

contract TestDeposit is Setup {

    // if new limit order, create order in orders
    function testDepositBuyOrder() public {
        depositBuyOrder(acc[1], 2000, 90);
        (address maker, bool isBuyOrder, uint256 quantity, uint256 price) = book.orders(1);
        assertEq(maker, acc[1]);
        assertEq(quantity, 2000);
        assertEq(price, 90);
        assertEq(isBuyOrder, buyOrder);
    }

    function testDepositSellOrder() public {
        depositSellOrder(acc[2], 20, 110);
        (address maker, bool isBuyOrder, uint256 quantity, uint256 price) = book.orders(1);
        assertEq(maker, acc[2]);
        assertEq(quantity, 20);
        assertEq(price, 110);
        assertEq(isBuyOrder, sellOrder);
        assertEq(book.countOrdersOfUser(acc[2]), 1);
        assertEq(book.countOrdersOfUser(acc[2]), 1);
    }

    // Transfer tokens to contract, check external balances
    function testDepositBuyOrderCheckBalances() public {
        uint256 orderBookBalance = quoteToken.balanceOf(address(book));
        uint256 userBalance = quoteToken.balanceOf(acc[1]);
        depositBuyOrder(acc[1], 2000, 90);
        assertEq(quoteToken.balanceOf(address(book)), orderBookBalance + 2000);
        assertEq(quoteToken.balanceOf(acc[1]), userBalance - 2000);
    }

    function testDepositSellOrderCheckBalances() public {
        uint256 orderBookBalance = baseToken.balanceOf(address(book));
        uint256 userBalance = baseToken.balanceOf(acc[1]);
        depositSellOrder(acc[1], 20, 110);
        assertEq(baseToken.balanceOf(address(book)), orderBookBalance + 20);
        assertEq(baseToken.balanceOf(acc[1]), userBalance - 20);
    }

    // Make two orders, check external balances
    function testDepositTwoBuyOrders() public {
        uint256 orderBookBalance = quoteToken.balanceOf(address(book));
        uint256 userBalance = quoteToken.balanceOf(acc[1]);
        depositBuyOrder(acc[1], 2000, 90);
        depositBuyOrder(acc[1], 3000, 95);
        assertEq(quoteToken.balanceOf(address(book)), orderBookBalance + 5000);
        assertEq(quoteToken.balanceOf(acc[1]), userBalance - 5000);
    }

    // Make three orders, check external balances
    function testDepositThreeOrders() public {
        uint256 bookBalance = baseToken.balanceOf(address(book));
        depositSellOrder(acc[1], 20, 110);
        depositBuyOrder(acc[1], 2000, 90);
        depositSellOrder(acc[2], 15, 105);
        assertEq(baseToken.balanceOf(address(book)), bookBalance + 35);
        assertEq(book.countOrdersOfUser(acc[1]), 2);
        assertEq(book.countOrdersOfUser(acc[2]), 1);
        assertEq(book.countOrdersOfUser(acc[3]), 0);
    }

    // When deposit is less than min deposit, revert
    function testRevertBuyOrderIfZeroDeposit() public {
        vm.expectRevert("Quantity exceeds limit");
        depositBuyOrder(acc[1], 99, 90);
    }

    function testRevertSellOrderIfZeroDeposit() public {
        vm.expectRevert("Quantity exceeds limit");
        depositSellOrder(acc[1], 1, 110);
    }

    // When price is zero, revert
    function testRevertBuyOrderIfZeroPrice() public {
        vm.expectRevert("Must be positive");
        depositBuyOrder(acc[1], 1000, 0);
    }

    function testRevertSellOrderIfZeroPrice() public {
        vm.expectRevert("Must be positive");
        depositSellOrder(acc[1], 10, 0);
    }

    // When an identical order exists, call increaseDeposit()
    function testAggregateIdenticalBuyOrder() public {
        depositBuyOrder(acc[1], 3000, 110);
        depositBuyOrder(acc[1], 2000, 110);
        (,, uint256 quantity1,) = book.orders(1);
        (,, uint256 quantity2,) = book.orders(2);
        assertEq(quantity1, 5000);
        assertEq(quantity2, 0);
        assertEq(book.countOrdersOfUser(acc[1]), 1);
    }

    function testAggregateIdenticalSellOrder() public {
        depositSellOrder(acc[1], 30, 90);
        depositSellOrder(acc[1], 20, 90);
        (,, uint256 quantity1,) = book.orders(1);
        (,, uint256 quantity2,) = book.orders(2);
        assertEq(quantity1, 50);
        assertEq(quantity2, 0);
        assertEq(book.countOrdersOfUser(acc[1]), 1);
    }
    
    // revert if 0 quantity via increaseDeposit() if same limit price
    function testincreaseBuyOrderZeroQuantity() public {
        depositBuyOrder(acc[1], 3000, 110);
        vm.expectRevert("Must be positive");
        depositBuyOrder(acc[1], 0, 110);
    }

    function testincreaseSellOrderZeroQuantity() public {
        depositSellOrder(acc[1], 30, 90);
        vm.expectRevert("Must be positive");
        depositSellOrder(acc[1], 0, 90);
    }

    // call increaseDeposit() check balances
    function testincreaseBuyOrderCheckBalances() public {
        uint256 bookBalance = quoteToken.balanceOf(address(book));
        uint256 userBalance = quoteToken.balanceOf(acc[1]);
        depositBuyOrder(acc[1], 2000, 90);
        depositBuyOrder(acc[1], 3000, 90);
        assertEq(quoteToken.balanceOf(address(book)), bookBalance + 5000);
        assertEq(quoteToken.balanceOf(acc[1]), userBalance - 5000);
    }

    function testincreaseSellOrderCheckBalances() public {
        uint256 bookBalance = baseToken.balanceOf(address(book));
        uint256 userBalance = baseToken.balanceOf(acc[1]);
        depositSellOrder(acc[1], 20, 110);
        depositSellOrder(acc[1], 30, 110);
        assertEq(baseToken.balanceOf(address(book)), bookBalance + 50);
        assertEq(baseToken.balanceOf(acc[1]), userBalance - 50);
    }

    // add new order if same order but different maker
    function addSameBuyOrderDifferentMaker() public {
        depositBuyOrder(acc[1], 3000, 110);
        depositBuyOrder(acc[2], 2000, 110);
        (,, uint256 quantity1,) = book.orders(1);
        (,, uint256 quantity2,) = book.orders(2);
        assertEq(quantity1, 3000);
        assertEq(quantity2, 2000);
        assertEq(book.countOrdersOfUser(acc[1]), 1);
        assertEq(book.countOrdersOfUser(acc[2]), 1);
    }

    // add order id in depositIds in users
    function testAddDepositIdInUsers() public {
        assertEq(book.getUserDepositIds(acc[1])[0], 0);
        depositBuyOrder(acc[1], 3000, 110);
        assertEq(book.getUserDepositIds(acc[1])[0], 1);
        depositBuyOrder(acc[1], 2000, 120);
        assertEq(book.getUserDepositIds(acc[1])[0], 1);
        assertEq(book.getUserDepositIds(acc[1])[1], 2);
    }
}
