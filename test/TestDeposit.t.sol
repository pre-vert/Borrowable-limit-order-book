// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Setup} from "./Setup.sol";
import {StdCheats} from "forge-std/StdCheats.sol";

contract TestDeposit is Setup {

    // if new limit order, create order in orders
    function test_DepositBuyOrder() public {
        depositBuyOrder(acc[1], 2000, 90);
        (address maker, bool isBuyOrder, uint256 quantity, uint256 price) = book.orders(1);
        assertEq(maker, acc[1]);
        assertEq(quantity, 2000);
        assertEq(price, 90);
        assertEq(isBuyOrder, buyOrder);
    }

    function test_DepositSellOrder() public {
        depositSellOrder(acc[2], 20, 110);
        (address maker, bool isBuyOrder, uint256 quantity, uint256 price) = book.orders(1);
        assertEq(maker, acc[2]);
        assertEq(quantity, 20);
        assertEq(price, 110);
        assertEq(isBuyOrder, sellOrder);
        assertEq(book.countOrdersOfUser(acc[2]), 1);
        assertEq(book.countOrdersOfUser(acc[2]), 1);
    }

    // Transfer tokens to contract, check balances
    function test_DepositBuyOrderCheckBalances() public {
        uint256 orderBookBalance = quoteToken.balanceOf(address(book));
        uint256 userBalance = quoteToken.balanceOf(acc[1]);
        depositBuyOrder(acc[1], 2000, 90);
        assertEq(quoteToken.balanceOf(address(book)), orderBookBalance + 2000);
        assertEq(quoteToken.balanceOf(acc[1]), userBalance - 2000);
        checkOrderQuantity(1, 2000);
    }

    function test_DepositSellOrderCheckBalances() public {
        uint256 orderBookBalance = baseToken.balanceOf(address(book));
        uint256 userBalance = baseToken.balanceOf(acc[1]);
        depositSellOrder(acc[1], 20, 110);
        assertEq(baseToken.balanceOf(address(book)), orderBookBalance + 20);
        assertEq(baseToken.balanceOf(acc[1]), userBalance - 20);
        checkOrderQuantity(1, 20);
    }

    // Make two orders, check external balances
    function test_DepositTwoBuyOrders() public {
        uint256 orderBookBalance = quoteToken.balanceOf(address(book));
        uint256 userBalance = quoteToken.balanceOf(acc[1]);
        depositBuyOrder(acc[1], 2000, 90);
        depositBuyOrder(acc[1], 3000, 95);
        assertEq(quoteToken.balanceOf(address(book)), orderBookBalance + 5000);
        assertEq(quoteToken.balanceOf(acc[1]), userBalance - 5000);
        checkOrderQuantity(1, 2000);
        checkOrderQuantity(2, 3000);
    }

    // Make three orders, check external balances
    function test_DepositThreeOrders() public {
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
    function test_RevertBuyOrderIfZeroDeposit() public {
        vm.expectRevert("Quantity exceeds limit");
        depositBuyOrder(acc[1], 99, 90);
        checkOrderQuantity(1, 0);
    }

    function test_RevertSellOrderIfZeroDeposit() public {
        vm.expectRevert("Quantity exceeds limit");
        depositSellOrder(acc[1], 1, 110);
        checkOrderQuantity(1, 0);
    }

    // When price is zero, revert
    function test_RevertBuyOrderIfZeroPrice() public {
        vm.expectRevert("Must be positive");
        depositBuyOrder(acc[1], 1000, 0);
        checkOrderQuantity(1, 0);
    }

    function test_RevertSellOrderIfZeroPrice() public {
        vm.expectRevert("Must be positive");
        depositSellOrder(acc[1], 10, 0);
        checkOrderQuantity(1, 0);
    }

    // When an identical order exists, call increaseDeposit()
    function test_AggregateIdenticalBuyOrder() public {
        depositBuyOrder(acc[1], 3000, 110);
        depositBuyOrder(acc[1], 2000, 110);
        (,, uint256 quantity1,) = book.orders(1);
        (,, uint256 quantity2,) = book.orders(2);
        assertEq(quantity1, 5000);
        assertEq(quantity2, 0);
        assertEq(book.countOrdersOfUser(acc[1]), 1);
        checkOrderQuantity(1, 5000);
    }

    function test_AggregateIdenticalSellOrder() public {
        depositSellOrder(acc[1], 30, 90);
        depositSellOrder(acc[1], 20, 90);
        (,, uint256 quantity1,) = book.orders(1);
        (,, uint256 quantity2,) = book.orders(2);
        assertEq(quantity1, 50);
        assertEq(quantity2, 0);
        assertEq(book.countOrdersOfUser(acc[1]), 1);
        checkOrderQuantity(1, 50);
    }
    
    // revert if 0 quantity via increaseDeposit() if same limit price
    function test_IncreaseBuyOrderZeroQuantity() public {
        depositBuyOrder(acc[1], 3000, 110);
        vm.expectRevert("Must be positive");
        depositBuyOrder(acc[1], 0, 110);
        checkOrderQuantity(1, 3000);
    }

    function test_IncreaseSellOrderZeroQuantity() public {
        depositSellOrder(acc[1], 30, 90);
        vm.expectRevert("Must be positive");
        depositSellOrder(acc[1], 0, 90);
        checkOrderQuantity(1, 30);
    }

    // call increaseDeposit() check balances
    function test_IncreaseBuyOrderCheckBalances() public {
        uint256 bookBalance = quoteToken.balanceOf(address(book));
        uint256 userBalance = quoteToken.balanceOf(acc[1]);
        depositBuyOrder(acc[1], 2000, 90);
        depositBuyOrder(acc[1], 3000, 90);
        assertEq(quoteToken.balanceOf(address(book)), bookBalance + 5000);
        assertEq(quoteToken.balanceOf(acc[1]), userBalance - 5000);
        checkOrderQuantity(1, 5000);
    }

    function test_IncreaseSellOrderCheckBalances() public {
        uint256 bookBalance = baseToken.balanceOf(address(book));
        uint256 userBalance = baseToken.balanceOf(acc[1]);
        depositSellOrder(acc[1], 20, 110);
        depositSellOrder(acc[1], 30, 110);
        assertEq(baseToken.balanceOf(address(book)), bookBalance + 50);
        assertEq(baseToken.balanceOf(acc[1]), userBalance - 50);
        checkOrderQuantity(1, 50);
    }

    // add new order if same order but different maker
    function test_AddSameBuyOrderDifferentMaker() public {
        depositBuyOrder(acc[1], 3000, 110);
        depositBuyOrder(acc[2], 2000, 110);
        checkOrderQuantity(1, 3000);
        checkOrderQuantity(2, 2000);
        assertEq(book.countOrdersOfUser(acc[1]), 1);
        assertEq(book.countOrdersOfUser(acc[2]), 1);
        checkOrderQuantity(1, 3000);
        checkOrderQuantity(2, 2000);
    }

    // add order id in depositIds in users
    function test_AddDepositIdInUsers() public {
        checkUserDepositId(acc[1], 0, 0);
        depositBuyOrder(acc[1], 3000, 110);
        checkUserDepositId(acc[1], 0, 1);
        checkUserDepositId(acc[1], 1, 0);
        depositBuyOrder(acc[1], 2000, 120);
        checkUserDepositId(acc[1], 0, 1);
        checkUserDepositId(acc[1], 1, 2);
    }

    // tests what happens if a user has more than the max number of orders
    function test_OrdersForUserExceedLimit() public {
        depositBuyOrder(acc[1], 3000, 110);
        depositSellOrder(acc[1], 30, 90);
        vm.expectRevert("Max number of orders reached for user");
        depositBuyOrder(acc[1], 4000, 120);
    }
}
