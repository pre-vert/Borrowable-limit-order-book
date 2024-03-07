// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Setup} from "./Setup.sol";
import {MathLib, WAD} from "../lib/MathLib.sol";

contract TestChangePrice is Setup {

    // // ChangePairedPrice() with a new paired price for buy order changes paired price
    // function test_ChangeBuyOrderPairedPrice() public depositBuy(LowPriceId) {
    //     changePairedPrice(Alice, FirstOrderId, VeryHighPriceId);
    //     checkOrderPairedPrice(FirstOrderId, VeryHighPriceId);
    // }

    // // ChangePairedPrice() with a new paired price for sell order changes paired price
    // function test_ChangeSellOrderPairedPrice() public setLowPrice() depositSell(B ) {
    //     changePairedPrice(Bob, FirstOrderId, B  - 2);
    //     checkOrderPairedPrice(FirstOrderId, B  - 2);
    // }

    // // When caller is not maker of buy order, revert
    // function test_RevertBuyOrderPairedIfNotMaker() public depositBuy(LowPriceId) {
    //     vm.expectRevert("Only maker");
    //     changePairedPrice(Bob, FirstOrderId, VeryHighPriceId);
    // }

    // // When caller is not maker of sell order, revert
    // function test_RevertSellOrderPairedIfNotMaker() public setLowPrice() depositSell(B ) {
    //     vm.expectRevert("Only maker");
    //     changePairedPrice(Carol, FirstOrderId, VeryLowPriceId);
    // }

    // // When new paired price in buy order is in wrong order with limit price, revert
    // function test_RevertBuyOrderPairedIfNotConsistent() public depositBuy(LowPriceId) {
    //     vm.expectRevert("Inconsistent prices");
    //     changePairedPrice(Alice, FirstOrderId, VeryLowPriceId);
    // }

    // // When new paired price in sell order is in wrong order with limit price, revert
    // function test_RevertSellOrderPairedIfNotConsistent() public setLowPrice() depositSell(B ) {
    //     vm.expectRevert("Inconsistent prices");
    //     changePairedPrice(Bob, FirstOrderId, VeryHighPriceId);
    // }

    // // ChangeLimitPrice() with a new limit price changes buy order's limit price
    // function test_ChangeBuyOrderLimitPrice() public {
    //     depositBuyOrder(Alice, -1, 1000, 1);
    //     changeLimitPrice(Alice, Alice_Order, -2);
    //     checkPoolId(Alice_Order, -2);
    // }

    // // ChangeLimitPrice() with a new limit price changes sell order's limit price
    // function test_ChangeSellOrderLimitPrice() public {
    //     depositSellOrder(Alice, 1, 10, -1);
    //     changeLimitPrice(Alice, Alice_Order, 2);
    //     checkPoolId(Alice_Order, 2);
    // }

    // // When caller is not maker of buy order, revert
    // function test_RevertBuyOrderIfNotMaker() public {
    //     depositBuyOrder(Alice, -1, 1000, 1);
    //     vm.expectRevert("Only maker can modify order");
    //     changeLimitPrice(Bob, Alice_Order, -2);
    // }

    // // When caller is not maker of sell order, revert
    // function test_RevertSellOrderIfNotMaker() public {
    //     depositSellOrder(Alice, 1, 10, -1);
    //     vm.expectRevert("Only maker can modify order");
    //     changeLimitPrice(Carol, Alice_Order, 2);
    // }

    // // When new buy order's limit price makes it immediately profitable, revert
    // function test_RevertBuyOrderIfNotConsistent() public {
    //     depositBuyOrder(Alice, -1, 1000, 1);
    //     setPriceFeed(90);
    //     vm.expectRevert("New price at loss");
    //     changeLimitPrice(Alice, Alice_Order, 0);
    // }

    // // When new sell order's limit price makes it immediately profitable, revert
    // function test_RevertSellOrderIfNotConsistent() public {
    //     depositSellOrder(Alice, 1, 10, -1);
    //     setPriceFeed(120);
    //     vm.expectRevert("New price at loss");
    //     changeLimitPrice(Alice, Alice_Order, 0);
    // }

    // // If buy order is borrowed, changing limit price reverts
    // function test_RevertBuyOrderIfBorrowed() public {
    //     depositBuyOrder(Alice, 3000, 90);
    //     depositSellOrder(Bob, 30, 110);
    //     borrow(Bob, Alice_Order, 1000);
    //     vm.expectRevert("Order must not be borrowed from");
    //     changeLimitPrice(Alice, Alice_Order, 95);
    // }

    // // If sell order is borrowed, changing limit price reverts
    // function test_RevertSellOrderIfBorrowed() public {
    //     depositSellOrder(Alice, 30, 110);
    //     depositBuyOrder(Bob, 3000, 90);
    //     borrow(Bob, Alice_Order, 10);
    //     vm.expectRevert("Order must not be borrowed from");
    //     changeLimitPrice(Alice, Alice_Order, 111);
    // }

}
