// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Setup} from "./Setup.sol";
import {MathLib, WAD} from "../lib/MathLib.sol";

contract TestTake is Setup {

    // taking vanilla buy order succeeds and correctly adjuts balances + order is reposted as a sell order
    // market price set initially at 2001
    // deposit buy order at limit price = 2000 = limit price pool(0) < market price
    // set price feed 1990 : limit price pool(0) > market price

    function test_TakingBuyOrderSucceeds() public depositBuy(FirstPoolId) setLowPrice() {
        uint256 orderBookBaseBalance = baseToken.balanceOf(OrderBook);
        uint256 orderBookQuoteBalance = quoteToken.balanceOf(OrderBook);
        uint256 makerBaseBalance = baseToken.balanceOf(Alice);
        uint256 makerQuoteBalance = quoteToken.balanceOf(Alice);
        uint256 takerBaseBalance = baseToken.balanceOf(Bob);
        uint256 takerQuoteBalance = quoteToken.balanceOf(Bob);
        uint256 aliceGets = WAD * DepositQT / book.limitPrice(FirstPoolId);
        console.log("Alice gets", aliceGets / WAD);
        take(Bob, FirstPoolId, DepositQT);
        assertEq(baseToken.balanceOf(Alice), makerBaseBalance); // BT are not sent to Alice's wallet but reposted
        assertEq(quoteToken.balanceOf(Alice), makerQuoteBalance);
        assertEq(baseToken.balanceOf(Bob), takerBaseBalance - aliceGets);
        assertEq(quoteToken.balanceOf(Bob), takerQuoteBalance + DepositQT);
        assertEq(baseToken.balanceOf(OrderBook), orderBookBaseBalance + aliceGets);
        assertEq(quoteToken.balanceOf(OrderBook), orderBookQuoteBalance - DepositQT);
        checkOrderQuantity(FirstOrderId, 0);
        checkOrderQuantity(SecondOrderId, aliceGets);
    }
    
    // taking vanilla sell order succeeds and correctly adjuts balances + order is reposted as a buy order
    function test_TakingSellOrderSucceeds() public setLowPrice() depositSell(FirstPoolId) setHighPrice() {
        uint256 orderBookBaseBalance = baseToken.balanceOf(OrderBook);
        uint256 orderBookQuoteBalance = quoteToken.balanceOf(OrderBook);
        uint256 makerQuoteBalance = quoteToken.balanceOf(Alice);
        uint256 makerBaseBalance = baseToken.balanceOf(Alice);
        uint256 takerBaseBalance = baseToken.balanceOf(Bob);
        uint256 takerQuoteBalance = quoteToken.balanceOf(Bob);
        uint256 aliceGets = DepositBT * book.limitPrice(FirstPoolId) / WAD;
        take(Bob, FirstPoolId, DepositBT);
        assertEq(baseToken.balanceOf(OrderBook), orderBookBaseBalance - DepositBT);
        assertEq(quoteToken.balanceOf(OrderBook), orderBookQuoteBalance + aliceGets); // HERE
        assertEq(quoteToken.balanceOf(Alice), makerQuoteBalance); // quotes are not sent to Alice's wallet but reposted
        assertEq(baseToken.balanceOf(Alice), makerBaseBalance);
        assertEq(baseToken.balanceOf(Bob), takerBaseBalance + DepositBT);
        assertEq(quoteToken.balanceOf(Bob), takerQuoteBalance - aliceGets);
        checkOrderQuantity(FirstOrderId, 0);
        checkOrderQuantity(SecondOrderId, aliceGets);
    }

    // taking buy order by maker succeeds and correctly adjuts balances
    function test_TakingBuyOrderByMakerSucceeds() public depositBuy(FirstPoolId) setLowPrice() {
        uint256 orderBookBaseBalance = baseToken.balanceOf(OrderBook);
        uint256 orderBookQuoteBalance = quoteToken.balanceOf(OrderBook);
        uint256 makerBaseBalance = baseToken.balanceOf(Alice);
        uint256 makerQuoteBalance = quoteToken.balanceOf(Alice);
        uint256 aliceGets = WAD * DepositQT / book.limitPrice(FirstPoolId);
        console.log("Alice gets", aliceGets / WAD);
        take(Alice, FirstPoolId, DepositQT);
        assertEq(baseToken.balanceOf(Alice), makerBaseBalance  - aliceGets); // as a taker
        assertEq(quoteToken.balanceOf(Alice), makerQuoteBalance + DepositQT); // as a taker
        assertEq(baseToken.balanceOf(OrderBook), orderBookBaseBalance + aliceGets);
        assertEq(quoteToken.balanceOf(OrderBook), orderBookQuoteBalance - DepositQT);
        checkOrderQuantity(FirstOrderId, 0);
        checkOrderQuantity(SecondOrderId, aliceGets);
    }

    // taking sell order by maker succeeds and correctly adjuts balances
    function test_TakingSellOrderByMakerSucceeds() public setLowPrice() depositSell(FirstPoolId) setHighPrice() {
        uint256 orderBookBaseBalance = baseToken.balanceOf(OrderBook);
        uint256 orderBookQuoteBalance = quoteToken.balanceOf(OrderBook);
        uint256 makerQuoteBalance = quoteToken.balanceOf(Alice);
        uint256 makerBaseBalance = baseToken.balanceOf(Alice);
        uint256 aliceGets = DepositBT * book.limitPrice(FirstPoolId) / WAD;
        take(Alice, FirstPoolId, DepositBT);
        assertEq(baseToken.balanceOf(OrderBook), orderBookBaseBalance - DepositBT);
        assertEq(quoteToken.balanceOf(OrderBook), orderBookQuoteBalance + aliceGets); // 
        assertEq(baseToken.balanceOf(Alice), makerBaseBalance  + DepositBT); // as a taker
        assertEq(quoteToken.balanceOf(Alice), makerQuoteBalance - aliceGets); // as a taker
        checkOrderQuantity(FirstOrderId, 0);
        checkOrderQuantity(SecondOrderId, aliceGets);
    }

    // taking half vanilla buy order succeeds
    function test_TakingHalfBuyOrderSucceeds() public depositBuy(FirstPoolId) {
        setPriceFeed(1990);
        take(Bob, FirstPoolId, DepositQT / 2);
    }
    
    // taking half vanilla sell order succeeds
    function test_TakingHalfSellOrderSucceeds() public setLowPrice() depositSell(FirstPoolId) {
        setPriceFeed(2010);
        take(Bob, FirstPoolId, DepositBT / 2);
    }
    
    // taking fails if non-existing buy order
    function test_TakingBuyOrderFailsIfEmptyPool() public depositBuy(FirstPoolId) {
        setPriceFeed(1990);
        vm.expectRevert("Pool_empty_2");
        take(Bob, FirstPoolId + 1, DepositQT);
    }

    // taking fails if non existing sell order
    function test_TakingSellOrderFailsIfEmptyPool() public setLowPrice() depositSell(FirstPoolId) {
        setPriceFeed(2010);
        vm.expectRevert("Pool_empty_2");
        take(Bob, FirstPoolId - 1, DepositBT);
    }

    // take buy order for zero is ok
    function test_TakeBuyOrderWithZero() public depositBuy(FirstPoolId) {
        setPriceFeed(1990);
        take(Bob, FirstPoolId, 0);
    }

    // take sell order for zero is not ok
    function test_TakingSellOrderFailsIfZeroTaken() public setLowPrice() depositSell(FirstPoolId) {
        setPriceFeed(2010);
        vm.expectRevert("Take zero");
        take(Bob, FirstPoolId, 0);
    }

    // taking fails if greater than buy order
    function test_TakeBuyOrderFailsIfTooMuch() public depositBuy(FirstPoolId) {
        setPriceFeed(1990);
        vm.expectRevert("Take too much");
        take(Bob, FirstPoolId, 2 * DepositQT);
    }

    // taking fails if greater than sell order
    function test_TakeSellOrderFailsIfTooMuch() public setLowPrice() depositSell(FirstPoolId) {
        setPriceFeed(2010);
        vm.expectRevert("Take too much");
        take(Bob, FirstPoolId, 2 * DepositBT);
    }

    // taking non profitable sell orders just loses money
    function test_TakingIsOkIfNonProfitableSellOrder() public setLowPrice() depositSell(FirstPoolId) {
        take(Bob, FirstPoolId, DepositBT);
    }

    // taking non profitable buy orders is not ok
    function test_TakingFailsIfNonProfitableBuyOrder() public depositBuy(FirstPoolId) {
        vm.expectRevert("Trade not profitable");
        take(Bob, FirstPoolId, DepositQT);
    }

    // Taking borrowed buy order succeeds and correctly adjuts balances + order is reposted as a sell order
    // Alice posts in a buy order 20,000 at limit price 2000, Bob deposits 10 ETH and borrows 8,000 from Alice
    // Carol takes available USDC in buy order, receives 12,000 and gives 12,000/2000 = 6 ETH
    // Alice gets from Bob and Carol 4 + 6 = 10 ETH, which are reposted in a sell order at 2200
    // book's base balance before take: 10 ETH for Bob
    // book's base balance after take: (10 - 4) for Bob and 10 for Alice = 16 ETH => variation = 16 - 10 = 6 ETH
    // book's quote balance before take: 12,000 (20,000 USDC for Alice - 8,000 sent to Bob)
    // book's quote balance after take: 0 (12,000 received by taker)
    
    function test_TakingBorrowedBuyOrderSucceeds() public depositBuy(FirstPoolId) depositSell(FirstPoolId + 1) {
        borrow(Bob, FirstPoolId, 2 * DepositQT / 5);
        uint256 bookBaseBalance = baseToken.balanceOf(OrderBook);
        uint256 bookQuoteBalance = quoteToken.balanceOf(OrderBook);
        uint256 makerBaseBalance = baseToken.balanceOf(Alice);
        uint256 makerQuoteBalance = quoteToken.balanceOf(Alice);
        uint256 borrowerBaseBalance = baseToken.balanceOf(Bob);
        uint256 borrowerQuoteBalance = quoteToken.balanceOf(Bob);
        uint256 takerBaseBalance = baseToken.balanceOf(Carol);
        uint256 takerQuoteBalance = quoteToken.balanceOf(Carol);
        setPriceFeed(LowPrice / WAD);
        uint256 aliceGets = WAD * DepositQT / book.limitPrice(FirstPoolId);
        console.log("Alice gets", aliceGets / WAD, "ETH reposted in a sell order");
        take(Carol, FirstPoolId, 3 * DepositQT / 5);
        assertEq(baseToken.balanceOf(OrderBook), bookBaseBalance + 6 * aliceGets / 10);
        assertEq(quoteToken.balanceOf(OrderBook), bookQuoteBalance - 3 * DepositQT / 5);
        assertEq(baseToken.balanceOf(Alice), makerBaseBalance); // BT are not sent to Alice's wallet but reposted
        assertEq(quoteToken.balanceOf(Alice), makerQuoteBalance);
        assertEq(baseToken.balanceOf(Bob), borrowerBaseBalance);
        assertEq(quoteToken.balanceOf(Bob), borrowerQuoteBalance);
        assertEq(baseToken.balanceOf(Carol), takerBaseBalance - 6 * aliceGets / 10);
        assertEq(quoteToken.balanceOf(Carol), takerQuoteBalance + 3 * DepositQT / 5);
        checkOrderQuantity(FirstOrderId, 0);
        checkOrderQuantity(SecondOrderId, DepositBT - 4 * DepositBT / 10);
        checkOrderQuantity(ThirdOrderId, aliceGets);
    }

    // // taking creates a sell order from a borrowed buy order
    // // Alice's buy order of 1800 QT is taken for 20 BT

    // function test_TakingBuyOrderCreatesASellOrder() public {
    //     depositBuyOrder(Alice, DepositQT, LowPrice);
    //     depositSellOrder(Bob, DepositBT, HighPrice);
    //     borrow(Bob, Alice_Order, DepositQT / 2);
    //     setPriceFeed(UltraLowPrice);
    //     take(Carol, Alice_Order, DepositQT / 2);
    //     checkOrderQuantity(Alice_Order, 0);
    //     checkOrderQuantity(Alice_Order + 1, (DepositQT / 2) / LowPrice);
    // }

    // // taking fails if taking borrowed buy order exceeds available assets
    // function test_TakingBuyOrderFailsIfExceedsAvailableAssets() public {
    //     depositBuyOrder(Alice, DepositQT, LowPrice);
    //     depositSellOrder(Bob, DepositBT, HighPrice);
    //     borrow(Bob, Alice_Order, DepositQT / 2);
    //     setPriceFeed(UltraLowPrice);
    //     vm.expectRevert("Take too much");
    //     take(Carol, Alice_Order, DepositQT);
    // }

    // // taking fails if taking borrowed buy order exceeds available assets BUG
    // function test_TakingBuyOrderFailsIfCollateralAssets() public {
    //     setPriceFeed(95);
    //     depositBuyOrder(Alice, 1900, 90);
    //     depositSellOrder(Bob, 20, 100);
    //     borrow(Bob, Alice_Order, 900);
    //     setPriceFeed(85);
    //     vm.expectRevert("Take too much");
    //     take(Carol, Bob_Order, 21);
    // }

    // // taking of buy order correctly adjusts external balances
    // // Alice receives DepositQT / LowPrice, which is used to create a sell order


    // function test_TakeBuyOrderCheckBalances() public {
    //     depositBuyOrder(Alice, DepositQT, LowPrice);
    //     uint256 contractQuoteBalance = quoteToken.balanceOf(OrderBook);
    //     uint256 makerQuoteBalance = quoteToken.balanceOf(Alice);
    //     uint256 makerBaseBalance = baseToken.balanceOf(Alice);
    //     uint256 takerQuoteBalance = quoteToken.balanceOf(Bob);
    //     uint256 takerBaseBalance = baseToken.balanceOf(Bob);
    //     setPriceFeed(UltraLowPrice);
    //     take(Bob, Alice_Order, DepositQT);
    //     assertEq(quoteToken.balanceOf(OrderBook), contractQuoteBalance - DepositQT * WAD);
    //     assertEq(quoteToken.balanceOf(Alice), makerQuoteBalance);
    //     assertEq(baseToken.balanceOf(Alice), makerBaseBalance); // + 20 * WAD);
    //     assertEq(quoteToken.balanceOf(Bob), takerQuoteBalance + DepositQT * WAD);
    //     assertEq(baseToken.balanceOf(Bob), takerBaseBalance - WAD * DepositQT / LowPrice);
    // }

    // // taking of sell order correctly adjusts external balances
    // // Alice receives 20 * 110 = 2200 QT which are used to create a buy order

    // function test_TakeSellOrderCheckBalances() public {
    //     depositSellOrder(Alice, DepositBT, 110);
    //     uint256 contractBaseBalance = baseToken.balanceOf(OrderBook);
    //     uint256 makerBaseBalance = baseToken.balanceOf(Alice);
    //     uint256 makerQuoteBalance = quoteToken.balanceOf(Alice);
    //     uint256 takerBaseBalance = baseToken.balanceOf(Bob);
    //     uint256 takerQuoteBalance = quoteToken.balanceOf(Bob);
    //     setPriceFeed(120);
    //     take(Bob, Alice_Order, DepositBT);
    //     assertEq(baseToken.balanceOf(OrderBook), contractBaseBalance - DepositBT * WAD);
    //     assertEq(baseToken.balanceOf(Alice), makerBaseBalance);
    //     assertEq(quoteToken.balanceOf(Alice), makerQuoteBalance);
    //     assertEq(baseToken.balanceOf(Bob), takerBaseBalance + DepositBT * WAD);
    //     assertEq(quoteToken.balanceOf(Bob), takerQuoteBalance - DepositBT * 110 * WAD);
    // }

    // // taking of buy order by maker correctly adjusts external balances
    // function test_MakerTakesBuyOrderCheckBalances() public {
    //     depositBuyOrder(Alice, DepositQT, LowPrice);
    //     uint256 contractQuoteBalance = quoteToken.balanceOf(OrderBook);
    //     uint256 contractBaseBalance = baseToken.balanceOf(OrderBook);
    //     uint256 makerQuoteBalance = quoteToken.balanceOf(Alice);
    //     uint256 makerBaseBalance = baseToken.balanceOf(Alice);
    //     setPriceFeed(UltraLowPrice);
    //     take(Alice, Alice_Order, TakeQT);
    //     //setPriceFeed(80);
    //     assertEq(quoteToken.balanceOf(OrderBook), contractQuoteBalance - TakeQT * WAD);
    //     assertEq(baseToken.balanceOf(OrderBook), contractBaseBalance + WAD * TakeQT / LowPrice);
    //     assertEq(quoteToken.balanceOf(Alice), makerQuoteBalance + TakeQT * WAD);
    //     assertEq(baseToken.balanceOf(Alice), makerBaseBalance - WAD * TakeQT / LowPrice);
    // }

}