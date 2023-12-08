// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Setup} from "./Setup.sol";
import {MathLib, WAD} from "../lib/MathLib.sol";

contract TestTake is Setup {

    // taking fails if non-existing buy order
    function test_TakingFailsIfNonExistingBuyOrder() public {
        depositBuyOrder(Alice, DepositQT, 90);
        vm.expectRevert("Order has zero assets");
        take(Bob, Carol_Order, 0);
    }

    // taking fails if non existing sell order
    function test_TakingFailsIfNonExistingSellOrder() public {
        depositSellOrder(Alice, DepositBT, 110);
        vm.expectRevert("Order has zero assets");
        take(Bob, Carol_Order, 0);
    }

    // taking buy order is ok if zero taken
    function test_TakeBuyOrderWithZero() public {
        depositBuyOrder(Alice, DepositQT, 90);
        setPriceFeed(80);
        take(Bob, Alice_Order, 0);
        checkOrderQuantity(Alice_Order, DepositQT);
    }

    // taking sell order is ok if zero taken
    function test_TakeSellOrderWithZero() public {
        depositSellOrder(Alice, DepositBT, 110);
        setPriceFeed(120);
        take(Bob, Alice_Order, 0);
        checkOrderQuantity(Alice_Order, DepositBT);
    }

    // taking fails if greater than buy order
    function test_TakeBuyOrderFailsIfTooMuch() public {
        depositBuyOrder(Alice, DepositQT, 90);
        setPriceFeed(80);
        vm.expectRevert("Take too much");
        take(Bob, Alice_Order, 2 * DepositQT);
    }

    // taking fails if greater than sell order
    function test_TakeSellOrderFailsIfTooMuch() public {
        depositSellOrder(Alice, DepositBT, 110);
        setPriceFeed(120);
        vm.expectRevert("Take too much");
        take(Bob, Alice_Order, 2 * DepositBT);
    }

    // taking doesn't fail if taking non-borrowed buy order is non profitable, taker just loses money
    // Bob gives Alice 1800 / 90 = 20 BT, which is reposted in a sell order at price 99

    function test_TakingIsOkIfNonProfitableBuyOrder() public {
        depositBuyOrder(Alice, DepositQT, LowPrice);
        //setPriceFeed(HighPrice);
        take(Bob, Alice_Order, DepositQT);
    }
    
    // taking doesn't fail if taking non-borrowed sell order is non profitable
    function test_TakingIsOkIfNonProfitableSellOrder() public {
        depositSellOrder(Alice, DepositBT, HighPrice);
        setPriceFeed(LowPrice);
        take(Bob, Alice_Order, DepositBT);
    }

    // taking fails if taking borrowed buy order is non profitable 
    // Taker loses money but not maker and borrower is worse off

    function test_TakingFailsIfNonProfitableBuyOrder() public {
        setPriceFeed(95);
        depositBuyOrder(Alice, DepositQT, LowPrice);
        depositSellOrder(Bob, DepositBT, HighPrice);
        borrow(Bob, Alice_Order, DepositQT / 2);
        vm.expectRevert("Trade must be profitable");
        take(Bob, Alice_Order, DepositQT / 2);
    }

    // taking fails if taking borrowed sell order is non profitable 
    function test_TakingFailsIfNonProfitableSellOrder() public {
        depositSellOrder(Alice, DepositBT, HighPrice);
        depositBuyOrder(Bob, DepositQT, LowPrice);
        borrow(Bob, Alice_Order, DepositBT / 2);
        vm.expectRevert("Trade must be profitable");
        take(Bob, Alice_Order, DepositBT / 2);
    }

    // taking creates a sell order from a borrowed buy order
    // Alice's buy order of 1800 QT is taken for 20 BT

    function test_TakingBuyOrderCreatesASellOrder() public {
        depositBuyOrder(Alice, DepositQT, LowPrice);
        depositSellOrder(Bob, DepositBT, HighPrice);
        borrow(Bob, Alice_Order, DepositQT / 2);
        setPriceFeed(UltraLowPrice);
        take(Carol, Alice_Order, DepositQT / 2);
        checkOrderQuantity(Alice_Order, 0);
        checkOrderQuantity(Alice_Order + 1, (DepositQT / 2) / LowPrice);
    }

    // taking fails if taking borrowed buy order exceeds available assets
    function test_TakingBuyOrderFailsIfExceedsAvailableAssets() public {
        depositBuyOrder(Alice, DepositQT, LowPrice);
        depositSellOrder(Bob, DepositBT, HighPrice);
        borrow(Bob, Alice_Order, DepositQT / 2);
        setPriceFeed(UltraLowPrice);
        vm.expectRevert("Take too much");
        take(Carol, Alice_Order, DepositQT);
    }

    // taking fails if taking borrowed buy order exceeds available assets BUG
    function test_TakingBuyOrderFailsIfCollateralAssets() public {
        setPriceFeed(95);
        depositBuyOrder(Alice, 1900, 90);
        depositSellOrder(Bob, 20, 100);
        borrow(Bob, Alice_Order, 900);
        setPriceFeed(85);
        vm.expectRevert("Take too much");
        take(Carol, Bob_Order, 21);
    }

    // taking of buy order correctly adjusts external balances
    // Alice receives DepositQT / LowPrice, which is used to create a sell order


    function test_TakeBuyOrderCheckBalances() public {
        depositBuyOrder(Alice, DepositQT, LowPrice);
        uint256 contractQuoteBalance = quoteToken.balanceOf(OrderBook);
        uint256 makerQuoteBalance = quoteToken.balanceOf(Alice);
        uint256 makerBaseBalance = baseToken.balanceOf(Alice);
        uint256 takerQuoteBalance = quoteToken.balanceOf(Bob);
        uint256 takerBaseBalance = baseToken.balanceOf(Bob);
        setPriceFeed(UltraLowPrice);
        take(Bob, Alice_Order, DepositQT);
        assertEq(quoteToken.balanceOf(OrderBook), contractQuoteBalance - DepositQT * WAD);
        assertEq(quoteToken.balanceOf(Alice), makerQuoteBalance);
        assertEq(baseToken.balanceOf(Alice), makerBaseBalance); // + 20 * WAD);
        assertEq(quoteToken.balanceOf(Bob), takerQuoteBalance + DepositQT * WAD);
        assertEq(baseToken.balanceOf(Bob), takerBaseBalance - WAD * DepositQT / LowPrice);
    }

    // taking of sell order correctly adjusts external balances
    // Alice receives 20 * 110 = 2200 QT which are used to create a buy order

    function test_TakeSellOrderCheckBalances() public {
        depositSellOrder(Alice, DepositBT, 110);
        uint256 contractBaseBalance = baseToken.balanceOf(OrderBook);
        uint256 makerBaseBalance = baseToken.balanceOf(Alice);
        uint256 makerQuoteBalance = quoteToken.balanceOf(Alice);
        uint256 takerBaseBalance = baseToken.balanceOf(Bob);
        uint256 takerQuoteBalance = quoteToken.balanceOf(Bob);
        setPriceFeed(120);
        take(Bob, Alice_Order, DepositBT);
        assertEq(baseToken.balanceOf(OrderBook), contractBaseBalance - DepositBT * WAD);
        assertEq(baseToken.balanceOf(Alice), makerBaseBalance);
        assertEq(quoteToken.balanceOf(Alice), makerQuoteBalance);
        assertEq(baseToken.balanceOf(Bob), takerBaseBalance + DepositBT * WAD);
        assertEq(quoteToken.balanceOf(Bob), takerQuoteBalance - DepositBT * 110 * WAD);
    }

    // taking of buy order by maker correctly adjusts external balances
    function test_MakerTakesBuyOrderCheckBalances() public {
        depositBuyOrder(Alice, DepositQT, LowPrice);
        uint256 contractQuoteBalance = quoteToken.balanceOf(OrderBook);
        uint256 contractBaseBalance = baseToken.balanceOf(OrderBook);
        uint256 makerQuoteBalance = quoteToken.balanceOf(Alice);
        uint256 makerBaseBalance = baseToken.balanceOf(Alice);
        setPriceFeed(UltraLowPrice);
        take(Alice, Alice_Order, TakeQT);
        //setPriceFeed(80);
        assertEq(quoteToken.balanceOf(OrderBook), contractQuoteBalance - TakeQT * WAD);
        assertEq(baseToken.balanceOf(OrderBook), contractBaseBalance + WAD * TakeQT / LowPrice);
        assertEq(quoteToken.balanceOf(Alice), makerQuoteBalance + TakeQT * WAD);
        assertEq(baseToken.balanceOf(Alice), makerBaseBalance - WAD * TakeQT / LowPrice);
    }

}
