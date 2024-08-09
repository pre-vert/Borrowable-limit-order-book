// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Setup} from "./Setup.sol";
import {MathLib, WAD} from "../lib/MathLib.sol";

contract TestTake is Setup {

    // taking half vanilla buy order succeeds + liquidity correctly reposted
    // Initail price is 4001, Alice deposits in buy order at 4000
    // Then price glides below 4000, allowing take

    function test_TakingHalfBuyOrder() public depositBuy(B) {
        setPriceFeed(3990);
        takeQuoteTokens(B, DepositQT / 2);
        assertEq(getOrderQuantity(FirstOrderId), DepositQT / 2);
        uint256 aliceGets = WAD * (DepositQT / book.limitPrice(B)) / 2;
        assertEq(getOrderQuantity(SecondOrderId), aliceGets);
    }
    
    // taking half vanilla sell order succeeds
    // set price at 3990, Bob deposits in sell order at limit price 4000
    // Then price is up to 4010, allowing take at limit price 4000

    function test_TakingHalfSellOrder() public setLowPrice() depositSell(B + 1) setHighPrice() {
        takeBaseTokens(B + 1, DepositBT / 2);
        assertEq(getOrderQuantity(FirstOrderId), DepositBT / 2);
        uint256 aliceGets = ((DepositBT * book.limitPrice(B + 1)) / 2) / WAD;
        assertEq(getOrderQuantity(SecondOrderId), aliceGets);
    }
    
    // taking fails if non-existing buy order
    function test_TakingBuyOrderFailsIfEmptyPool() public depositBuy(B) setLowPrice() {
        vm.expectRevert("Pool_empty_2");
        takeQuoteTokens(B + 1, DepositQT);
        assertEq(getOrderQuantity(FirstOrderId), DepositQT);
    }

    // taking fails if non existing sell order
    function test_TakingSellOrderFailsIfEmptyPool() public setLowPrice() depositSell(B + 1) setHighPrice() {
        vm.expectRevert("Pool_empty_3");
        takeBaseTokens(B - 1, DepositBT);
    }

    // take buy order for zero is ok
    function test_takeBuyOrderWithZero() public depositBuy(B) setLowPrice() {
        takeQuoteTokens(B, 0);
        assertEq(getOrderQuantity(FirstOrderId), DepositQT);
    }

    // take sell order for zero reverts
    function test_TakingSellOrderFailsIfZeroTaken() public setLowPrice() depositSell(B + 1) setHighPrice() {
        vm.expectRevert("Take zero");
        takeBaseTokens(B + 1, 0);
    }

    // taking fails if greater than non borrowed pool of buy order
    function test_TakeBuyOrderFailsIfTooMuch() public depositBuy(B) setLowPrice() {
        vm.expectRevert("Take too much");
        takeQuoteTokens(B, 2 * DepositQT);
    }

    // taking fails if greater than pool of sell orders
    function test_TakeSellOrderFailsIfTooMuch() public setLowPrice() depositSell(B + 1) setHighPrice() {
        vm.expectRevert("Take too much");
        takeBaseTokens(B + 1, 2 * DepositBT);
    }

    // taking non profitable sell orders just loses money
    function test_TakingIsOkIfNonProfitableSellOrder() public setLowPrice() depositSell(B + 1) {
        takeBaseTokens(B + 1, DepositBT);
        assertEq(getOrderQuantity(FirstOrderId), 0);
    }

    // taking 0 from non profitable sell orders reverts
    function test_TakingIIfNonProfitableSellOrder() public setLowPrice() depositSell(B + 1) {
        vm.expectRevert("Take zero");
        takeBaseTokens(B + 1, 0);
    }

    // taking non profitable buy orders reverts
    function test_TakingFailsIfNonProfitableBuyOrder() public depositBuy(B) {
        vm.expectRevert("Not profitable");
        takeQuoteTokens(B, DepositQT);
    }

    // taking non profitable buy orders with 0 reverts
    function test_TakingZeroFailsIfNonProfitableBuyOrder() public depositBuy(B) {
        vm.expectRevert("Not profitable");
        takeQuoteTokens(B, 0);
    }

    // taking buy order correctly adjuts balances + order is reposted in sell order
    // market price set initially at 4001, deposit buy order at 4000
    // set price feed 3990: buy order becomes takable

    function test_TakingBuyOrder() public depositBuy(B) setLowPrice() {
        uint256 orderBookBaseBalance = baseToken.balanceOf(OrderBook);
        uint256 orderBookQuoteBalance = quoteToken.balanceOf(OrderBook);
        uint256 makerBaseBalance = baseToken.balanceOf(Alice);
        uint256 makerQuoteBalance = quoteToken.balanceOf(Alice);
        uint256 takerBaseBalance = baseToken.balanceOf(Takashi);
        uint256 takerQuoteBalance = quoteToken.balanceOf(Takashi);
        uint256 aliceGets = WAD * DepositQT / book.limitPrice(B);
        takeQuoteTokens(B, DepositQT);
        assertEq(baseToken.balanceOf(Alice), makerBaseBalance);   // BT not sent to Alice's wallet but reposted
        assertEq(quoteToken.balanceOf(Alice), makerQuoteBalance);
        assertEq(baseToken.balanceOf(Takashi), takerBaseBalance - aliceGets);
        assertEq(quoteToken.balanceOf(Takashi), takerQuoteBalance + DepositQT);
        assertEq(baseToken.balanceOf(OrderBook), orderBookBaseBalance + aliceGets);
        assertEq(quoteToken.balanceOf(OrderBook), orderBookQuoteBalance - DepositQT);
        assertEq(getOrderQuantity(FirstOrderId), 0);
        assertEq(getOrderQuantity(SecondOrderId), aliceGets);
    }
    
    // taking sell order correctly adjusts balances + order is reposted as a buy order

    function test_TakingSellOrder() public setLowPrice() depositSell(B + 1) setHighPrice() {
        uint256 orderBookBaseBalance = baseToken.balanceOf(OrderBook);
        uint256 orderBookQuoteBalance = quoteToken.balanceOf(OrderBook);
        uint256 makerQuoteBalance = quoteToken.balanceOf(Alice);
        uint256 makerBaseBalance = baseToken.balanceOf(Alice);
        uint256 takerBaseBalance = baseToken.balanceOf(Takashi);
        uint256 takerQuoteBalance = quoteToken.balanceOf(Takashi);
        uint256 bobGets = DepositBT * book.limitPrice(B + 1) / WAD;
        takeBaseTokens(B + 1, DepositBT);
        assertEq(baseToken.balanceOf(OrderBook), orderBookBaseBalance - DepositBT);
        assertEq(quoteToken.balanceOf(OrderBook), orderBookQuoteBalance + bobGets);
        assertEq(quoteToken.balanceOf(Alice), makerQuoteBalance); // quotes are not sent to Alice's wallet but reposted
        assertEq(baseToken.balanceOf(Alice), makerBaseBalance);
        assertEq(baseToken.balanceOf(Takashi), takerBaseBalance + DepositBT);
        assertEq(quoteToken.balanceOf(Takashi), takerQuoteBalance - bobGets);
        assertEq(getOrderQuantity(FirstOrderId), 0);
        assertEq(getOrderQuantity(SecondOrderId), bobGets);
    }

    // taking sell order of borrower correctly adjuts balances + liquidity is transferred to quote account
    // initial market price 4001, deposit buy at 4000, price to 4400
    
    function test_TakingSellOrderOfBorrower() public depositBuy(B) depositSell(B + 3) {
        uint256 BobDebt = DepositQT / 2;
        borrow(Bob, B, BobDebt);
        setPriceFeed(HighPrice);
        uint256 orderBookBaseBalance = baseToken.balanceOf(OrderBook);
        uint256 orderBookQuoteBalance = quoteToken.balanceOf(OrderBook);
        uint256 BobQuoteBalance = quoteToken.balanceOf(Bob);
        uint256 BobBaseBalance = baseToken.balanceOf(Bob);
        uint256 takerBaseBalance = baseToken.balanceOf(Takashi);
        uint256 takerQuoteBalance = quoteToken.balanceOf(Takashi);
        uint256 BobGetsBeforeRepayDebt = DepositBT * book.limitPrice(B + 3) / WAD;
        uint256 BobGetsAfterRepayDebt = BobGetsBeforeRepayDebt - BobDebt;
        setPriceFeed(UltraHighPrice);
        takeBaseTokens(B + 3, DepositBT);
        assertEq(baseToken.balanceOf(OrderBook), orderBookBaseBalance - DepositBT);
        assertEq(quoteToken.balanceOf(OrderBook), orderBookQuoteBalance + BobGetsBeforeRepayDebt);
        assertEq(quoteToken.balanceOf(Bob), BobQuoteBalance);
        assertEq(baseToken.balanceOf(Bob), BobBaseBalance);
        assertEq(baseToken.balanceOf(Takashi), takerBaseBalance + DepositBT);
        assertEq(quoteToken.balanceOf(Takashi), takerQuoteBalance - BobGetsBeforeRepayDebt);
        assertEq(getOrderQuantity(FirstOrderId), DepositQT);
        assertEq(getOrderQuantity(SecondOrderId), 0);
        checkUserQuoteAccount(Bob, BobGetsAfterRepayDebt);
    }

    // taking buy order by maker correctly adjuts balances
    function test_TakingBuyOrderByMaker() public depositBuy(B) setLowPrice() {
        uint256 orderBookBaseBalance = baseToken.balanceOf(OrderBook);
        uint256 orderBookQuoteBalance = quoteToken.balanceOf(OrderBook);
        uint256 makerBaseBalance = baseToken.balanceOf(Alice);
        uint256 makerQuoteBalance = quoteToken.balanceOf(Alice);
        uint256 aliceGets = WAD * DepositQT / book.limitPrice(B );
        console.log("Alice gets", aliceGets / WAD);
        vm.prank(Alice);
        book.takeQuoteTokens(B, DepositQT);
        assertEq(baseToken.balanceOf(Alice), makerBaseBalance  - aliceGets); // as a taker
        assertEq(quoteToken.balanceOf(Alice), makerQuoteBalance + DepositQT); // as a taker
        assertEq(baseToken.balanceOf(OrderBook), orderBookBaseBalance + aliceGets);
        assertEq(quoteToken.balanceOf(OrderBook), orderBookQuoteBalance - DepositQT);
        assertEq(getOrderQuantity(FirstOrderId), 0);
        assertEq(getOrderQuantity(SecondOrderId), aliceGets);
    }

    // taking sell order by maker correctly adjuts balances
    function test_TakingSellOrderByMaker() public setLowPrice() depositSell(B + 1) setHighPrice() {
        uint256 orderBookBaseBalance = baseToken.balanceOf(OrderBook);
        uint256 orderBookQuoteBalance = quoteToken.balanceOf(OrderBook);
        uint256 makerQuoteBalance = quoteToken.balanceOf(Alice);
        uint256 makerBaseBalance = baseToken.balanceOf(Alice);
        uint256 aliceGets = DepositBT * book.limitPrice(B + 1) / WAD;
        vm.prank(Alice);
        book.takeBaseTokens(B + 1, DepositBT);
        assertEq(baseToken.balanceOf(OrderBook), orderBookBaseBalance - DepositBT);
        assertEq(quoteToken.balanceOf(OrderBook), orderBookQuoteBalance + aliceGets); // 
        assertEq(baseToken.balanceOf(Alice), makerBaseBalance  + DepositBT); // as a taker
        assertEq(quoteToken.balanceOf(Alice), makerQuoteBalance - aliceGets); // as a taker
        assertEq(getOrderQuantity(FirstOrderId), 0);
        assertEq(getOrderQuantity(SecondOrderId), aliceGets);
    }

    // Taking borrowed buy order succeeds and correctly adjuts balances + order is reposted as a sell order
    // Alice posts 20,000 in a buy order at limit price 4000, Bob deposits 10 ETH and borrows 8,000 from Alice
    // Takashi takes available USDC in buy order, receives 12,000 and gives 12,000/4000 = 3 ETH
    // Alice gets from Bob and Takashi 2 + 3 = 5 ETH, which are reposted in a sell order at 4400
    // book's base balance before take: 10 ETH for Bob
    // book's base balance after take: (10 - 2) for Bob and 5 for Alice = 13 ETH => variation = 13 - 10 = 3 ETH
    // book's quote balance before take: 12,000 (20,000 USDC for Alice - 8,000 sent to Bob)
    // book's quote balance after take: 0 (12,000 received by taker)
    
    function test_TakingBorrowedBuyOrderSucceeds() public depositBuy(B) depositSell(B + 3) {
        borrow(Bob, B, 2 * DepositQT / 5);
        uint256 bookBaseBalance = baseToken.balanceOf(OrderBook);
        uint256 bookQuoteBalance = quoteToken.balanceOf(OrderBook);
        uint256 makerBaseBalance = baseToken.balanceOf(Alice);
        uint256 makerQuoteBalance = quoteToken.balanceOf(Alice);
        uint256 borrowerBaseBalance = baseToken.balanceOf(Bob);
        uint256 borrowerQuoteBalance = quoteToken.balanceOf(Bob);
        uint256 takerBaseBalance = baseToken.balanceOf(Takashi);
        uint256 takerQuoteBalance = quoteToken.balanceOf(Takashi);
        setPriceFeed(LowPrice / WAD);
        uint256 aliceGets = WAD * DepositQT / book.limitPrice(B);
        console.log("Alice gets", aliceGets / WAD, "ETH reposted in a sell order");
        takeQuoteTokens(B, 3 * DepositQT / 5);
        assertEq(baseToken.balanceOf(OrderBook), bookBaseBalance + 3 * aliceGets / 5);
        assertEq(quoteToken.balanceOf(OrderBook), bookQuoteBalance - 3 * DepositQT / 5);
        assertEq(baseToken.balanceOf(Alice), makerBaseBalance); // BT are not sent to Alice's wallet but reposted
        assertEq(quoteToken.balanceOf(Alice), makerQuoteBalance);
        assertEq(baseToken.balanceOf(Bob), borrowerBaseBalance);
        assertEq(quoteToken.balanceOf(Bob), borrowerQuoteBalance);
        assertEq(baseToken.balanceOf(Takashi), takerBaseBalance - 3 * aliceGets / 5);
        assertEq(quoteToken.balanceOf(Takashi), takerQuoteBalance + 3 * DepositQT / 5);
        assertEq(getOrderQuantity(FirstOrderId), 0);
        assertEq(getOrderQuantity(SecondOrderId), DepositBT - 2 * DepositBT / 10);
        assertEq(getOrderQuantity(ThirdOrderId), aliceGets);
        assertEq(getPositionQuantity(FirstPositionId), 0);
    }

    // taking buy order fails if exceeds available assets
    function test_TakingBuyOrderFailsIfExceedsAvailableAssets() public depositBuy(B) depositSell(B + 3) {
        borrow(Bob, B, 4 * DepositQT / 5);
        setPriceFeed(LowPrice / WAD);
        vm.expectRevert("Take too much");
        takeQuoteTokens(B, 2 * DepositQT / 5);
    }

    // multiple deposits in same pool, no borrower, then take
    function test_MultipleDepositBuyOrderTake() public {
        uint256 numberDeposits = 2;
        for (uint256 i = 1; i <= numberDeposits; i++) {
            depositBuyOrder(acc[i], B, DepositQT, B + 3);
        }
        uint256 totalDeposits = numberDeposits * DepositQT;
        setPriceFeed(LowPrice / WAD);
        uint256 depositorGets = WAD * DepositQT / book.limitPrice(B);
        takeQuoteTokens(B, totalDeposits);
        for (uint256 i = 1; i <= numberDeposits; i++) {
            assertEq(getOrderQuantity(i), 0);
        }
        for (uint256 i = numberDeposits + 1; i <= 2 * numberDeposits; i++) {
            assertEq(getOrderQuantity(i), depositorGets);
        }
        assertEq(getPoolDeposits(B), 0);
        assertEq(getPoolBorrows(B), 0);
    }

    // Taking two borrowed buy order correctly adjuts balances + order is reposted as a sell order
    // Alice posts in a buy order 20,000 at limit price 2000, Bob deposits 10 ETH and borrows 8,000 from Alice
    // Takashi takes available USDC in buy order, receives 12,000 and gives 12,000/2000 = 6 ETH
    // Alice gets from Bob and Takashi 4 + 6 = 10 ETH, which are reposted in a sell order at 2200
    // book's base balance before take: 10 ETH for Bob
    // book's base balance after take: (10 - 4) for Bob and 10 for Alice = 16 ETH => variation = 16 - 10 = 6 ETH
    // book's quote balance before take: 12,000 (20,000 USDC for Alice - 8,000 sent to Bob)
    // book's quote balance after take: 0 (12,000 received by taker)
    
    function test_TakingTwoBorrowedBuyOrder() public depositBuy(B) {
        depositSellOrder(Bob, B + 3, DepositBT);
        borrow(Bob, B, DepositQT / 4);
        depositSellOrder(Carol, B + 5, DepositBT);
        borrow(Carol, B, DepositQT / 4);
        uint256 bookBaseBalance = baseToken.balanceOf(OrderBook);
        uint256 bookQuoteBalance = quoteToken.balanceOf(OrderBook);
        uint256 makerBaseBalance = baseToken.balanceOf(Alice);
        uint256 makerQuoteBalance = quoteToken.balanceOf(Alice);
        uint256 borrowerOneBaseBalance = baseToken.balanceOf(Bob);
        uint256 borrowerOneQuoteBalance = quoteToken.balanceOf(Bob);
        uint256 borrowerTwoBaseBalance = baseToken.balanceOf(Carol);
        uint256 borrowerTwoQuoteBalance = quoteToken.balanceOf(Carol);
        uint256 takerBaseBalance = baseToken.balanceOf(Takashi);
        uint256 takerQuoteBalance = quoteToken.balanceOf(Takashi);
        setPriceFeed(LowPrice / WAD);
        uint256 aliceGets = WAD * DepositQT / book.limitPrice(B);
        console.log("Alice gets", aliceGets / WAD, "ETH reposted in sell order");
        takeQuoteTokens(B, DepositQT / 2);
        assertEq(baseToken.balanceOf(OrderBook), bookBaseBalance + aliceGets / 2);
        assertEq(quoteToken.balanceOf(OrderBook), bookQuoteBalance - DepositQT / 2);
        assertEq(baseToken.balanceOf(Alice), makerBaseBalance);     // BT are not sent to Alice's wallet but reposted
        assertEq(quoteToken.balanceOf(Alice), makerQuoteBalance);
        assertEq(baseToken.balanceOf(Bob), borrowerOneBaseBalance);
        assertEq(quoteToken.balanceOf(Bob), borrowerOneQuoteBalance);
        assertEq(baseToken.balanceOf(Carol), borrowerTwoBaseBalance);
        assertEq(quoteToken.balanceOf(Carol), borrowerTwoQuoteBalance);
        assertEq(baseToken.balanceOf(Takashi), takerBaseBalance - aliceGets / 2);
        assertEq(quoteToken.balanceOf(Takashi), takerQuoteBalance + DepositQT / 2);
        assertEq(getOrderQuantity(FirstOrderId), 0);
        assertEq(getOrderQuantity(SecondOrderId), DepositBT -  aliceGets / 4);
        assertEq(getOrderQuantity(ThirdOrderId), DepositBT -  aliceGets / 4);
        assertEq(getPositionQuantity(FirstPositionId), 0);
        assertEq(getPositionQuantity(SecondPositionId), 0);
        assertEq(getPoolDeposits(B), 0);
        assertEq(getPoolBorrows(B), 0);
    }

    // Same with many borrowers
    
    function test_TakeManyBorrowedBuyOrders() public {
        uint256 numberBorrowers = 5;
        depositBuyOrder(Alice, B, numberBorrowers * DepositQT, B + 3);
        for (uint256 i = 2; i <= (numberBorrowers + 1); i++) {
            depositSellOrder(acc[i], B + 3, DepositBT);
            borrow(acc[i], B, DepositQT / 2);
        }
        uint256 bookBaseBalance = baseToken.balanceOf(OrderBook);
        uint256 bookQuoteBalance = quoteToken.balanceOf(OrderBook);
        uint256 makerBaseBalance = baseToken.balanceOf(Alice);
        uint256 makerQuoteBalance = quoteToken.balanceOf(Alice);
        uint256 takerBaseBalance = baseToken.balanceOf(Takashi);
        uint256 takerQuoteBalance = quoteToken.balanceOf(Takashi);
        setPriceFeed(LowPrice / WAD);
        uint256 aliceGets = WAD * numberBorrowers * DepositQT / book.limitPrice(B);
        console.log("Alice gets", aliceGets / WAD, "ETH reposted in a sell order");
        uint256 takenAmount = numberBorrowers * DepositQT / 2;
        takeQuoteTokens(B, takenAmount);
        assertEq(baseToken.balanceOf(OrderBook), bookBaseBalance + aliceGets / 2);
        assertEq(quoteToken.balanceOf(OrderBook), bookQuoteBalance - takenAmount);
        assertEq(baseToken.balanceOf(Alice), makerBaseBalance);
        assertEq(quoteToken.balanceOf(Alice), makerQuoteBalance);
        assertEq(baseToken.balanceOf(Takashi), takerBaseBalance - aliceGets / 2);
        assertEq(quoteToken.balanceOf(Takashi), takerQuoteBalance + takenAmount);
        for (uint256 i = 2; i <= (numberBorrowers + 1); i++) 
            assertEq(getPositionQuantity(i - 2), 0);
        assertEq(getPoolDeposits(B), 0);
        assertEq(getPoolBorrows(B), 0);
    }

    // first taker is compelled to liquidate at least 3 positions
    // second taker liquidate the last one
    
    function test_ManyBorrowedBuyOrderTwoTaking() public {
        uint256 numberBorrowers = 4;
        depositBuyOrder(Alice, B, numberBorrowers * DepositQT, B + 3);
        for (uint256 i = 2; i <= (numberBorrowers + 1); i++) {
            depositSellOrder(acc[i], B + 3, DepositBT);
            borrow(acc[i], B, DepositQT / 2);
        }
        setPriceFeed(LowPrice / WAD);
        uint256 takenAmount = numberBorrowers * DepositQT / 2;
        takeQuoteTokens(B, 2 * takenAmount / 5);
        takeQuoteTokens(B, 3 * takenAmount / 5);
        uint256 borrowerRemainingAssets = DepositBT - WAD * (DepositQT / 2) / book.limitPrice(B);
        for (uint256 i = 2; i <= (numberBorrowers + 1); i++)
            assertEq(getOrderQuantity(i), borrowerRemainingAssets);
        uint256 aliceGets = WAD * numberBorrowers * DepositQT / book.limitPrice(B); // ETH reposted in a sell order
        assertEq(getOrderQuantity(numberBorrowers + 2), aliceGets);
        for (uint256 i = 2; i <= (numberBorrowers + 1); i++)
            assertEq(getPositionQuantity(i - 2), 0);
        assertEq(getPoolDeposits(B), 0);
        assertEq(getPoolBorrows(B), 0);
    }

    // Many borrowers with some repaying their debt before take
    
    function test_TakeManyOrdersWithRepayBefore() public {
        uint256 numberBorrowers = 5;
        uint256 availableCapital = 0;
        depositBuyOrder(Alice, B, numberBorrowers * DepositQT, B + 3);
        availableCapital += numberBorrowers * DepositQT;
        for (uint256 i = 2; i <= (numberBorrowers + 1); i++) {
            depositSellOrder(acc[i], B + 3, DepositBT);
            borrow(acc[i], B, DepositQT / 2);
            availableCapital -= DepositQT / 2;
            if (i % 2 == 0) {
                repay(acc[i], i - 1,  DepositQT / 2);
                availableCapital += DepositQT / 2;
            }
        }
        setPriceFeed(LowPrice / WAD);
        uint256 aliceGets = WAD * numberBorrowers * DepositQT / book.limitPrice(B);
        takeQuoteTokens(B, availableCapital);
        for (uint256 i = 2; i <= (numberBorrowers + 1); i++)
            assertEq(getPositionQuantity(i - 2), 0);
        assertEq(getOrderQuantity(FirstOrderId), 0);
        assertEq(getOrderQuantity(1 + numberBorrowers + 1), aliceGets);
        assertEq(getPoolDeposits(B), 0);
        assertEq(getPoolBorrows(B), 0);
    }

    // Taking two buy orders borrowed once correctly adjuts balances + orders are reposted as a sell orders
    // Alice and Carol posts in a buy order 20,000 at limit price 2000
    // Bob deposits 2 * 10 ETH and borrows 20,000 from pool
    // Takashi takes available USDC in buy order, receives 20,000 and gives 20,000/2000 = 10 ETH
    // Alice and Carol both get from Bob and Takashi 5 + 5 = 10 ETH each, which are reposted in a sell order at 2200
    // Bob gives part of his collateral: 20 - 20,000/2000 = 10 ETH
    
    function test_DepositTwiceTakeOneBorrow() public {
        depositBuyOrder(Alice, B, DepositQT, B + 3);
        depositBuyOrder(Carol, B, DepositQT, B + 3);
        depositSellOrder(Bob, B + 3, 2 * DepositBT);
        borrow(Bob, B, DepositQT);
        uint256 bookBaseBalance = baseToken.balanceOf(OrderBook);
        uint256 bookQuoteBalance = quoteToken.balanceOf(OrderBook);
        uint256 makerOneBaseBalance = baseToken.balanceOf(Alice);
        uint256 makerOneQuoteBalance = quoteToken.balanceOf(Alice);
        uint256 makerTwoBaseBalance = baseToken.balanceOf(Carol);
        uint256 makerTwoQuoteBalance = quoteToken.balanceOf(Carol);
        uint256 borrowerBaseBalance = baseToken.balanceOf(Bob);
        uint256 borrowerQuoteBalance = quoteToken.balanceOf(Bob);
        uint256 takerBaseBalance = baseToken.balanceOf(Takashi);
        uint256 takerQuoteBalance = quoteToken.balanceOf(Takashi);
        setPriceFeed(LowPrice / WAD);
        uint256 aliceGets = WAD * DepositQT / book.limitPrice(B);
        takeQuoteTokens(B, DepositQT);
        assertEq(baseToken.balanceOf(OrderBook), bookBaseBalance + aliceGets);
        assertEq(quoteToken.balanceOf(OrderBook), bookQuoteBalance - DepositQT);
        assertEq(baseToken.balanceOf(Alice), makerOneBaseBalance);
        assertEq(quoteToken.balanceOf(Alice), makerOneQuoteBalance);
        assertEq(baseToken.balanceOf(Alice), makerTwoBaseBalance);
        assertEq(quoteToken.balanceOf(Alice), makerTwoQuoteBalance);
        assertEq(baseToken.balanceOf(Bob), borrowerBaseBalance);
        assertEq(quoteToken.balanceOf(Bob), borrowerQuoteBalance);
        assertEq(baseToken.balanceOf(Takashi), takerBaseBalance - aliceGets);
        assertEq(quoteToken.balanceOf(Takashi), takerQuoteBalance + DepositQT);
        assertEq(getOrderQuantity(FirstOrderId), 0);
        assertEq(getOrderQuantity(SecondOrderId), 0);
        assertEq(getOrderQuantity(ThirdOrderId), 2 * DepositBT - aliceGets);
        assertEq(getPositionQuantity(FirstPositionId), 0);
        assertEq(getPoolDeposits(B), 0);
        assertEq(getPoolBorrows(B), 0);
    }

    // multiple deposits in same pool, one (big) borrower), then take
    function test_MultipleDepositTakeOneBorrow() public {
        uint256 numberDeposits = 10;
        for (uint256 i = 1; i <= numberDeposits; i++) {
            depositBuyOrder(acc[i], B, DepositQT, B + 3);
        }
        uint256 totalDeposits = numberDeposits * DepositQT;
        address borrower = acc[numberDeposits + 1];
        depositSellOrder(borrower, B + 3, numberDeposits * DepositBT);
        borrow(borrower, B, totalDeposits / 2);
        setPriceFeed(LowPrice / WAD);
        uint256 depositorGets = WAD * DepositQT / book.limitPrice(B);
        takeQuoteTokens(B, totalDeposits / 2);
        for (uint256 i = 1; i <= numberDeposits; i++)
            assertEq(getOrderQuantity(i), 0);
        assertEq(getOrderQuantity(numberDeposits + 1), numberDeposits * DepositBT - numberDeposits * depositorGets / 2);
        assertEq(getPositionQuantity(FirstPositionId), 0);
        assertEq(getPoolDeposits(B), 0);
        assertEq(getPoolBorrows(B), 0);
    }

    // multiple deposits in same pool, some withdraw before borrow and take
    function test_MultipleDepositSomeWithdrawBorrowTake() public {
        uint256 numberDeposits = 5;
        uint256 endNumberDeposits = numberDeposits;
        uint256 totalDeposits;
        for (uint256 i = 1; i <= numberDeposits; i++) {
            depositBuyOrder(acc[i], B, DepositQT, B + 3);
            totalDeposits += DepositQT;
            if (i % 2 == 0) {
                withdraw(acc[i], i, DepositQT);
                totalDeposits -= DepositQT;
                endNumberDeposits -= 1;
            }
        }
        address borrower = acc[numberDeposits + 1];
        depositSellOrder(borrower, B + 3, numberDeposits * DepositBT);
        borrow(borrower, B, totalDeposits / 2);
        setPriceFeed(LowPrice / WAD);
        uint256 depositorGets = WAD * DepositQT / book.limitPrice(B);
        takeQuoteTokens(B, totalDeposits / 2);
        for (uint256 i = 1; i <= numberDeposits; i++)
            assertEq(getOrderQuantity(i), 0);
        assertEq(getOrderQuantity(numberDeposits + 1), numberDeposits * DepositBT - endNumberDeposits * depositorGets / 2);
        assertEq(getPositionQuantity(FirstPositionId), 0);
        assertEq(getPoolDeposits(B), 0);
        assertEq(getPoolBorrows(B), 0);
    }

    // multiple deposits in same pool, multiple borrowers, then take

    // N depositors post in a buy order 20,000 at limit price 2000 => total deposits = N * 20,000
    // M borrowers deposit 10 ETH and borrows 10,000 from pool 2000 => total borrows = M * 10,000
    // Takashi takes available USDC in pool 2000, receives Y = N * 20,000 - M * 10,000 USDC and gives Y/2000 ETH
    // Depositors receive 20,000 / 2000 = 10 ETH reposted in a sell order
    // Borowers' deposit net of liquidated assets is 10 - 10,000 / 2000 = 5 ETH ou 10 - 10/2 ETH
    // Bob gives part of his collateral: 20 - 20,000/2000 = 10 ETH

    function test_MultipleDepositsAndBorrowersTake() public {
        uint256 numberDeposits = 45;
        uint256 numberBorrowers = numberDeposits;
        for (uint256 i = 1; i <= numberDeposits; i++) {
            depositBuyOrder(acc[i], B, DepositQT, B + 3);
        }
        uint256 totalDeposits = numberDeposits * DepositQT;
        for (uint256 i = numberDeposits + 1; i <= (numberDeposits + numberBorrowers); i++) {
            depositSellOrder(acc[i], B + 3, DepositBT);
            borrow(acc[i], B, DepositQT / 2);
        }
        uint256 totalBorrows = numberBorrowers * DepositQT / 2;
        setPriceFeed(LowPrice / WAD);
        uint256 depositorGets = WAD * DepositQT / book.limitPrice(B);
        takeQuoteTokens(B, totalDeposits - totalBorrows);
        for (uint256 i = 1; i <= numberDeposits; i++)
            assertEq(getOrderQuantity(i), 0);
        for (uint256 i = numberDeposits + 1; i <= (numberDeposits + numberBorrowers); i++) {
            assertEq(getOrderQuantity(i), DepositBT - depositorGets / 2);
            assertEq(getPositionQuantity(i - numberDeposits), 0);
            //checkBorrowingQuantity(i - numberDeposits, 0);
        }
        for (uint256 i = numberDeposits + 1 + numberBorrowers; i <= 2 * numberDeposits + numberBorrowers; i++) {
            assertEq(getOrderQuantity(i), depositorGets);
            // checkOrderQuantity(i, depositorGets);
        }
        assertEq(getPoolDeposits(B), 0);
        assertEq(getPoolBorrows(B), 0);
    }

    // multiple depositors, multiple borrowers, and multiple takers

    // N depositors post in a buy order 20,000 at limit price 2000 => total deposits = N * 20,000
    // M borrowers deposit 10 ETH and borrows 10,000 from pool 2000 => total borrows = M * 10,000
    // T takers receive Y = (N * 20,000 - M * 10,000)/T USDC and gives Y/2000 ETH

    function test_MultipleDepositsBorrowersAndTakers() public {
        uint256 numberDeposits = 40;
        uint256 numberBorrowers = numberDeposits;
        uint256 numberTakers = 4;
        for (uint256 i = 1; i <= numberDeposits; i++) {
            depositBuyOrder(acc[i], B, DepositQT, B + 3);
        }
        uint256 totalDeposits = numberDeposits * DepositQT;
        for (uint256 i = numberDeposits + 1; i <= (numberDeposits + numberBorrowers); i++) {
            depositSellOrder(acc[i], B + 3, DepositBT);
            borrow(acc[i], B, DepositQT / 2);
        }
        uint256 totalBorrows = numberBorrowers * DepositQT / 2;
        setPriceFeed(LowPrice / WAD);
        uint256 depositorGets = WAD * DepositQT / book.limitPrice(B);
        for (uint256 i = numberDeposits + numberBorrowers + 1; i <= (numberDeposits + numberBorrowers + numberTakers); i++) {
            vm.prank(acc[i]);
            book.takeQuoteTokens(B, (totalDeposits - totalBorrows) / numberTakers);
        }
        for (uint256 i = 1; i <= numberDeposits; i++) {
            assertEq(getOrderQuantity(i), 0);
            // checkOrderQuantity(i, 0);
        }

        for (uint256 i = numberDeposits + 1; i <= (numberDeposits + numberBorrowers); i++) {
            assertEq(getOrderQuantity(i), DepositBT - depositorGets / 2);
            //checkOrderQuantity(i, DepositBT - depositorGets / 2);
            assertEq(getPositionQuantity(i - numberDeposits), 0);
            //checkBorrowingQuantity(i - numberDeposits, 0);
        }
        for (uint256 i = numberDeposits + 1 + numberBorrowers; i <= 2 * numberDeposits + numberBorrowers; i++) {
            assertEq(getOrderQuantity(i), depositorGets);
            // checkOrderQuantity(i, depositorGets);
        }
        assertEq(getPoolDeposits(B), 0);
        assertEq(getPoolBorrows(B), 0);
    }

    // Custom test
    // Alice: 0x403B4ab728856Cd31972f7390B8445D2bD82bF18
    // Price of Genesis pool (1111111110) = 3200 => 2909 2644

    // function test_CustomTake() public {
    //    vm.warp(0); // setting starting timestamp to 0
    //    setPriceFeed(3210000000000000000000 / WAD); // set price at 3210
    //    depositBuyOrder(Alice, 1111111106, 100000000000000000000000, 1111111106 + 1);  // id 1, 100,000 USDC at 2644
    //    depositInBaseAccount(Alice, 30000000000000000000); // 30 ETH
    //    vm.warp(10 * 60 * 60); // 
    //    borrow(Alice, 1111111106, 60000000000000000000000);  // id 1 borrow 60,000 USDC at 2644
    //    vm.warp(100 * 60 * 60); // 
    //    repay(Alice, 1, 20000000000000000000000); // repay 20,000 USDC at 2644
    //    setPriceFeed(2520); // current price = 2520
    //    vm.warp(500 * 60 * 60); // 
    //    vm.prank(Alice);
    //    book.takeQuoteTokens(1111111106, 29000000000000000000000); // take 29,000 USDC
    // }


}