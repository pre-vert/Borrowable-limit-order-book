// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Setup} from "./Setup.sol";
import {MathLib, WAD} from "../lib/MathLib.sol";

contract TestRepay is Setup {

    function test_BorrowRepayFromIdInUsers() public depositBuy(B) depositSell(B + 3) {
        borrow(Bob, B, DepositQT / 2);
        repay(Bob, FirstPositionId, DepositQT / 2);
        checkUserBorrowId(Bob, FirstRow, FirstPositionId);
    }
    
    // reverts if non-existing position
    function test_RepayNonExistingPosition() public depositBuy(B) depositSell(B + 3) {
        borrow(Bob, B, DepositQT / 2);
        vm.expectRevert("Not borrowing");
        repay(Bob, SecondPositionId, DepositQT / 2);
    }

    // reverts if repay with zero assets
    function test_RepayWithZeroAssets() public depositBuy(B) depositSell(B + 3) {
        borrow(Bob, B,  DepositQT / 2);
        vm.expectRevert("Repay zero");
        repay(Bob, FirstPositionId, 0);
    }

    // repay fails if wrong pool id
    function test_RepayNonExistingSellOrder() public depositBuy(B) depositSell(B + 3) {
        borrow(Bob, B, DepositQT / 2);
        vm.expectRevert("Not borrowing");
        repay(Bob, SecondPositionId, DepositQT / 2);
    }

    // fails if repay buy order > borrowed amount
    function test_RepayBuyOrderFailsIfTooMuch() public depositBuy(B) depositSell(B + 3) {
        borrow(Bob, B, DepositQT / 2);
        vm.expectRevert("Repay too much");
        repay(Bob, FirstPositionId, DepositQT);
    }

    // fails if repayer is not borrower of buy order
    function test_RepayBuyOrderFailsIfNotBorrower() public depositBuy(B) depositSell(B + 3) {
        borrow(Bob, B,  DepositQT / 2);
        vm.expectRevert("Not Borrower");
        repay(Carol, FirstPositionId, DepositQT / 2);
        checkBorrowingQuantity(FirstPositionId, DepositQT / 2);
    }

    // ok if borrower/repayer is maker
    // market price set initially at 2001
    // deposit buy order at initial price = 2000 = limit price pool(0) < market price
    // deposit sell order price at 2200 = limit price pool(1) > market price 

    function test_RepayBuyOrderOkIfMaker() public {
        depositBuyOrder(Alice, B, DepositQT, B + 3);
        depositSellOrder(Alice, B + 3, DepositBT, B);
        borrow(Alice, B, DepositQT / 2);
        repay(Alice, FirstPositionId, DepositQT / 2);
        checkBorrowingQuantity(FirstPositionId, 0); 
    }
    
    // repay correctly adjusts balances
    function test_RepayBuyOrderCheckBalances() public depositBuy(B) depositSell(B + 3) {
        borrow(Bob, B, DepositQT / 2);
        uint256 bookBalance = quoteToken.balanceOf(OrderBook);
        uint256 lenderBalance = quoteToken.balanceOf(Alice);
        uint256 borrowerBalance = quoteToken.balanceOf(Bob);
        repay(Bob, FirstPositionId,  DepositQT / 2);
        assertEq(quoteToken.balanceOf(OrderBook), bookBalance + DepositQT / 2);
        assertEq(quoteToken.balanceOf(Alice), lenderBalance);
        assertEq(quoteToken.balanceOf(Bob), borrowerBalance - DepositQT / 2);
        checkBorrowingQuantity(FirstPositionId, 0); 
    }

    // Borrower excess collateral in base token is correct
    // Alice deposits buy order of 20,000 at limit price 2000 => EC = ALTV * 20,000 / 2000 = 9.8
    // Bob deposits sell order of 10 at limit price 2200 => EC = ALTV * 10 = 9.8
    // borrows 20,000/2 at limit price 2000 => EC = EC - 20,000 / (2*2000) = 9.8 - 5 = 4.8
    // repays 20,000/2 at limit price 2000 => EC = EC + 20,000 / (2*2000) = 4.8 + 5 = 9.8

    function test_RepayBuyOrderExcessCollateral() public depositBuy(B) depositSell(B + 3) {
        borrow(Bob, B, DepositQT / 2);
        uint256 excessCollateral = book.getUserExcessCollateral(Bob, 0);
        uint256 limitPrice = book.limitPrice(B);
        repay(Bob, FirstPositionId,  DepositQT / 2);
        uint256 newExcessCollateral = excessCollateral + WAD * DepositQT / (2 * limitPrice);
        assertEq(book.getUserExcessCollateral(Bob, 0), newExcessCollateral);
    }

}
