// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Setup} from "./Setup.sol";
import {MathLib, WAD} from "../lib/MathLib.sol";

contract TestTake is Setup {

    // taking half vanilla buy order succeeds + liquidity is correctly reposted
    function test_TakingHalfBuyOrder() public depositBuy(B) {
        setPriceFeed(1990);
        takeQuoteTokens(Bob, B, DepositQT / 2);
        checkOrderQuantity(FirstOrderId, DepositQT / 2);
        uint256 aliceGets = WAD * (DepositQT / book.limitPrice(B)) / 2;
        checkOrderQuantity(SecondOrderId, aliceGets);
    }
    
    // taking half vanilla sell order succeeds
    function test_TakingHalfSellOrder() public setLowPrice() depositSell(B + 1) {
        setPriceFeed(2010);
        takeBaseTokens(Bob, B + 1, DepositBT / 2);
        checkOrderQuantity(FirstOrderId, DepositBT / 2);
        uint256 aliceGets = ((DepositBT * book.limitPrice(B + 1)) / 2) / WAD;
        checkOrderQuantity(SecondOrderId, aliceGets);
    }
    
    // taking fails if non-existing buy order
    function test_TakingBuyOrderFailsIfEmptyPool() public depositBuy(B) {
        setPriceFeed(1990);
        vm.expectRevert("Pool_empty_2");
        takeQuoteTokens(Bob, B + 1, DepositQT);
        checkOrderQuantity(FirstOrderId, DepositQT);
    }

    // taking fails if non existing sell order
    function test_TakingSellOrderFailsIfEmptyPool() public setLowPrice() depositSell(B + 1) {
        setPriceFeed(2010);
        vm.expectRevert("Pool_empty_2");
        takeBaseTokens(Bob, B - 1, DepositBT);
    }

    // take buy order for zero is ok
    function test_takeBuyOrderWithZero() public depositBuy(B) {
        setPriceFeed(1990);
        takeQuoteTokens(Bob, B, 0);
        checkOrderQuantity(FirstOrderId, DepositQT);
    }

    // take sell order for zero reverts
    function test_TakingSellOrderFailsIfZeroTaken() public setLowPrice() depositSell(B + 1) {
        setPriceFeed(2010);
        vm.expectRevert("Take zero");
        takeBaseTokens(Bob, B + 1, 0);
    }

    // taking fails if greater than non borrowed pool of buy order
    function test_TakeBuyOrderFailsIfTooMuch() public depositBuy(B) {
        setPriceFeed(1990);
        vm.expectRevert("Take too much");
        takeQuoteTokens(Bob, B, 2 * DepositQT);
    }

    // taking fails if greater than pool of sell orders
    function test_TakeSellOrderFailsIfTooMuch() public setLowPrice() depositSell(B + 1) {
        setPriceFeed(2010);
        vm.expectRevert("Take too much");
        takeBaseTokens(Bob, B + 1, 2 * DepositBT);
    }

    // taking non profitable sell orders just loses money
    function test_TakingIsOkIfNonProfitableSellOrder() public setLowPrice() depositSell(B + 1) {
        takeBaseTokens(Bob, B + 1, DepositBT);
        checkOrderQuantity(FirstOrderId, 0);
    }

    // taking 0 from non profitable sell orders reverts
    function test_TakingIIfNonProfitableSellOrder() public setLowPrice() depositSell(B + 1) {
        vm.expectRevert("Take zero");
        takeBaseTokens(Bob, B + 1, 0);
    }

    // taking non profitable buy orders reverts
    function test_TakingFailsIfNonProfitableBuyOrder() public depositBuy(B) {
        vm.expectRevert("Not profitable");
        takeQuoteTokens(Bob, B, DepositQT);
    }

    // taking non profitable buy orders with 0 reverts
    function test_TakingZeroFailsIfNonProfitableBuyOrder() public depositBuy(B) {
        vm.expectRevert("Not profitable");
        takeQuoteTokens(Bob, B, 0);
    }

    // taking vanilla buy order correctly adjuts balances + order is reposted as a sell order
    // market price set initially at 2001, deposit buy order at 2000
    // set price feed 1990 : buy order becomes takable

    function test_TakingBuyOrder() public depositBuy(B) setLowPrice() {
        uint256 orderBookBaseBalance = baseToken.balanceOf(OrderBook);
        uint256 orderBookQuoteBalance = quoteToken.balanceOf(OrderBook);
        uint256 makerBaseBalance = baseToken.balanceOf(Alice);
        uint256 makerQuoteBalance = quoteToken.balanceOf(Alice);
        uint256 takerBaseBalance = baseToken.balanceOf(Bob);
        uint256 takerQuoteBalance = quoteToken.balanceOf(Bob);
        uint256 aliceGets = WAD * DepositQT / book.limitPrice(B);
        takeQuoteTokens(Bob, B, DepositQT);
        assertEq(baseToken.balanceOf(Alice), makerBaseBalance);   // BT are not sent to Alice's wallet but reposted
        assertEq(quoteToken.balanceOf(Alice), makerQuoteBalance);
        assertEq(baseToken.balanceOf(Bob), takerBaseBalance - aliceGets);
        assertEq(quoteToken.balanceOf(Bob), takerQuoteBalance + DepositQT);
        assertEq(baseToken.balanceOf(OrderBook), orderBookBaseBalance + aliceGets);
        assertEq(quoteToken.balanceOf(OrderBook), orderBookQuoteBalance - DepositQT);
        checkOrderQuantity(FirstOrderId, 0);
        checkOrderQuantity(SecondOrderId, aliceGets);
    }
    
    // taking vanilla sell order correctly adjuts balances + order is reposted as a buy order
    function test_TakingSellOrder() public setLowPrice() depositSell(B + 1) setHighPrice() {
        uint256 orderBookBaseBalance = baseToken.balanceOf(OrderBook);
        uint256 orderBookQuoteBalance = quoteToken.balanceOf(OrderBook);
        uint256 makerQuoteBalance = quoteToken.balanceOf(Alice);
        uint256 makerBaseBalance = baseToken.balanceOf(Alice);
        uint256 takerBaseBalance = baseToken.balanceOf(Bob);
        uint256 takerQuoteBalance = quoteToken.balanceOf(Bob);
        uint256 aliceGets = DepositBT * book.limitPrice(B + 1) / WAD;
        takeBaseTokens(Bob, B + 1, DepositBT);
        assertEq(baseToken.balanceOf(OrderBook), orderBookBaseBalance - DepositBT);
        assertEq(quoteToken.balanceOf(OrderBook), orderBookQuoteBalance + aliceGets);
        assertEq(quoteToken.balanceOf(Alice), makerQuoteBalance); // quotes are not sent to Alice's wallet but reposted
        assertEq(baseToken.balanceOf(Alice), makerBaseBalance);
        assertEq(baseToken.balanceOf(Bob), takerBaseBalance + DepositBT);
        assertEq(quoteToken.balanceOf(Bob), takerQuoteBalance - aliceGets);
        checkOrderQuantity(FirstOrderId, 0);
        checkOrderQuantity(SecondOrderId, aliceGets);
    }

    // taking buy order by maker correctly adjuts balances
    function test_TakingBuyOrderByMaker() public depositBuy(B) setLowPrice() {
        uint256 orderBookBaseBalance = baseToken.balanceOf(OrderBook);
        uint256 orderBookQuoteBalance = quoteToken.balanceOf(OrderBook);
        uint256 makerBaseBalance = baseToken.balanceOf(Alice);
        uint256 makerQuoteBalance = quoteToken.balanceOf(Alice);
        uint256 aliceGets = WAD * DepositQT / book.limitPrice(B );
        console.log("Alice gets", aliceGets / WAD);
        takeQuoteTokens(Alice, B, DepositQT);
        assertEq(baseToken.balanceOf(Alice), makerBaseBalance  - aliceGets); // as a taker
        assertEq(quoteToken.balanceOf(Alice), makerQuoteBalance + DepositQT); // as a taker
        assertEq(baseToken.balanceOf(OrderBook), orderBookBaseBalance + aliceGets);
        assertEq(quoteToken.balanceOf(OrderBook), orderBookQuoteBalance - DepositQT);
        checkOrderQuantity(FirstOrderId, 0);
        checkOrderQuantity(SecondOrderId, aliceGets);
    }

    // taking sell order by maker correctly adjuts balances
    function test_TakingSellOrderByMaker() public setLowPrice() depositSell(B + 1) setHighPrice() {
        uint256 orderBookBaseBalance = baseToken.balanceOf(OrderBook);
        uint256 orderBookQuoteBalance = quoteToken.balanceOf(OrderBook);
        uint256 makerQuoteBalance = quoteToken.balanceOf(Alice);
        uint256 makerBaseBalance = baseToken.balanceOf(Alice);
        uint256 aliceGets = DepositBT * book.limitPrice(B + 1) / WAD;
        takeBaseTokens(Alice, B + 1, DepositBT);
        assertEq(baseToken.balanceOf(OrderBook), orderBookBaseBalance - DepositBT);
        assertEq(quoteToken.balanceOf(OrderBook), orderBookQuoteBalance + aliceGets); // 
        assertEq(baseToken.balanceOf(Alice), makerBaseBalance  + DepositBT); // as a taker
        assertEq(quoteToken.balanceOf(Alice), makerQuoteBalance - aliceGets); // as a taker
        checkOrderQuantity(FirstOrderId, 0);
        checkOrderQuantity(SecondOrderId, aliceGets);
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
        takeQuoteTokens(Takashi, B, 3 * DepositQT / 5);
        assertEq(baseToken.balanceOf(OrderBook), bookBaseBalance + 3 * aliceGets / 5);
        assertEq(quoteToken.balanceOf(OrderBook), bookQuoteBalance - 3 * DepositQT / 5);
        assertEq(baseToken.balanceOf(Alice), makerBaseBalance); // BT are not sent to Alice's wallet but reposted
        assertEq(quoteToken.balanceOf(Alice), makerQuoteBalance);
        assertEq(baseToken.balanceOf(Bob), borrowerBaseBalance);
        assertEq(quoteToken.balanceOf(Bob), borrowerQuoteBalance);
        assertEq(baseToken.balanceOf(Takashi), takerBaseBalance - 3 * aliceGets / 5);
        assertEq(quoteToken.balanceOf(Takashi), takerQuoteBalance + 3 * DepositQT / 5);
        checkOrderQuantity(FirstOrderId, 0);
        checkOrderQuantity(SecondOrderId, DepositBT - 2 * DepositBT / 10);
        checkOrderQuantity(ThirdOrderId, aliceGets);
        checkBorrowingQuantity(FirstPositionId, 0);
    }

    // taking buy order fails if exceeds available assets
    function test_TakingBuyOrderFailsIfExceedsAvailableAssets() public depositBuy(B) depositSell(B + 3) {
        borrow(Bob, B, 4 * DepositQT / 5);
        setPriceFeed(LowPrice / WAD);
        vm.expectRevert("Take too much");
        takeQuoteTokens(Takashi, B, 2 * DepositQT / 5);
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
        takeQuoteTokens(Takashi, B, totalDeposits);
        for (uint256 i = 1; i <= numberDeposits; i++) {
            checkOrderQuantity(i, 0);
        }
        for (uint256 i = numberDeposits + 1; i <= 2 * numberDeposits; i++) {
            checkOrderQuantity(i, depositorGets);
        }
        checkPoolDeposits(B, 0);
        checkPoolBorrows(B, 0);
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
        console.log("Alice gets", aliceGets / WAD, "ETH reposted in a sell order");
        takeQuoteTokens(Takashi, B, DepositQT / 2);
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
        checkOrderQuantity(FirstOrderId, 0);
        checkOrderQuantity(SecondOrderId, DepositBT -  aliceGets / 4);
        checkOrderQuantity(ThirdOrderId, DepositBT -  aliceGets / 4);
        checkBorrowingQuantity(FirstPositionId, 0);
        checkBorrowingQuantity(SecondPositionId, 0);
        checkPoolDeposits(B, 0);
        checkPoolBorrows(B, 0);
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
        takeQuoteTokens(Takashi, B, takenAmount);
        assertEq(baseToken.balanceOf(OrderBook), bookBaseBalance + aliceGets / 2);
        assertEq(quoteToken.balanceOf(OrderBook), bookQuoteBalance - takenAmount);
        assertEq(baseToken.balanceOf(Alice), makerBaseBalance);
        assertEq(quoteToken.balanceOf(Alice), makerQuoteBalance);
        assertEq(baseToken.balanceOf(Takashi), takerBaseBalance - aliceGets / 2);
        assertEq(quoteToken.balanceOf(Takashi), takerQuoteBalance + takenAmount);
        for (uint256 i = 2; i <= (numberBorrowers + 1); i++) 
            checkBorrowingQuantity(i - 2, 0);
        checkPoolDeposits(B, 0);
        checkPoolBorrows(B, 0);
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
        takeQuoteTokens(Takashi, B, 2 * takenAmount / 5);
        takeQuoteTokens(Takashi, B, 3 * takenAmount / 5);
        uint256 borrowerRemainingAssets = DepositBT - WAD * (DepositQT / 2) / book.limitPrice(B);
        for (uint256 i = 2; i <= (numberBorrowers + 1); i++)
            checkOrderQuantity(i, borrowerRemainingAssets);
        uint256 aliceGets = WAD * numberBorrowers * DepositQT / book.limitPrice(B); // ETH reposted in a sell order
        checkOrderQuantity(numberBorrowers + 2, aliceGets);
        for (uint256 i = 2; i <= (numberBorrowers + 1); i++) 
            checkBorrowingQuantity(i - 2, 0);
        checkPoolDeposits(B, 0);
        checkPoolBorrows(B, 0);
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
        takeQuoteTokens(Takashi, B, availableCapital);
        for (uint256 i = 2; i <= (numberBorrowers + 1); i++) 
            checkBorrowingQuantity(i - 2, 0);
        checkOrderQuantity(FirstOrderId, 0);
        checkOrderQuantity(1 + numberBorrowers + 1, aliceGets);
        checkPoolDeposits(B, 0);
        checkPoolBorrows(B, 0);
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
        takeQuoteTokens(Takashi, B, DepositQT);
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
        checkOrderQuantity(FirstOrderId, 0);
        checkOrderQuantity(SecondOrderId, 0);
        checkOrderQuantity(ThirdOrderId, 2 * DepositBT - aliceGets);
        checkBorrowingQuantity(FirstPositionId, 0);
        checkPoolDeposits(B, 0);
        checkPoolBorrows(B, 0);
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
        takeQuoteTokens(Takashi, B, totalDeposits / 2);
        for (uint256 i = 1; i <= numberDeposits; i++) {
            checkOrderQuantity(i, 0);
        }
        checkOrderQuantity(numberDeposits + 1, numberDeposits * DepositBT - numberDeposits * depositorGets / 2);
        checkBorrowingQuantity(FirstPositionId, 0);
        checkPoolDeposits(B, 0);
        checkPoolBorrows(B, 0);
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
        takeQuoteTokens(Takashi, B, totalDeposits / 2);
        for (uint256 i = 1; i <= numberDeposits; i++) {
            checkOrderQuantity(i, 0);
        }
        checkOrderQuantity(numberDeposits + 1, numberDeposits * DepositBT - endNumberDeposits * depositorGets / 2);
        checkBorrowingQuantity(FirstPositionId, 0);
        checkPoolDeposits(B, 0);
        checkPoolBorrows(B, 0);
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
        takeQuoteTokens(Takashi, B, totalDeposits - totalBorrows);
        for (uint256 i = 1; i <= numberDeposits; i++) {
            checkOrderQuantity(i, 0);
        }
        for (uint256 i = numberDeposits + 1; i <= (numberDeposits + numberBorrowers); i++) {
            checkOrderQuantity(i, DepositBT - depositorGets / 2);
            checkBorrowingQuantity(i - numberDeposits, 0);
        }
        for (uint256 i = numberDeposits + 1 + numberBorrowers; i <= 2 * numberDeposits + numberBorrowers; i++) {
            checkOrderQuantity(i, depositorGets);
        }
        checkPoolDeposits(B, 0);
        checkPoolBorrows(B, 0);
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
            takeQuoteTokens(acc[i], B, (totalDeposits - totalBorrows) / numberTakers);
        }
        for (uint256 i = 1; i <= numberDeposits; i++) {
            checkOrderQuantity(i, 0);
        }

        for (uint256 i = numberDeposits + 1; i <= (numberDeposits + numberBorrowers); i++) {
            checkOrderQuantity(i, DepositBT - depositorGets / 2);
            checkBorrowingQuantity(i - numberDeposits, 0);
        }
        for (uint256 i = numberDeposits + 1 + numberBorrowers; i <= 2 * numberDeposits + numberBorrowers; i++) {
            checkOrderQuantity(i, depositorGets);
        }
        checkPoolDeposits(B, 0);
        checkPoolBorrows(B, 0);
    }


}