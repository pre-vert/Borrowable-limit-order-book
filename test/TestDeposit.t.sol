// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Setup} from "./Setup.sol";
import {MathLib, WAD} from "../lib/MathLib.sol";

contract TestDeposit is Setup {

    // if new limit order, create order in orders
    function test_DepositBuyOrder() public {
        depositBuyOrder(Alice, 2000, 90);
        (address maker,
        bool isBuyOrder,
        uint256 quantity,
        uint256 price, 
        uint256 pairedPrice,
        bool isBorrowable)
        = book.orders(1);
        assertEq(maker, Alice);
        assertEq(quantity, 2000 * WAD);
        assertEq(price, 90 * WAD);
        assertEq(pairedPrice, price + price / 10);
        assertEq(isBuyOrder, BuyOrder);
        assertEq(isBorrowable, IsBorrowable);
    }

    function test_DepositSellOrder() public {
        depositSellOrder(Bob, 20, 110);
        (address maker,
        bool isBuyOrder,
        uint256 quantity,
        uint256 price,
        uint256 pairedPrice,
        bool isBorrowable)
        = book.orders(1);
        assertEq(maker, Bob);
        assertEq(quantity, 20 * WAD);
        assertEq(price, 110 * WAD);
        assertEq(pairedPrice, price - price / 10);
        assertEq(isBuyOrder, SellOrder);
        assertEq(isBorrowable, IsBorrowable);
        assertEq(book.countOrdersOfUser(Bob), 1);
        assertEq(book.countOrdersOfUser(Bob), 1);
    }

    // Transfer tokens to contract, correctly adjustsbalances
    function test_DepositBuyOrderCheckBalances() public {
        uint256 OrderBookBalance = quoteToken.balanceOf(OrderBook);
        uint256 userBalance = quoteToken.balanceOf(Alice);
        depositBuyOrder(Alice, 2000, 90);
        assertEq(quoteToken.balanceOf(OrderBook), OrderBookBalance + 2000 * WAD);
        assertEq(quoteToken.balanceOf(Alice), userBalance - 2000 * WAD);
        checkOrderQuantity(1, 2000);
    }

    function test_DepositSellOrderCheckBalances() public {
        uint256 OrderBookBalance = baseToken.balanceOf(OrderBook);
        uint256 userBalance = baseToken.balanceOf(Alice);
        depositSellOrder(Alice, 20, 110);
        assertEq(baseToken.balanceOf(OrderBook), OrderBookBalance + 20 * WAD);
        assertEq(baseToken.balanceOf(Alice), userBalance - 20 * WAD);
        checkOrderQuantity(1, 20);
    }

    // Make two orders, correctly adjusts external balances
    function test_DepositTwoBuyOrders() public {
        uint256 OrderBookBalance = quoteToken.balanceOf(OrderBook);
        uint256 userBalance = quoteToken.balanceOf(Alice);
        depositBuyOrder(Alice, 2000, 90);
        depositBuyOrder(Alice, 3000, 95);
        assertEq(quoteToken.balanceOf(OrderBook), OrderBookBalance + 5000 * WAD);
        assertEq(quoteToken.balanceOf(Alice), userBalance - 5000 * WAD);
        checkOrderQuantity(Alice_Order, 2000);
        checkOrderQuantity(Alice_Order + 1, 3000);
    }

    // Make three orders, correctly adjusts external balances
    function test_DepositThreeOrders() public {
        uint256 bookBalance = baseToken.balanceOf(OrderBook);
        depositSellOrder(Alice, 20, 110);
        depositBuyOrder(Alice, 2000, 90);
        depositSellOrder(Bob, 15, 105);
        assertEq(baseToken.balanceOf(OrderBook), bookBalance + 35 * WAD);
        assertEq(book.countOrdersOfUser(Alice), 2);
        assertEq(book.countOrdersOfUser(Bob), 1);
        assertEq(book.countOrdersOfUser(Carol), 0);
    }

    // When deposit is less than min deposit, revert
    function test_RevertBuyOrderIfZeroDeposit() public {
        vm.expectRevert("Deposit too small (10)"); // confusing error message
        depositBuyOrder(Alice, 99, 90);
        checkOrderQuantity(Alice_Order, 0);
    }

    function test_RevertSellOrderIfZeroDeposit() public {
        vm.expectRevert("Deposit too small (10)");
        depositSellOrder(Alice, 1, 110);
        checkOrderQuantity(Alice_Order, 0);
    }

    // When price is zero, revert
    function test_RevertBuyOrderIfZeroPrice() public {
        vm.expectRevert("Must be positive");
        depositBuyOrder(Alice, 1000, 0);
        checkOrderQuantity(Alice_Order, 0);
    }

    function test_RevertSellOrderIfZeroPrice() public {
        vm.expectRevert("Must be positive");
        depositSellOrder(Alice, 10, 0);
        checkOrderQuantity(Alice_Order, 0);
    }

    // When an identical order exists, increase deposit of that order
    function test_AggregateIdenticalBuyOrder() public {
        depositBuyOrder(Alice, 3000, 90);
        depositBuyOrder(Alice, 2000, 90);
        (,, uint256 quantity1,,,) = book.orders(1);
        (,, uint256 quantity2,,,) = book.orders(2);
        assertEq(quantity1, (3000 + 2000) * WAD);
        assertEq(quantity2, 0);
        assertEq(book.countOrdersOfUser(Alice), 1);
        checkOrderQuantity(Alice_Order, 5000);
        checkOrderQuantity(Alice_Order + 1, 0);
    }

    function test_AggregateIdenticalSellOrder() public {
        depositSellOrder(Alice, 30, 110);
        depositSellOrder(Alice, 20, 110);
        (,, uint256 quantity1,,,) = book.orders(1);
        (,, uint256 quantity2,,,) = book.orders(2);
        assertEq(quantity1, 50 * WAD);
        assertEq(quantity2, 0);
        assertEq(book.countOrdersOfUser(Alice), 1);
        checkOrderQuantity(Alice_Order, 50);
    }
    
    // revert if 0 quantity via increaseDeposit() if same limit price
    function test_IncreaseBuyOrderZeroQuantity() public {
        depositBuyOrder(Alice, 3000, 90);
        vm.expectRevert("Must be positive");
        depositBuyOrder(Alice, 0, 90);
        checkOrderQuantity(Alice_Order, 3000);
    }

    function test_IncreaseSellOrderZeroQuantity() public {
        depositSellOrder(Alice, 30, 110);
        setPriceFeed(80);
        vm.expectRevert("Must be positive");
        depositSellOrder(Alice, 0, 110);
        checkOrderQuantity(Alice_Order, 30);
    }

    // increase Deposit correctly adjusts balances
    function test_IncreaseBuyOrderCheckBalances() public {
        uint256 bookBalance = quoteToken.balanceOf(OrderBook);
        uint256 userBalance = quoteToken.balanceOf(Alice);
        depositBuyOrder(Alice, 2000, 90);
        depositBuyOrder(Alice, 3000, 90);
        assertEq(quoteToken.balanceOf(OrderBook), bookBalance + 5000 * WAD);
        assertEq(quoteToken.balanceOf(Alice), userBalance - 5000 * WAD);
        checkOrderQuantity(Alice_Order, 5000);
    }

    function test_IncreaseSellOrderCheckBalances() public {
        uint256 bookBalance = baseToken.balanceOf(OrderBook);
        uint256 userBalance = baseToken.balanceOf(Alice);
        depositSellOrder(Alice, 20, 110);
        depositSellOrder(Alice, 30, 110);
        assertEq(baseToken.balanceOf(OrderBook), bookBalance + 50 * WAD);
        assertEq(baseToken.balanceOf(Alice), userBalance - 50 * WAD);
        checkOrderQuantity(Alice_Order, 50);
    }

    // add new order if same order but different maker
    function test_AddSameBuyOrderDifferentMaker() public {
        depositBuyOrder(Alice, 3000, 90);
        depositBuyOrder(Bob, 2000, 90);
        checkOrderQuantity(1, 3000);
        checkOrderQuantity(2, 2000);
        assertEq(book.countOrdersOfUser(Alice), 1);
        assertEq(book.countOrdersOfUser(Bob), 1);
        checkOrderQuantity(Alice_Order, 3000);
        checkOrderQuantity(Bob_Order, 2000);
    }

    // add order id in depositIds in users
    function test_AddDepositIdInUsers() public {
        checkUserDepositId(Alice, 0, 0);
        depositBuyOrder(Alice, 3000, 90);
        checkUserDepositId(Alice, 0, Alice_Order);
        checkUserDepositId(Alice, 1, 0);
        depositBuyOrder(Alice, 2000, 95);
        checkUserDepositId(Alice, 0, Alice_Order);
        checkUserDepositId(Alice, 1, Alice_Order + 1);
    }

    // user posts more than max number of orders
    function test_OrdersForUserExceedLimit() public {
        depositBuyOrder(Alice, 3000, 90);
        depositSellOrder(Alice, 30, 110);
        vm.expectRevert("Max number of orders reached for user");
        depositBuyOrder(Alice, 4000, 80);
    }

    // user switches from borrowable buy order to non borrowable
    function test_SwitchBuyToNonBorrowable() public {
        depositBuyOrder(Alice, 3000, 90);
        checkOrderIsBorrowable(Alice_Order);
        makeOrderNonBorrowable(Alice, Alice_Order);
        checkOrderIsNonBorrowable(Alice_Order);
    }

    // user switches from non borrowable buy order to borrowable
    function test_SwitchBuyToBorrowable() public {
        depositBuyOrder(Alice, 3000, 90);
        makeOrderNonBorrowable(Alice, Alice_Order);
        makeOrderBorrowable(Alice, Alice_Order);
        checkOrderIsBorrowable(Alice_Order);
    }

    // user switches from borrowable sell orderto non borrowable
    function test_SwitchSellToNonBorrowable() public {
        depositSellOrder(Alice, 30, 110);
        checkOrderIsBorrowable(Alice_Order);
        makeOrderNonBorrowable(Alice, Alice_Order);
        checkOrderIsNonBorrowable(Alice_Order);
    }

    // user switches from non borrowable sell order to borrowable
    function test_SwitchSellToBorrowable() public {
        depositSellOrder(Alice, 30, 110);
        makeOrderNonBorrowable(Alice, Alice_Order);
        makeOrderBorrowable(Alice, Alice_Order);
        checkOrderIsBorrowable(Alice_Order);
    }
}
