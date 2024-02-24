// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
//import "forge-std/console.sol";
import {Setup} from "./Setup.sol";
import {MathLib, WAD} from "../lib/MathLib.sol";

contract TestDeposit is Setup {

    // if new limit order, create order in mapping orders
    // market price set initially at 2001
    // deposit buy order at initial price = 2000 = limit price pool(0) < market price

    function test_DepositBuyOrder() public depositBuy(LowPriceId) {
        // vm.warp(0);
        (int24 poolId,
        address maker,
        int24 pairedPoolId,
        uint256 quantity,
        uint256 orderWeightedRate,
        bool isBuyOrder
        )
        = book.orders(FirstOrderId);
        assertEq(poolId, LowPriceId);
        assertEq(poolId, FirstPoolId);
        assertEq(maker, Alice);
        assertEq(pairedPoolId, HighPriceId);
        assertEq(quantity, DepositQT);
        assertEq(orderWeightedRate, orderWeightedRate);
        assertEq(isBuyOrder, BuyOrder);
        assertEq(initialPriceWAD, book.limitPrice(FirstPoolId));
    }

    // market price set initially at 2001
    // set low price at 1999
    // deposit sell order at initial price = 2000 > limit price pool(0)

    function test_DepositSellOrder() public setLowPrice() depositSell(FirstPoolId) {
        (int24 poolId,
        address maker,
        int24 pairedPoolId,
        uint256 quantity,
        uint256 orderWeightedRate,
        bool isBuyOrder)
        = book.orders(FirstOrderId);
        assertEq(poolId, FirstPoolId);
        assertEq(maker, Bob);
        assertEq(pairedPoolId, FirstPoolId - 1);
        assertEq(quantity, DepositBT);
        assertEq(orderWeightedRate, 1 * WAD);
        assertEq(isBuyOrder, SellOrder);
        assertEq(initialPriceWAD, book.limitPrice(FirstPoolId));
    }

    // Deposit buy order correctly adjusts user deposit
    function test_DepositBuyOrderCheckUserDeposit() public depositBuy(FirstPoolId) {
        // first row of user.depositIds[] is 1
        checkUserDepositId(Alice, 0, FirstOrderId);
    }

    // Deposit sell order correctly adjusts user deposit
    function test_DepositSellOrderCheckUserDeposit() public setLowPrice() depositSell(FirstPoolId) {
        // first row of user.depositIds[] is 1
        checkUserDepositId(Bob, 0, FirstOrderId);
    }

    // Deposit buy order correctly adjusts balances
    function test_DepositBuyOrderCheckBalances() public {
        uint256 OrderBookBalance = quoteToken.balanceOf(OrderBook);
        uint256 userBalance = quoteToken.balanceOf(Alice);
        depositBuyOrder(Alice, FirstPoolId, DepositQT, FirstPoolId + 1);
        assertEq(quoteToken.balanceOf(OrderBook), OrderBookBalance + DepositQT);
        assertEq(quoteToken.balanceOf(Alice), userBalance - DepositQT);
        checkOrderQuantity(FirstOrderId, DepositQT);
    }

    // Deposit sell order correctly adjusts balances
    function test_DepositSellOrderCheckBalances() public setLowPrice() {
        uint256 orderBookBalance = baseToken.balanceOf(OrderBook);
        uint256 userBalance = baseToken.balanceOf(Bob);
        depositSellOrder(Bob, FirstPoolId, DepositBT, FirstPoolId - 1);
        assertEq(baseToken.balanceOf(OrderBook), orderBookBalance + DepositBT);
        assertEq(baseToken.balanceOf(Bob), userBalance - DepositBT);
        checkOrderQuantity(FirstOrderId, DepositBT);
    }

    // // Two orders correctly adjusts external balances
    function test_DepositTwoBuyOrders() public {
        uint256 orderBookBalance = quoteToken.balanceOf(OrderBook);
        uint256 userBalance = quoteToken.balanceOf(Alice);
        depositBuyOrder(Alice, FirstPoolId, DepositQT, FirstPoolId + 1);
        depositBuyOrder(Alice, FirstPoolId - 1, 2 * DepositQT, FirstPoolId);
        assertEq(quoteToken.balanceOf(OrderBook), orderBookBalance + 3 * DepositQT);
        assertEq(quoteToken.balanceOf(Alice), userBalance - 3 * DepositQT);
        checkOrderQuantity(FirstOrderId, DepositQT);
        checkOrderQuantity(SecondOrderId, 2 * DepositQT);
    }

    // Three buy orders correctly adjusts external balances
    function test_DepositThreeOrders() public {
        setPriceFeed(2100);
        uint256 orderBookBalance = quoteToken.balanceOf(OrderBook);
        uint256 userBalance = quoteToken.balanceOf(Alice);
        depositBuyOrder(Alice, FirstPoolId, DepositQT, FirstPoolId + 1);
        depositBuyOrder(Alice, FirstPoolId - 1, 2 * DepositQT, FirstPoolId);
        depositBuyOrder(Alice, FirstPoolId - 2, DepositQT, FirstPoolId - 1);
        assertEq(quoteToken.balanceOf(OrderBook), orderBookBalance + 4 * DepositQT);
        assertEq(quoteToken.balanceOf(Alice), userBalance - 4 * DepositQT);
        checkOrderQuantity(FirstOrderId, DepositQT);
        checkOrderQuantity(SecondOrderId, 2 * DepositQT);
        checkOrderQuantity(ThirdOrderId, DepositQT);
    }

    // Three sell orders correctly adjusts external balances
    function test_DepositThreeSellOrders() public setLowPrice() {
        uint256 orderBookBalance = baseToken.balanceOf(OrderBook);
        uint256 userBalance = baseToken.balanceOf(Alice);
        depositSellOrder(Alice, FirstPoolId, DepositBT, FirstPoolId - 1);
        depositSellOrder(Alice, FirstPoolId + 1, 2 * DepositBT, FirstPoolId);
        depositSellOrder(Alice, FirstPoolId + 2, DepositBT, FirstPoolId + 1);
        assertEq(baseToken.balanceOf(OrderBook), orderBookBalance + 4 * DepositBT);
        assertEq(baseToken.balanceOf(Alice), userBalance - 4 * DepositBT);
        checkOrderQuantity(FirstOrderId, DepositBT);
        checkOrderQuantity(SecondOrderId, 2 * DepositBT);
        checkOrderQuantity(ThirdOrderId, DepositBT);
    }

    // When buy order deposit is zero, revert
    function test_RevertBuyOrderIfZeroDeposit() public {
        vm.expectRevert("Not enough deposited");
        depositBuyOrder(Alice, FirstPoolId, 0, FirstPoolId + 1);
        checkOrderQuantity(FirstOrderId, 0);
    }

    function test_RevertSellOrderIfZeroDeposit() public setLowPrice() {
        vm.expectRevert("Not enough deposited");
        depositSellOrder(Alice, FirstPoolId, 0, FirstPoolId - 1);
        checkOrderQuantity(FirstOrderId, 0);
    }

    // When deposit is less than min deposit, revert
    function test_RevertBuyOrderIfLessMinDeposit() public {
        vm.expectRevert("Not enough deposited");
        depositBuyOrder(Alice, FirstPoolId, 99 * WAD, FirstPoolId + 1);
        checkOrderQuantity(FirstOrderId, 0);
    }

    function test_RevertSellOrderIfLessMinDeposit() public setLowPrice() {
        vm.expectRevert("Not enough deposited");
        depositSellOrder(Alice, FirstPoolId, 1 * WAD / 10, FirstPoolId - 1);
        checkOrderQuantity(FirstOrderId, 0);
    }

    // When identical buy order exists, increase deposit
    function test_AggregateIdenticalBuyOrder() public {
        depositBuyOrder(Alice, FirstPoolId, DepositQT, FirstPoolId + 1);
        depositBuyOrder(Alice, FirstPoolId, 2 * DepositQT, FirstPoolId + 1);
        checkOrderQuantity(FirstOrderId, 3 * DepositQT);
        checkOrderQuantity(FirstOrderId + 1, 0);
    }

    // When identical sell order exists, increase deposit
    function test_AggregateIdenticalSellOrder() public setLowPrice() {
        depositSellOrder(Alice, FirstPoolId, DepositBT, FirstPoolId - 1);
        depositSellOrder(Alice, FirstPoolId, 2 * DepositBT, FirstPoolId - 1);
        checkOrderQuantity(FirstOrderId, 3 * DepositBT);
        checkOrderQuantity(FirstOrderId + 1, 0);
    }

    // Identical buy orders, except pairedPriceId => two separate orders
    function test_SeparateNearIdenticalBuyOrder() public {
        depositBuyOrder(Alice, FirstPoolId, DepositQT, FirstPoolId + 1);
        depositBuyOrder(Alice, FirstPoolId, 2 * DepositQT, FirstPoolId + 2);
        checkOrderQuantity(FirstOrderId, DepositQT);
        checkOrderQuantity(FirstOrderId + 1, 2 * DepositQT);
    }

    // Identical sell orders, except pairedPriceId => two separate orders
    function test_SeparateNearIdenticalSellOrder() public setLowPrice() {
        depositSellOrder(Alice, FirstPoolId, DepositBT, FirstPoolId - 1);
        depositSellOrder(Alice, FirstPoolId, 2 * DepositBT, FirstPoolId - 2);
        checkOrderQuantity(FirstOrderId, DepositBT);
        checkOrderQuantity(FirstOrderId + 1, 2 * DepositBT);
    }

    // Identical buy order Deposit correctly adjusts balances
    function test_IncreaseBuyOrderCheckBalances() public {
        uint256 bookBalance = quoteToken.balanceOf(OrderBook);
        uint256 userBalance = quoteToken.balanceOf(Alice);
        depositBuyOrder(Alice, FirstPoolId, DepositQT, FirstPoolId + 1);
        depositBuyOrder(Alice, FirstPoolId, 2 * DepositQT, FirstPoolId + 1);
        assertEq(quoteToken.balanceOf(OrderBook), bookBalance + 3 * DepositQT);
        assertEq(quoteToken.balanceOf(Alice), userBalance - 3 * DepositQT);
    }

    // Identical Deposit correctly adjusts balances
    function test_IncreaseSellOrderCheckBalances() public setLowPrice() {
        uint256 bookBalance = baseToken.balanceOf(OrderBook);
        uint256 userBalance = baseToken.balanceOf(Alice);
        depositSellOrder(Alice, FirstPoolId, DepositBT, FirstPoolId - 1);
        depositSellOrder(Alice, FirstPoolId, 2 * DepositBT, FirstPoolId - 1);
        assertEq(baseToken.balanceOf(OrderBook), bookBalance + 3 * DepositBT);
        assertEq(baseToken.balanceOf(Alice), userBalance - 3 * DepositBT);
    }

    // add order id in depositIds in users
    function test_AddDepositIdInUsers() public {
        checkUserDepositId(Alice, 0, NoOrderId);
        depositBuyOrder(Alice, FirstPoolId, DepositQT, FirstPoolId + 1);
        checkUserDepositId(Alice, 0, FirstOrderId);
        checkUserDepositId(Alice, 1, NoOrderId);
        depositBuyOrder(Alice, FirstPoolId - 1, DepositQT, FirstPoolId);
        checkUserDepositId(Alice, 0, FirstOrderId);
        checkUserDepositId(Alice, 1, SecondOrderId);
        checkUserDepositId(Alice, 2, NoOrderId);
    }

    // user posts more than max number of orders
    function test_OrdersForUserExceedLimit() public {
        uint256 maxOrders = book.MAX_ORDERS() - 1;
        for (uint256 i = 0; i <= maxOrders; i++) {
            int24 j = int24(int256(i));
            depositBuyOrder(Alice, FirstPoolId - j, DepositQT / maxOrders, FirstPoolId - j + 1);
        }
        for (uint256 i = 0; i <= maxOrders; i++) {
            checkOrderQuantity(i+1, DepositQT / maxOrders);
        }
        int24 maxInt24 = int24(int256(maxOrders));
        vm.expectRevert("Max orders reached");
        depositBuyOrder(Alice, FirstPoolId - maxInt24 - 1, DepositQT / maxOrders, FirstPoolId - maxInt24);
    }

    // revert if inconsistent paired prices in buy order
    function test_RevertBuyOrderInconsistentPairedPrice() public {
        vm.expectRevert("Inconsistent prices");
        depositBuyOrder(Alice, FirstPoolId, DepositQT, FirstPoolId - 1);
    }

    // revert if inconsistent paired prices in sell order
    function test_RvertSellOrderInconsistentPairedPrice() public setLowPrice() {
        vm.expectRevert("Inconsistent prices");
        depositSellOrder(Alice, FirstPoolId, DepositBT, FirstPoolId + 1);
    }

    // revert if same paired prices in buy order
    function test_RevertBuyOrderSamePairedPrice() public {
        vm.expectRevert("Inconsistent prices");
        depositBuyOrder(Alice, FirstPoolId, DepositQT, FirstPoolId);
    }

    // revert if same paired prices in sell order
    function test_RevertSellOrderSamePairedPrice() public setLowPrice() {
        vm.expectRevert("Inconsistent prices");
        depositSellOrder(Alice, FirstPoolId, DepositBT, FirstPoolId);
    }

    // User excess collateral is correct after deposit in buy order
    function test_DepositBuyOrderExcessCollateral() public depositBuy(FirstPoolId) {
        uint256 userEC = book.getUserExcessCollateral(Alice, 0, book.ALTV());
        assertEq(userEC, book.ALTV() * DepositQT / book.limitPrice(FirstPoolId));
    }

    // User excess collateral is correct after deposit in sell order
    function test_DepositSellOrderExcessCollateral() public setLowPrice() depositSell(FirstPoolId) {
        uint256 userEC = book.getUserExcessCollateral(Bob, 0, book.ALTV());
        assertEq(userEC, book.ALTV() * DepositBT / WAD);
    }

    // // Paired price in buy order is used in paired limit order after taking
    // function test_BuyOrderPairedPricereportsOk() public {
    //     depositBuyOrderWithPairedPrice(Alice, 1800, 90, 110);
    //     setPriceFeed(70);
    //     take(Bob, Alice_Order, 1800);
    //     checkOrderPrice(Alice_Order + 1, 110);
    //     checkOrderPairedPrice(Alice_Order + 1, 90);
    //     checkOrderQuantity(Alice_Order + 1, 1800 / 90);
    // }

    // // Paired price in sell order is used in paired limit order after taking
    // function test_SellOrderPairedPricereportsOk() public {
    //     depositSellOrderWithPairedPrice(Alice, 20, 110, 90);
    //     setPriceFeed(120);
    //     take(Bob, Alice_Order, 20);
    //     checkOrderPrice(Alice_Order + 1, 90);
    //     checkOrderPairedPrice(Alice_Order + 1, 110);
    //     checkOrderQuantity(Alice_Order + 1, 20 * 110);
    // }
}
