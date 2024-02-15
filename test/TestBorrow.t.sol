// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Setup} from "./Setup.sol";
import {MathLib, WAD} from "../lib/MathLib.sol";

contract TestBorrow is Setup {

    // ok if borrower is maker
    // market price set initially at 2001
    // deposit buy order at initial price = 2000 = limit price pool(0) < market price
    // deposit sell order price at 2200 = limit price pool(1) > market price 

    function test_BorrowBuyOrderOkIfMaker() public {
        depositBuyOrder(Alice, FirstPoolId, DepositQT, FirstPoolId + 1);
        depositSellOrder(Alice, FirstPoolId + 1, DepositBT, FirstPoolId);
        borrow(Alice, FirstPoolId, DepositQT / 2);
        checkOrderQuantity(FirstOrderId, DepositQT);
        checkBorrowingQuantity(FirstPositionId, DepositQT / 2); 
    }

    // borrow reverts if non-existing buy order
    function test_BorrowNonExistingBuyOrder() public setLowPrice() depositSell(FirstPoolId) {
        vm.expectRevert("Pool has no orders_1");
        borrow(Bob, FirstPoolId - 1, DepositQT / 2);
    }
    
    // reverts if borrowing is zero
    function test_BorrowBuyOrderFailsIfZero() public 
        depositBuy(FirstPoolId) setLowPrice() depositSell(FirstPoolId + 1) {
        vm.expectRevert("Must be positive");
        borrow(Bob, FirstPoolId, 0);
    }
    
    // borrow of buy order correctly adjusts balances
    function test_BorrowBuyOrderCheckBalances() public depositBuy(FirstPoolId) depositSell(FirstPoolId + 1) {
        uint256 bookBalance = quoteToken.balanceOf(OrderBook);
        uint256 lenderBalance = quoteToken.balanceOf(Alice);
        uint256 borrowerBalance = quoteToken.balanceOf(Bob);
        borrow(Bob, FirstPoolId,  DepositQT / 2);
        assertEq(quoteToken.balanceOf(OrderBook), bookBalance - DepositQT / 2);
        assertEq(quoteToken.balanceOf(Alice), lenderBalance);
        assertEq(quoteToken.balanceOf(Bob), borrowerBalance + DepositQT / 2);
        checkOrderQuantity(FirstOrderId, DepositQT);
        checkOrderQuantity(SecondOrderId, DepositBT);
        checkBorrowingQuantity(FirstPositionId, DepositQT / 2); 
    }

    // revert if borrow all assets in a pool
    function test_FailsIfBorrowAllDeposit() public depositBuy(FirstPoolId) depositSell(FirstPoolId + 1) {
        vm.expectRevert("Borrow too much_2");
        borrow(Bob, FirstPoolId, DepositQT); 
    }

    // revert if borrow more than available assets in a pool
    function test_FailsIfBorrowMoreThanDeposit() public depositBuy(FirstPoolId) depositSell(FirstPoolId + 1) {
        vm.expectRevert("Borrow too much_2");
        borrow(Bob, FirstPoolId, DepositQT); 
    }

    // Lender and borrower excess collaterals in quote and base token are correct
    // Alice deposits buy order of 20,000 at initial price 2000 => EC = ALTV * 20000 / 2000 = 9.8
    // Bob deposits sell order of 10 at initial price = 2200 => EC = ALTV * 10 = 9.8
    // borrow 10000 => EC = EC - 10000 / 2000 = 9.8 - 5 = EC - 4.8

    function test_BorrowBuyOrderExcessCollateral() public depositBuy(FirstPoolId) depositSell(FirstPoolId + 1) {
        uint256 ALTV = book.ALTV();
        uint256 excessCollateral = book.getUserExcessCollateral(Bob, 0, ALTV);
        uint256 limitPrice = book.limitPrice(FirstPoolId);
        borrow(Bob, FirstPoolId, DepositQT / 2);
        assertEq(book.getUserExcessCollateral(Bob, 0, ALTV), excessCollateral - WAD * DepositQT / (2 * limitPrice));
    }

    // Bob borrows from Alice's sell order, borrowFromIds array correctly updates
    function test_BorrowFromIdInUsers() public depositBuy(FirstPoolId) depositSell(FirstPoolId + 1) {
        checkUserBorrowId(Bob, FirstRow, NoPositionId);
        borrow(Bob, FirstPoolId, DepositQT / 2);
        checkUserBorrowId(Bob, FirstRow, FirstPositionId);
        checkUserBorrowId(Bob, SecondRow, NoPositionId);
    }

    // Bob borrows twice from same pool, borrowing positions should be aggregated
    function test_BorrowTwiceFromSamePool() public depositBuy(FirstPoolId) depositSell(FirstPoolId + 1) {
        borrow(Bob, FirstPoolId, DepositQT / 4);
        borrow(Bob, FirstPoolId, DepositQT / 4);
        checkUserBorrowId(Bob, FirstRow, FirstPositionId);
        checkUserBorrowId(Bob, SecondRow, NoPositionId);
        checkBorrowingQuantity(FirstPositionId, DepositQT / 2);
        checkBorrowingQuantity(SecondPositionId, 0);
    }

    // Bob borrows twice from two distinct pools, borrowing positions should not be aggregated
    function test_BorrowTwiceFromDifferentPool() public 
        depositBuy(FirstPoolId) depositBuy(FirstPoolId - 1) depositSell(FirstPoolId + 1) {
        borrow(Bob, FirstPoolId, DepositQT / 4);
        borrow(Bob, FirstPoolId - 1, DepositQT / 4);
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
        uint256 borrowedQuantity = DepositBT * 5 / (maxPositions+2);
        setPriceFeed(initialPriceWAD / WAD - 2);
        depositSellOrder(Alice, FirstPoolId, 3 * DepositBT, FirstPoolId - 1);
        for (uint256 i = 2; i <= (maxPositions+1); i++) {
            int24 j = int24(int256(i));
            depositBuyOrder(acc[i], FirstPoolId - j + 1, DepositQT, FirstPoolId);
            borrow(Alice, FirstPoolId - j + 1, borrowedQuantity);
            checkBorrowingQuantity(i-1, borrowedQuantity);
        }
        uint256 agentId = maxPositions+2;
        int24 agentIdInt24 = int24(int256(agentId));
        depositBuyOrder(acc[agentId], FirstPoolId - agentIdInt24 + 1, DepositQT, FirstPoolId);
        vm.expectRevert("Max positions reached");
        borrow(Alice, FirstPoolId - agentIdInt24 + 1, borrowedQuantity);
    }

    // borrower of buy order is maker correctly adjusts balances
    function test_MakerBorrowsHerBuyOrderCheckBalances() public depositBuy(FirstPoolId) {
        depositSellOrder(Alice, FirstPoolId + 1, DepositBT, FirstPoolId);
        uint256 bookBalance = quoteToken.balanceOf(OrderBook);
        uint256 lenderBorrowerBalance = quoteToken.balanceOf(Alice);
        borrow(Alice, FirstPoolId, DepositQT / 2);
        assertEq(quoteToken.balanceOf(OrderBook), bookBalance - DepositQT / 2);
        assertEq(quoteToken.balanceOf(Alice), lenderBorrowerBalance + DepositQT / 2);
        checkOrderQuantity(FirstOrderId, DepositQT);
        checkOrderQuantity(SecondOrderId, DepositBT);
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
