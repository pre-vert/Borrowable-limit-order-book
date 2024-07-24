// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
//import "forge-std/console.sol";
import {Setup} from "./Setup.sol";
import {MathLib, WAD} from "../lib/MathLib.sol";

contract TestDeposit is Setup {

    // if new limit order, create order in orders
    // market price set initially at 4001
    // deposit buy order at genesis limit price = 4000 = limit price pool(0) < market price

    function test_DepositSimpleBuyOrder() public depositBuy(B) {
        (uint256 poolId,
        address maker,
        uint256 pairedPoolId,
        uint256 quantity,
        uint256 orderWeightedRate
        )
        = book.orders(FirstOrderId);
        assertEq(poolId, B);
        assertEq(maker, Alice);
        assertEq(pairedPoolId, B + 1);
        assertEq(quantity, DepositQT);
        assertEq(orderWeightedRate, orderWeightedRate);
        assertEq(genesisLimitPriceWAD, book.limitPrice(B));
        assertEq(getAvailableAssets(B), book.PHI() * DepositQT / WAD);
        assertEq(book.viewUserQuoteDeposit(FirstOrderId), DepositQT);
        assertEq(book.viewPoolDeposit(B), DepositQT);
        assertEq(book.viewUserTotalDeposits(Alice, InQuoteToken), DepositQT);
    }

    // // market price set initially at 4001
    // // set low price at 3999
    // // deposit sell order at initial price = 4000 > limit price pool(0)

    function test_DepositSellOrderSimple() public setLowPrice() depositSell(B + 1) {
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
        assertEq(orderWeightedRate, 0);
        assertEq(genesisLimitPriceWAD, book.limitPrice(B));
        assertEq(book.viewUserTotalDeposits(Bob, InBaseToken), DepositBT);
    }

    // deposit base assets in account correctly adjusts balance
    function test_DepositInBaseAccount() public depositInAccount(DepositBT) {
        checkUserBaseAccount(Bob, DepositBT);
        checkUserQuoteAccount(Bob, 0);
        assertEq(book.viewUserTotalDeposits(Bob, InBaseToken), DepositBT);
    }

    // deposit base assets twice in account correctly adjusts balance
    function test_DepositTwiceInBaseAccount() public depositInAccount(DepositBT) depositInAccount(2 * DepositBT) {
        checkUserBaseAccount(Bob, 3 * DepositBT);
        checkUserQuoteAccount(Bob, 0);
        assertEq(book.viewUserTotalDeposits(Bob, InBaseToken), 3 * DepositBT);
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
        assertEq(getOrderQuantity(FirstOrderId), DepositQT);
    }

    // Deposit sell order correctly adjusts balances
    function test_DepositSellOrderCheckBalances() public setLowPrice() {
        uint256 orderBookBalance = baseToken.balanceOf(OrderBook);
        uint256 userBalance = baseToken.balanceOf(Bob);
        depositSellOrder(Bob, B + 1, DepositBT);
        assertEq(baseToken.balanceOf(OrderBook), orderBookBalance + DepositBT);
        assertEq(baseToken.balanceOf(Bob), userBalance - DepositBT);
        assertEq(getOrderQuantity(FirstOrderId), DepositBT);
    }

    // // Two orders correctly adjusts external balances
    function test_DepositTwoBuyOrders() public {
        uint256 orderBookBalance = quoteToken.balanceOf(OrderBook);
        uint256 userBalance = quoteToken.balanceOf(Alice);
        depositBuyOrder(Alice, B, DepositQT, B + 1);
        depositBuyOrder(Alice, B - 2, 2 * DepositQT, B - 1);
        assertEq(quoteToken.balanceOf(OrderBook), orderBookBalance + 3 * DepositQT);
        assertEq(quoteToken.balanceOf(Alice), userBalance - 3 * DepositQT);
        assertEq(getOrderQuantity(FirstOrderId), DepositQT);
        assertEq(getOrderQuantity(SecondOrderId), 2 * DepositQT);
        assertEq(book.viewUserTotalDeposits(Alice, InQuoteToken), 3 * DepositQT);
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
        assertEq(getOrderQuantity(FirstOrderId), DepositQT);
        assertEq(getOrderQuantity(SecondOrderId), 2 * DepositQT);
        assertEq(getOrderQuantity(ThirdOrderId), DepositQT);
        assertEq(book.viewUserTotalDeposits(Alice, InQuoteToken), 4 * DepositQT);
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
        assertEq(getOrderQuantity(FirstOrderId), DepositBT);
        assertEq(getOrderQuantity(SecondOrderId), 2 * DepositBT);
        assertEq(getOrderQuantity(ThirdOrderId), DepositBT);
        assertEq(book.viewUserTotalDeposits(Alice, InBaseToken), 4 * DepositBT);
    }

    // Deposit base asset in account correctly adjusts external balances
    function test_DepositBaseAccountCheckBalances() public {
        uint256 OrderBookBalance = baseToken.balanceOf(OrderBook);
        uint256 userBalance = baseToken.balanceOf(Bob);
        depositInBaseAccount(Bob, DepositBT);
        assertEq(baseToken.balanceOf(OrderBook), OrderBookBalance + DepositBT);
        assertEq(baseToken.balanceOf(Bob), userBalance - DepositBT);
    }

    // When buy order deposit is zero, revert
    function test_RevertBuyOrderIfZeroDeposit() public {
        vm.expectRevert("Deposit zero");
        depositBuyOrder(Alice, B, 0, B + 1);
    }

    // When sell order deposit is zero, revert
    function test_RevertSellOrderIfZeroDeposit() public setLowPrice() {
        vm.expectRevert("Deposit zero");
        depositSellOrder(Alice, B + 1, 0);
    }

    // deposit zero base assets in account reverts
    function test_DepositZeroInBaseAccount() public {
        vm.expectRevert("Deposit zero");
        depositInBaseAccount(Bob, 0);
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
        assertEq(getOrderQuantity(FirstOrderId), 3 * DepositQT);
        assertEq(getOrderQuantity(SecondOrderId), 0);
        // checkOrderQuantity(FirstOrderId + 1, 0);
    }

    // When identical sell order exists, increase deposit
    function test_AggregateIdenticalSellOrder() public setLowPrice() {
        depositSellOrder(Alice, B + 1, DepositBT);
        depositSellOrder(Alice, B + 1, 2 * DepositBT);
        assertEq(getOrderQuantity(FirstOrderId), 3 * DepositBT);
        assertEq(getOrderQuantity(SecondOrderId), 0);
        //checkOrderQuantity(FirstOrderId + 1, 0);
    }

    // Identical buy orders, except pairedPriceId => two separate orders
    function test_SeparateNearIdenticalBuyOrder() public {
        depositBuyOrder(Alice, B, DepositQT, B + 1);
        depositBuyOrder(Alice, B, 2 * DepositQT, B + 3);
        assertEq(getOrderQuantity(FirstOrderId), DepositQT);
        assertEq(getOrderQuantity(SecondOrderId), 2 * DepositQT);
        assertEq(book.viewUserTotalDeposits(Alice, InQuoteToken), 3 * DepositQT);
    }

    // Identical two sell orders => merged orders
    function test_MergeIdenticalSellOrder() public setLowPrice() {
        depositSellOrder(Alice, B + 1, DepositBT);
        depositSellOrder(Alice, B + 1, 2 * DepositBT);
        assertEq(getOrderQuantity(FirstOrderId), 3 * DepositBT);
        assertEq(getOrderQuantity(SecondOrderId), 0);
        //checkOrderQuantity(FirstOrderId + 1, 0);
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
            assertEq(getOrderQuantity(i + 1), DepositQT / maxOrders);
            // checkOrderQuantity(i + 1, DepositQT / maxOrders);
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

    // User excess collateral is correct after deposit in base account
    function test_DepositInAccountExcessCollateral() public depositInAccount(DepositBT) {
       (bool isPositive, uint256 userEC) = book.viewUserExcessCollateral(Bob, 0);
        assertEq(userEC, DepositBT);
        assertEq(isPositive, true);
    }

}
