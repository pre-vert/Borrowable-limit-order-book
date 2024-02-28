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
    
    // taking sell order succeeds and correctly adjuts balances + order is reposted as a buy order
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

    // taking fails if greater than non borrowed pool of buy order
    function test_TakeBuyOrderFailsIfTooMuch() public depositBuy(FirstPoolId) {
        setPriceFeed(1990);
        vm.expectRevert("Take too much");
        take(Bob, FirstPoolId, 2 * DepositQT);
    }

    // taking fails if greater than pool of sell order
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

    // taking fails if taking borrowed buy order exceeds available assets
    function test_TakingBuyOrderFailsIfExceedsAvailableAssets() public depositBuy(FirstPoolId) depositSell(FirstPoolId + 1) {
        borrow(Bob, FirstPoolId, 4 * DepositQT / 5);
        setPriceFeed(LowPrice / WAD);
        vm.expectRevert("Take too much");
        take(Carol, FirstPoolId, 2 * DepositQT / 5);
    }

    // take pool of borrowed quotes collateralized by quotes correctly adjust balances
    // price 2001: Alice deposits 20,000 in buy order at 2000
    // price 2201: Bob deposits 20,000 in buy order at 2200 and borrows 10,000 from Alice
    // price 2100: Carol takes Bob's buy order at 2200
    // => Bob gets 20,000/2200 = 9.1 ETH replaced in sell order at 2400
    // price 1900: Carol takes Alice's buy order => Bob's collateral 10,000/2000 = 5 ETH is transferred to Alice
    // Bob's residual asset in sell order is 20,000/2200 - 10,000/2000 = 9.1 - 5 = 4.1 ETH
    // book base balance : base tokens received from taker are reposted as sell orders
    // book quote balance : minus quote tokens sent to takers
    
    function test_TakeBorrowWithQuoteTokens() public depositBuy(FirstPoolId) {
        setPriceFeed(initialPriceWAD / WAD + 201);
        depositBuyOrder(Bob, FirstPoolId + 1, DepositQT, FirstPoolId + 2);
        borrow(Bob, FirstPoolId, 2 * DepositQT / 5);
        setPriceFeed(initialPriceWAD / WAD - 100);
        take(Carol, FirstPoolId + 1, DepositQT);
        uint256 bobGets = WAD * DepositQT / book.limitPrice(FirstPoolId + 1);
        console.log("bob gets : ", bobGets);
        checkOrderQuantity(ThirdOrderId, bobGets);
        setPriceFeed(initialPriceWAD / WAD - 100);
        uint256 bookBaseBalance = baseToken.balanceOf(OrderBook);
        uint256 bookQuoteBalance = quoteToken.balanceOf(OrderBook);
        uint256 makerBaseBalance = baseToken.balanceOf(Alice);
        uint256 makerQuoteBalance = quoteToken.balanceOf(Alice);
        uint256 borrowerBaseBalance = baseToken.balanceOf(Bob);
        uint256 borrowerQuoteBalance = quoteToken.balanceOf(Bob);
        uint256 takerBaseBalance = baseToken.balanceOf(Carol);
        uint256 takerQuoteBalance = quoteToken.balanceOf(Carol);
        uint256 aliceGets = WAD * DepositQT / book.limitPrice(FirstPoolId);
        bobGets -= DepositQT / (2 * book.limitPrice(FirstPoolId));
        console.log("bob gets : ", bobGets);
        take(Carol, FirstPoolId, 3 * DepositQT / 5);
        assertEq(baseToken.balanceOf(OrderBook), bookBaseBalance + 3 * aliceGets / 5);
        assertEq(quoteToken.balanceOf(OrderBook), bookQuoteBalance - 3 * DepositQT / 5);
        assertEq(baseToken.balanceOf(Alice), makerBaseBalance); // BT are not sent to Alice's wallet but reposted
        assertEq(quoteToken.balanceOf(Alice), makerQuoteBalance);
        assertEq(baseToken.balanceOf(Bob), borrowerBaseBalance);
        assertEq(quoteToken.balanceOf(Bob), borrowerQuoteBalance);
        assertEq(baseToken.balanceOf(Carol), takerBaseBalance - 3 * aliceGets / 5);
        assertEq(quoteToken.balanceOf(Carol), takerQuoteBalance + 3 * DepositQT / 5);
        checkOrderQuantity(FirstOrderId, 0);
        checkOrderQuantity(SecondOrderId, 0);
        checkOrderQuantity(ThirdOrderId, bobGets);
        // checkOrderQuantity(ThirdOrderId, DepositQT);
        // checkBorrowingQuantity(FirstPositionId, DepositQT / 2); 
    }

    // Taking borrowed buy order succeeds and correctly adjuts balances + order is reposted as a sell order
    // Alice posts in a buy order 20,000 at limit price 2000, Bob deposits 10 ETH and borrows 8,000 from Alice
    // Carol takes available USDC in buy order, receives 12,000 and gives 12,000/2000 = 6 ETH
    // Alice gets from Bob and Carol 4 + 6 = 10 ETH, which are reposted in a sell order at 2200
    // book's base balance before take: 10 ETH for Bob
    // book's base balance after take: (10 - 4) for Bob and 10 for Alice = 16 ETH => variation = 16 - 10 = 6 ETH
    // book's quote balance before take: 12,000 (20,000 USDC for Alice - 8,000 sent to Bob)
    // book's quote balance after take: 0 (12,000 received by taker)
    
    // function test_TakingBorrowedBuyOrderSucceeds() public depositBuy(FirstPoolId) depositSell(FirstPoolId + 1) {
    //     borrow(Bob, FirstPoolId, 2 * DepositQT / 5);
    //     uint256 bookBaseBalance = baseToken.balanceOf(OrderBook);
    //     uint256 bookQuoteBalance = quoteToken.balanceOf(OrderBook);
    //     uint256 makerBaseBalance = baseToken.balanceOf(Alice);
    //     uint256 makerQuoteBalance = quoteToken.balanceOf(Alice);
    //     uint256 borrowerBaseBalance = baseToken.balanceOf(Bob);
    //     uint256 borrowerQuoteBalance = quoteToken.balanceOf(Bob);
    //     uint256 takerBaseBalance = baseToken.balanceOf(Carol);
    //     uint256 takerQuoteBalance = quoteToken.balanceOf(Carol);
    //     setPriceFeed(LowPrice / WAD);
    //     uint256 aliceGets = WAD * DepositQT / book.limitPrice(FirstPoolId);
    //     console.log("Alice gets", aliceGets / WAD, "ETH reposted in a sell order");
    //     take(Carol, FirstPoolId, 3 * DepositQT / 5);
    //     assertEq(baseToken.balanceOf(OrderBook), bookBaseBalance + 6 * aliceGets / 10);
    //     assertEq(quoteToken.balanceOf(OrderBook), bookQuoteBalance - 3 * DepositQT / 5);
    //     assertEq(baseToken.balanceOf(Alice), makerBaseBalance); // BT are not sent to Alice's wallet but reposted
    //     assertEq(quoteToken.balanceOf(Alice), makerQuoteBalance);
    //     assertEq(baseToken.balanceOf(Bob), borrowerBaseBalance);
    //     assertEq(quoteToken.balanceOf(Bob), borrowerQuoteBalance);
    //     assertEq(baseToken.balanceOf(Carol), takerBaseBalance - 6 * aliceGets / 10);
    //     assertEq(quoteToken.balanceOf(Carol), takerQuoteBalance + 3 * DepositQT / 5);
    //     checkOrderQuantity(FirstOrderId, 0);
    //     checkOrderQuantity(SecondOrderId, DepositBT - 4 * DepositBT / 10);
    //     checkOrderQuantity(ThirdOrderId, aliceGets);
    // }




}