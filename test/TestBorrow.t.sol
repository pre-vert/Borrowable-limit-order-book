// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Setup} from "./Setup.sol";
import {MathLib, WAD} from "../lib/MathLib.sol";

contract TestBorrow is Setup {

    // ok if borrower is maker
    // market price set initially at 2001
    // deposit buy order at limit price = 2000 = limit price pool(0) < market price
    // deposit sell order price at 2200 = limit price pool(1) > market price 

    function test_BorrowBuyOrderOkIfMaker() public {
        depositBuyOrder(Alice, B, DepositQT, B + 1);
        depositSellOrder(Alice, B + 3, DepositBT, B + 2);
        borrow(Alice, B , DepositQT / 2);
        checkOrderQuantity(FirstOrderId, DepositQT);
        checkBorrowingQuantity(FirstPositionId, DepositQT / 2); 
    }

    // borrow reverts if borrow base tokens in sell order pool
    function test_BorrowRevertsIfBaseTokens() public depositSell(B + 3) depositSell(B + 5) {
        vm.expectRevert("Cannot borrow_0");
        borrow(Bob, B + 3, DepositBT / 2);
    }

    // borrow reverts if pool empty
    function test_BorrowNonExistingBuyOrder() public setLowPrice() depositSell(B + 1) {
        vm.expectRevert("Cannot borrow_0");
        borrow(Bob, B - 1, DepositQT / 2);
    }
    
    // reverts if borrowing is zero
    function test_BorrowBuyOrderFailsIfZero() public 
        depositBuy(B) setLowPrice() depositSell(B + 1) {
        vm.expectRevert("Borrow zero");
        borrow(Bob, B, 0);
    }
    
    // borrow of buy order correctly adjusts balances
    function test_BorrowBuyOrderCheckBalances() public depositBuy(B) depositSell(B + 3) {
        uint256 bookBalance = quoteToken.balanceOf(OrderBook);
        uint256 lenderBalance = quoteToken.balanceOf(Alice);
        uint256 borrowerBalance = quoteToken.balanceOf(Bob);
        borrow(Bob, B, DepositQT / 2);
        assertEq(quoteToken.balanceOf(OrderBook), bookBalance - DepositQT / 2);
        assertEq(quoteToken.balanceOf(Alice), lenderBalance);
        assertEq(quoteToken.balanceOf(Bob), borrowerBalance + DepositQT / 2);
        checkOrderQuantity(FirstOrderId, DepositQT);
        checkOrderQuantity(SecondOrderId, DepositBT);
        checkBorrowingQuantity(FirstPositionId, DepositQT / 2); 
    }

    // borrow of buy order collateralized by quote tokens in buy orders correctly adjusts balances
    // market price set initially at 2001
    // Alice deposits buy order at 2000 (initialPriceWAD)
    // price is set at 2201
    // Bob deposits buy order at 2200 and borrows quote tokens from Alice

    function test_BorrowBuyOrderWithQuoteTokens() public depositBuy(B) {
        setPriceFeed(genesisLimitPriceWAD / WAD + 201);
        depositBuyOrder(Bob, B + 2, DepositQT, B + 3);
        uint256 bookBalance = quoteToken.balanceOf(OrderBook);
        uint256 lenderBalance = quoteToken.balanceOf(Alice);
        uint256 borrowerBalance = quoteToken.balanceOf(Bob);
        borrow(Bob, B, DepositQT / 2);
        assertEq(quoteToken.balanceOf(OrderBook), bookBalance - DepositQT / 2);
        assertEq(quoteToken.balanceOf(Alice), lenderBalance);
        assertEq(quoteToken.balanceOf(Bob), borrowerBalance + DepositQT / 2);
        checkOrderQuantity(FirstOrderId, DepositQT);
        checkOrderQuantity(SecondOrderId, DepositQT);
        checkBorrowingQuantity(FirstPositionId, DepositQT / 2); 
    }

    // revert if borrow all assets in a pool
    function test_FailsIfBorrowAllDeposit() public depositBuy(B) depositSell(B + 3) {
        vm.expectRevert("Borrow too much_2");
        borrow(Bob, B, DepositQT); 
    }

    // Borrower excess collateral in base token is correct
    // Alice deposits buy order of 20,000 at limit price 2000 => EC = ALTV * 20,000 / 2000 = 9.8
    // Bob deposits sell order of 10 at limit price 2200 => EC = ALTV * 10 = 9.8
    // borrows 20,000/2 at limit price 2000 => EC = EC - 20,000 / (2*2000) = 9.8 - 5 = 4.8

    function test_BorrowBuyOrderExcessCollateral() public depositBuy(B) depositSell(B + 3) {
        uint256 ALTV = book.ALTV();
        uint256 excessCollateral = book.getUserExcessCollateral(Bob, 0, ALTV);
        uint256 limitPrice = book.limitPrice(B);
        borrow(Bob, B , DepositQT / 2);
        assertEq(book.getUserExcessCollateral(Bob, 0, ALTV), excessCollateral - WAD * DepositQT / (2 * limitPrice));
    }

    // Bob borrows from Alice's sell order, borrowFromIds array correctly updates
    function test_BorrowFromIdInUsers() public depositBuy(B) depositSell(B + 3) {
        checkUserBorrowId(Bob, FirstRow, NoPositionId);
        borrow(Bob, B, DepositQT / 2);
        checkUserBorrowId(Bob, FirstRow, FirstPositionId);
        checkUserBorrowId(Bob, SecondRow, NoPositionId);
    }

    // As Bob borrows twice from same pool, borrowing positions should be aggregated
    function test_BorrowTwiceFromSamePool() public depositBuy(B) depositSell(B + 3) {
        borrow(Bob, B, DepositQT / 4);
        borrow(Bob, B, DepositQT / 4);
        checkUserBorrowId(Bob, FirstRow, FirstPositionId);
        checkUserBorrowId(Bob, SecondRow, NoPositionId);
        checkBorrowingQuantity(FirstPositionId, DepositQT / 2);
        checkBorrowingQuantity(SecondPositionId, 0);
    }

    // Bob borrows twice from two distinct pools, borrowing positions should not be aggregated
    function test_BorrowTwiceFromDifferentPool() public 
        depositBuy(B) depositBuy(B - 2) depositSell(B + 3) {
        borrow(Bob, B, DepositQT / 4);
        borrow(Bob, B - 2, DepositQT / 4);
        checkUserBorrowId(Bob, FirstRow, FirstPositionId);
        checkUserBorrowId(Bob, SecondRow, SecondPositionId);
        checkBorrowingQuantity(FirstPositionId, DepositQT / 4);
        checkBorrowingQuantity(SecondPositionId, DepositQT / 4);
    }

    // fail if user has more than max number of positions
    // market price set initially at 2001
    // deposit sell order at initial price = 2000 = limit price pool(0) < market price
    // deposit sell order price at 2200 = limit price pool(1) > market price 

    function test_PositionsForUserExceedLimit() public {
        uint256 maxPositions = book.MAX_POSITIONS();
        uint256 borrowedQuantity = DepositBT * 5 / (maxPositions + 2);
        setPriceFeed(genesisLimitPriceWAD / WAD - 2);
        depositSellOrder(Alice, B + 1, 3 * DepositBT, B - 2);
        setPriceFeed(genesisLimitPriceWAD / WAD + 2);
        for (uint256 i = 2; i <= (maxPositions + 1); i++) {
            depositBuyOrder(acc[i], B - 2 * (i - 2), DepositQT, B + 3);
            borrow(Alice, B - 2 * (i - 2), borrowedQuantity);
            checkBorrowingQuantity(i - 1, borrowedQuantity);
        }
        uint256 agentId = maxPositions + 2;
        depositBuyOrder(acc[agentId], B - 2 * (agentId - 2), DepositQT, B + 3);
        vm.expectRevert("Max positions reached");
        borrow(Alice, B - 2 * (agentId - 2), borrowedQuantity);
    }

    // borrower of buy order is maker correctly adjusts balances
    function test_MakerBorrowsHerBuyOrderCheckBalances() public depositBuy(B) {
        depositSellOrder(Alice, B + 3, DepositBT, B +2);
        uint256 bookBalance = quoteToken.balanceOf(OrderBook);
        uint256 lenderBorrowerBalance = quoteToken.balanceOf(Alice);
        borrow(Alice, B, DepositQT / 2);
        assertEq(quoteToken.balanceOf(OrderBook), bookBalance - DepositQT / 2);
        assertEq(quoteToken.balanceOf(Alice), lenderBorrowerBalance + DepositQT / 2);
        checkOrderQuantity(FirstOrderId, DepositQT);
        checkOrderQuantity(SecondOrderId, DepositBT);
        checkBorrowingQuantity(FirstPositionId, DepositQT / 2);
    }

    // take pool of borrowed quotes collateralized by quotes correctly adjust balances
    // price 2001: Alice deposits 20,000 in buy order at 2000
    // price 2201: Bob deposits 20,000 in buy order at 2200 and borrows 10,000 from Alice
    
    function test_TakeBorrowWithQuoteTokens() public depositBuy(B) {
        setPriceFeed(genesisLimitPriceWAD / WAD + 201);
        depositBuyOrder(Bob, B + 2, DepositQT, B + 3);
        uint256 bookBaseBalance = baseToken.balanceOf(OrderBook);
        uint256 bookQuoteBalance = quoteToken.balanceOf(OrderBook);
        uint256 makerBaseBalance = baseToken.balanceOf(Alice);
        uint256 makerQuoteBalance = quoteToken.balanceOf(Alice);
        uint256 borrowerBaseBalance = baseToken.balanceOf(Bob);
        uint256 borrowerQuoteBalance = quoteToken.balanceOf(Bob);
        borrow(Bob, B, DepositQT / 2);
        assertEq(baseToken.balanceOf(OrderBook), bookBaseBalance);
        assertEq(quoteToken.balanceOf(OrderBook), bookQuoteBalance - DepositQT / 2);
        assertEq(baseToken.balanceOf(Alice), makerBaseBalance);
        assertEq(quoteToken.balanceOf(Alice), makerQuoteBalance);
        assertEq(baseToken.balanceOf(Bob), borrowerBaseBalance);
        assertEq(quoteToken.balanceOf(Bob), borrowerQuoteBalance + DepositQT / 2);
        checkBorrowingQuantity(FirstPositionId, DepositQT / 2); 
    }
    
    // // test liquidate a huge number of positions at once
    // // max_position 0 take() 150101 gas diff 108747/5 = 21749 (au lieu de 5843*5 = 29215)
    // // max_position 5 take() 258848 gas
    // // max_position 15 take() 317282 gas diff = 58434/10 = 5843
    // // max_position 25 take() 375742 gas diff = 117000/20 = 5850

    // function test_LiquidateHugeNumberOfPositionsAtOnce() public {
    //     uint256 maxPosition = book.MAX_POSITIONS() - 1;
    //     depositBuyOrder(Alice, ReceivedQuoteToken / WAD, LowPrice);
    //     for (uint256 i = 2; i <= (maxPosition+1); i++) {
    //         depositSellOrder(acc[i], DepositBT, HighPrice);
    //         borrow(acc[i], Alice_Order, DepositQT / 10);
    //     }
    //     setPriceFeed(UltraLowPrice);
    //     take(acc[maxPosition+2], Alice_Order, 0);
    //     for (uint256 i = 2; i <= (maxPosition+1); i++) {
    //         checkBorrowingQuantity(i, 0);
    //     }
    // }

}
