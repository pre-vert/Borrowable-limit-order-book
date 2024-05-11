// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
//import "forge-std/console.sol";
import {Setup} from "./Setup.sol";
import {MathLib, WAD} from "../lib/MathLib.sol";

contract TestDeposit is Setup {

    // if new limit order, create order in orders
    // market price set initially at 2001
    // deposit buy order at genesis limit price = 2000 = limit price pool(0) < market price

    function test_DepositBuyOrder() public depositBuy(B) {
        // vm.warp(0);
        (uint256 poolId,
        address maker,
        uint256 pairedPoolId,
        uint256 quantity,
        uint256 orderWeightedRate
        )
        = book.orders(FirstOrderId);
        assertEq(poolId, B);
        assertEq(maker, Alice);
        assertEq(pairedPoolId, B + 3);
        assertEq(quantity, DepositQT);
        assertEq(orderWeightedRate, orderWeightedRate);
        assertEq(genesisLimitPriceWAD, book.limitPrice(B));
    }

    // // market price set initially at 2001
    // // set low price at 1999
    // // deposit sell order at initial price = 2000 > limit price pool(0)

    function test_DepositSellOrder() public setLowPrice() depositSell(B + 1) {
        (uint256 poolId,
        address maker,
        uint256 pairedPoolId,
        uint256 quantity,
        uint256 orderWeightedRate)
        = book.orders(FirstOrderId);
        assertEq(poolId, B + 1);
        assertEq(maker, Bob);
        assertEq(pairedPoolId, 0);
        assertEq(quantity, DepositBT);
        assertEq(orderWeightedRate, WAD);
        assertEq(genesisLimitPriceWAD, book.limitPrice(B));
    }

    // Deposit buy order correctly adjusts user deposit
    function test_DepositBuyOrderCheckUserDeposit() public depositBuy(B) {
        // first row of user.depositIds[0] is 1
        checkUserDepositId(Alice, 0, FirstOrderId);
    }

    // Deposit sell order correctly adjusts user deposit
    function test_DepositSellOrderCheckUserDeposit() public setLowPrice() depositSell(B + 1) {
        // first row of user.depositIds[0] is 1
        checkUserDepositId(Bob, 0, FirstOrderId);
    }

    // Deposit two buy order correctly adjusts user deposit
    function test_DepositTwoBuyOrderCheckUserDeposit() public depositBuy(B) depositBuy(B - 2) {
        // first row of user.depositIds[0] is 1
        checkUserDepositId(Alice, 1, SecondOrderId);
    }

    // Choose paired buy order in same pool is ok
    function test_ChoosePairedBuyOrderInSamePoolIsOk() public {
        depositBuyOrder(Alice, B, DepositQT, B + 1);
    }

    // Choose paired sell order in same pool is ok
    function test_ChoosePairedSellOrderInSamePoolIsOk() public setLowPrice() {
        depositSellOrder(Alice, B + 1, DepositBT);
    }

    // Choose paired buy order in wrong pool reverts
    function test_ChoosePairedBuyOrderInWrongPoolReverts() public {
        vm.expectRevert("Wrong paired pool");
        depositBuyOrder(Alice, B, DepositQT, B + 2);
    }

    // Deposit buy order correctly adjusts balances
    function test_DepositBuyOrderCheckBalances() public {
        uint256 OrderBookBalance = quoteToken.balanceOf(OrderBook);
        uint256 userBalance = quoteToken.balanceOf(Alice);
        depositBuyOrder(Alice, B, DepositQT, B + 1);
        assertEq(quoteToken.balanceOf(OrderBook), OrderBookBalance + DepositQT);
        assertEq(quoteToken.balanceOf(Alice), userBalance - DepositQT);
        checkOrderQuantity(FirstOrderId, DepositQT);
    }

    // Deposit sell order correctly adjusts balances
    function test_DepositSellOrderCheckBalances() public setLowPrice() {
        uint256 orderBookBalance = baseToken.balanceOf(OrderBook);
        uint256 userBalance = baseToken.balanceOf(Bob);
        depositSellOrder(Bob, B + 1, DepositBT);
        assertEq(baseToken.balanceOf(OrderBook), orderBookBalance + DepositBT);
        assertEq(baseToken.balanceOf(Bob), userBalance - DepositBT);
        checkOrderQuantity(FirstOrderId, DepositBT);
    }

    // // Two orders correctly adjusts external balances
    function test_DepositTwoBuyOrders() public {
        uint256 orderBookBalance = quoteToken.balanceOf(OrderBook);
        uint256 userBalance = quoteToken.balanceOf(Alice);
        depositBuyOrder(Alice, B, DepositQT, B + 1);
        depositBuyOrder(Alice, B - 2, 2 * DepositQT, B - 1);
        assertEq(quoteToken.balanceOf(OrderBook), orderBookBalance + 3 * DepositQT);
        assertEq(quoteToken.balanceOf(Alice), userBalance - 3 * DepositQT);
        checkOrderQuantity(FirstOrderId, DepositQT);
        checkOrderQuantity(SecondOrderId, 2 * DepositQT);
    }

    // Three buy orders correctly adjusts external balances
    function test_DepositThreeOrders() public {
        setPriceFeed(4100);
        uint256 orderBookBalance = quoteToken.balanceOf(OrderBook);
        uint256 userBalance = quoteToken.balanceOf(Alice);
        depositBuyOrder(Alice, B, DepositQT, B + 1);
        depositBuyOrder(Alice, B - 2, 2 * DepositQT, B - 1);
        depositBuyOrder(Alice, B - 4, DepositQT, B - 3);
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
        depositSellOrder(Alice, B + 1, DepositBT);
        depositSellOrder(Alice, B + 3, 2 * DepositBT);
        depositSellOrder(Alice, B + 5, DepositBT);
        assertEq(baseToken.balanceOf(OrderBook), orderBookBalance + 4 * DepositBT);
        assertEq(baseToken.balanceOf(Alice), userBalance - 4 * DepositBT);
        checkOrderQuantity(FirstOrderId, DepositBT);
        checkOrderQuantity(SecondOrderId, 2 * DepositBT);
        checkOrderQuantity(ThirdOrderId, DepositBT);
    }

    // When buy order deposit is zero, revert
    function test_RevertBuyOrderIfZeroDeposit() public {
        vm.expectRevert("Deposit zero");
        depositBuyOrder(Alice, B, 0, B + 1);
    }

    function test_RevertSellOrderIfZeroDeposit() public setLowPrice() {
        vm.expectRevert("Deposit zero");
        depositSellOrder(Alice, B + 1, 0);
    }

    // When deposit is less than min deposit, revert
    function test_RevertBuyOrderIfLessMinDeposit() public {
        vm.expectRevert("Not enough deposited");
        depositBuyOrder(Alice, B, 99 * WAD, B + 1);
    }

    function test_RevertSellOrderIfLessMinDeposit() public setLowPrice() {
        vm.expectRevert("Not enough deposited");
        depositSellOrder(Alice, B + 1, 1 * WAD / 10);
    }

    // When identical buy orders exist, increase deposit
    function test_AggregateIdenticalBuyOrder() public {
        depositBuyOrder(Alice, B, DepositQT, B + 1);
        depositBuyOrder(Alice, B, 2 * DepositQT, B + 1);
        checkOrderQuantity(FirstOrderId, 3 * DepositQT);
        checkOrderQuantity(FirstOrderId + 1, 0);
    }

    // When identical sell order exists, increase deposit
    function test_AggregateIdenticalSellOrder() public setLowPrice() {
        depositSellOrder(Alice, B + 1, DepositBT);
        depositSellOrder(Alice, B + 1, 2 * DepositBT);
        checkOrderQuantity(FirstOrderId, 3 * DepositBT);
        checkOrderQuantity(FirstOrderId + 1, 0);
    }

    // Identical buy orders, except pairedPriceId => two separate orders
    function test_SeparateNearIdenticalBuyOrder() public {
        depositBuyOrder(Alice, B, DepositQT, B + 1);
        depositBuyOrder(Alice, B, 2 * DepositQT, B + 3);
        checkOrderQuantity(FirstOrderId, DepositQT);
        checkOrderQuantity(FirstOrderId + 1, 2 * DepositQT);
    }

    // Identical two sell orders => merged orders
    function test_MergeIdenticalSellOrder() public setLowPrice() {
        depositSellOrder(Alice, B + 1, DepositBT);
        depositSellOrder(Alice, B + 1, 2 * DepositBT);
        checkOrderQuantity(FirstOrderId, 3 * DepositBT);
        checkOrderQuantity(FirstOrderId + 1, 0);
    }

    // Two identical buy order deposits correctly adjust balances
    function test_IncreaseBuyOrderCheckBalances() public {
        uint256 bookBalance = quoteToken.balanceOf(OrderBook);
        uint256 userBalance = quoteToken.balanceOf(Alice);
        depositBuyOrder(Alice, B, DepositQT, B + 1);
        depositBuyOrder(Alice, B, 2 * DepositQT, B + 1);
        assertEq(quoteToken.balanceOf(OrderBook), bookBalance + 3 * DepositQT);
        assertEq(quoteToken.balanceOf(Alice), userBalance - 3 * DepositQT);
    }

    // Two identical sell order deposits correctly adjust balances
    function test_IncreaseSellOrderCheckBalances() public setLowPrice() {
        uint256 bookBalance = baseToken.balanceOf(OrderBook);
        uint256 userBalance = baseToken.balanceOf(Alice);
        depositSellOrder(Alice, B + 1, DepositBT);
        depositSellOrder(Alice, B + 1, 2 * DepositBT);
        assertEq(baseToken.balanceOf(OrderBook), bookBalance + 3 * DepositBT);
        assertEq(baseToken.balanceOf(Alice), userBalance - 3 * DepositBT);
    }

    // add order id in depositIds in users
    function test_AddDepositIdInUsers() public {
        checkUserDepositId(Alice, 0, NoOrderId);
        depositBuyOrder(Alice, B, DepositQT, B + 1);
        checkUserDepositId(Alice, 0, FirstOrderId);
        checkUserDepositId(Alice, 1, NoOrderId);
        depositBuyOrder(Alice, B - 2, DepositQT, B - 1);
        checkUserDepositId(Alice, 0, FirstOrderId);
        checkUserDepositId(Alice, 1, SecondOrderId);
        checkUserDepositId(Alice, 2, NoOrderId);
    }

    // // user posts more than max number of orders
    function test_OrdersForUserExceedLimit() public {
        uint256 maxOrders = book.MAX_ORDERS() - 1;
        for (uint256 i = 0; i <= maxOrders; i++) {
            depositBuyOrder(Alice, B - 2 * i, DepositQT / maxOrders, B - 2 * i + 1);
        }
        for (uint256 i = 0; i <= maxOrders; i++) {
            checkOrderQuantity(i + 1, DepositQT / maxOrders);
        }
        vm.expectRevert("Max orders reached");
        depositBuyOrder(Alice, B - 2 * (maxOrders + 1), DepositQT / maxOrders, B - 2 * (maxOrders + 1) + 1);
    }

    // revert if inconsistent paired prices in buy order
    function test_RevertBuyOrderInconsistentPairedPrice() public {
        vm.expectRevert("Inconsistent prices");
        depositBuyOrder(Alice, B, DepositQT, B - 1);
    }

    // revert if same paired prices in buy order
    function test_RevertBuyOrderSamePairedPrice() public {
        vm.expectRevert("Wrong paired pool");
        depositBuyOrder(Alice, B, DepositQT, B);
    }

    // User excess collateral is correct after deposit in buy order
    function test_DepositBuyOrderExcessCollateral() public depositBuy(B) {
       (, uint256 userEC) = book.viewUserExcessCollateral(Alice, 0);
        assertEq(userEC, 0);
    }

    // User excess collateral is correct after deposit in sell order
    function test_DepositSellOrderExcessCollateral() public setLowPrice() depositSell(B + 1) {
        (, uint256 userEC) = book.viewUserExcessCollateral(Bob, 0);
        assertEq(userEC, DepositBT);
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
