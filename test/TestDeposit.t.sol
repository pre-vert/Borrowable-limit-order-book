// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Setup} from "./Setup.sol";
import {MathLib, WAD} from "../lib/MathLib.sol";

contract TestDeposit is Setup {

    // if new limit order, create order in mapping orders
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

    // Transfer tokens to contract, correctly adjusts balances
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
        vm.expectRevert("Deposit too small"); // confusing error message
        depositBuyOrder(Alice, 99, 90);
        checkOrderQuantity(Alice_Order, 0);
    }

    function test_RevertSellOrderIfZeroDeposit() public {
        vm.expectRevert("Deposit too small");
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
        depositBuyOrder(Alice, 1000, 95);
        vm.expectRevert("Max orders reached");
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

    // user switches from borrowable sell order to non borrowable
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

    // filling a consistent paired price in buy order is ok
    function test_BuyOrderConsistentPairedPriceIsOk() public {
        depositBuyOrderWithPairedPrice(Alice, 1000, 90, 110);
        checkOrderPrice(Alice_Order, 90);
        checkOrderPairedPrice(Alice_Order, 110);
    }

    // filling a consistent paired price in sell order is ok
    function test_SellOrderConsistentPairedPriceIsOk() public {
        depositSellOrderWithPairedPrice(Alice, 10, 110, 90);
        checkOrderPrice(Alice_Order, 110);
        checkOrderPairedPrice(Alice_Order, 90);
    }
    
    // Check that filling 0 in paired price while depositing sets buy order's paired price to limit price + 10%
    function test_SetBuyOrderPairedPriceToZeroOk() public {
        depositBuyOrderWithPairedPrice(Alice, 1000, 90, 0);
        checkOrderPairedPrice(Alice_Order, 90 + 90 / 10);
    }

    // Check that filling 0 in paired price while depositing sets buy order's paired price to limit price - 10%
    function test_SetSellOrderPairedPriceToZeroOk() public {
        depositSellOrderWithPairedPrice(Alice, 10, 110, 0);
        checkOrderPairedPrice(Alice_Order, 110 - 110/11);
    }

    // filling an inconsistent paired price in buy order reverts
    function test_RevertBuyOrderInconsistentPairedPrice() public {
        vm.expectRevert("Inconsistent prices");
        depositBuyOrderWithPairedPrice(Alice, 1000, 90, 80);
    }

    // filling an inconsistent paired price in sell order reverts
    function test_RevertSellOrderInconsistentPairedPrice() public {
        vm.expectRevert("Inconsistent prices");
        depositSellOrderWithPairedPrice(Alice, 10, 110, 120);
    }

    // Paired price in buy order is used in paired limit order after taking
    function test_BuyOrderPairedPricereportsOk() public {
        depositBuyOrderWithPairedPrice(Alice, 1800, 90, 110);
        setPriceFeed(70);
        take(Bob, Alice_Order, 1800);
        checkOrderPrice(Alice_Order + 1, 110);
        checkOrderPairedPrice(Alice_Order + 1, 90);
        checkOrderQuantity(Alice_Order + 1, 1800 / 90);
    }

    // Paired price in sell order is used in paired limit order after taking
    function test_SellOrderPairedPricereportsOk() public {
        depositSellOrderWithPairedPrice(Alice, 20, 110, 90);
        setPriceFeed(120);
        take(Bob, Alice_Order, 20);
        checkOrderPrice(Alice_Order + 1, 90);
        checkOrderPairedPrice(Alice_Order + 1, 110);
        checkOrderQuantity(Alice_Order + 1, 20 * 110);
    }
}
