// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Setup} from "./Setup.sol";
import {MathLib, WAD} from "../lib/MathLib.sol";

contract TestRepay is Setup {

    // repay fails if non-existing buy order
    function test_RepayNonExistingBuyOrder() public {
        depositBuyOrder(Alice, 2000, 90);
        depositSellOrder(Bob, 30, 110);
        borrow(Bob, 1, 1000);
        vm.expectRevert("Position does not exist");
        repay(Bob, Carol_Position, 10);
        vm.expectRevert("Position does not exist");
        repay(Bob, Carol_Position, 0);
        checkOrderQuantity(Alice_Order, 2000);
        checkOrderQuantity(Bob_Order, 30);
        checkBorrowingQuantity(Bob_Position, 1000); 
    }

    // repay fails if non-existing sell order
    function test_RepayNonExistingSellOrder() public {
        depositSellOrder(Alice, 20, 110);
        depositBuyOrder(Bob, 3000, 90);
        borrow(Bob, Alice_Order, 10);
        vm.expectRevert("Position does not exist");
        repay(Bob, Carol_Position, 10);
        vm.expectRevert("Position does not exist");
        repay(Bob, Carol_Position, 0);
        checkOrderQuantity(1, 20);
        checkOrderQuantity(2, 3000);
        checkBorrowingQuantity(1, 10); 
    }
    
    // fails if repay buy order for zero
    function test_RepayBuyOrderFailsIfZero() public {
        depositBuyOrder(Alice, 2000, 90);
        depositSellOrder(Bob, 30, 110);
        borrow(Bob, Alice_Order, 1000);
        vm.expectRevert("Must be positive");
        repay(Bob, Bob_Position, 0);
        checkOrderQuantity(1, 2000);
        checkOrderQuantity(2, 30);
    }

    // fails if repay sell order for zero
    function test_RepaySellOrderFailsIfZero() public {
        depositSellOrder(Alice, 20, 110);
        depositBuyOrder(Bob, 3000, 90);
        borrow(Bob, Alice_Order, 10);
        vm.expectRevert("Must be positive");
        repay(Bob, Bob_Position, 0);
        checkOrderQuantity(1, 20);
        checkOrderQuantity(2, 3000);
    }

    // fails if repay buy order > borrowed amount
    function test_RepayBuyOrderFailsIfTooMuch() public {
        depositBuyOrder(Alice, 2000, 90);
        depositSellOrder(Bob, 30, 110);
        borrow(Bob, Alice_Order, 1000);
        vm.expectRevert("Repay too much");
        repay(Bob, Bob_Position, 1400);
        checkOrderQuantity(Alice_Order, 2000);
        checkOrderQuantity(Bob_Order, 30);
    }

    // fails if repay sell order > borrowed amount
    function test_RepaySellOrderFailsIfTooMuch() public {
        depositSellOrder(Alice, 20, 110);
        depositBuyOrder(Bob, 3000, 90);
        borrow(Bob, Alice_Order, 10);
        vm.expectRevert("Repay too much");
        repay(Bob, Bob_Position, 15);
        checkOrderQuantity(Alice_Order, 20);
        checkOrderQuantity(Bob_Order, 3000);
    }

    // fails if repayer is not borrower of buy order
    function test_RepayBuyOrderFailsIfNotBorrower() public {
        depositBuyOrder(Alice, 2000, 90);
        depositSellOrder(Bob, 30, 110);
        borrow(Bob, Alice_Order, 1000);
        vm.expectRevert("Only borrower can repay position");
        repay(Alice, Bob_Position, 800);
        checkOrderQuantity(Alice_Order, 2000);
        checkOrderQuantity(Bob_Order, 30);
    }

    // fails if repayer is not borrower of sell order
    function test_RepaySellOrderFailsIfNotBorrower() public {
        depositSellOrder(Alice, 20, 110);
        depositBuyOrder(Bob, 3000, 90);
        borrow(Bob, Alice_Order, 10);
        vm.expectRevert("Only borrower can repay position");
        repay(Carol, Bob_Position, 5);
        checkOrderQuantity(Alice_Order, 20);
        checkOrderQuantity(Bob_Order, 3000);
    }

    // ok if borrower then repayer of buy order is maker
    function test_RepayBuyOrderOkIfMaker() public {
        setPriceFeed(105);
        depositBuyOrder(Alice, 2000, 100);
        depositSellOrder(Alice, 30, 110);
        borrow(Alice, Alice_Order, 1000);
        checkBorrowingQuantity(1, 1000);
        repay(Alice, Alice_Position, 500);
        checkOrderQuantity(Alice_Order, 2000);
        checkOrderQuantity(Bob_Order, 30);
        checkBorrowingQuantity(Bob_Position, 500);
    }

    // ok if borrower and repayer of sell order is maker
    function test_RepaySellOrderOkIfMaker() public {
        setPriceFeed(95);
        depositSellOrder(Alice, DepositBT, 100);
        depositBuyOrder(Alice, DepositQT, 90);
        borrow(Alice, Alice_Order, DepositBT / 2);
        checkBorrowingQuantity(Alice_Position, DepositBT / 2); 
        repay(Alice, Alice_Position, DepositBT / 2);
        checkOrderQuantity(Alice_Order, DepositBT);
        checkOrderQuantity(Alice_Order + 1, DepositQT);
        checkBorrowingQuantity(Alice_Position, 0); 
    }

    // fails if borrower repay non-borrowed buy order
    function test_RepayNonBorrowedBuyOrder() public {
        depositBuyOrder(Alice, 2000, 90);
        depositSellOrder(Bob, 50, 110);
        borrow(Bob, Alice_Order, 1000);
        depositBuyOrder(Carol, 3000, 80);
        vm.expectRevert("Position does not exist");
        repay(Bob, Carol_Position, 500);
        checkOrderQuantity(Alice_Order, 2000);
        checkOrderQuantity(Bob_Order, 50);
        checkOrderQuantity(Carol_Order, 3000);
        checkBorrowingQuantity(Bob_Position, 1000); 
    }

    // fails if borrower repay non-borrowed sell order
    function test_RepayNonBorrowedSellOrder() public {
        setPriceFeed(105);
        depositSellOrder(Alice, 20, 110);
        depositBuyOrder(Bob, 5000, 100);
        borrow(Bob, Alice_Order, 10);
        depositSellOrder(Carol, 30, 120);
        vm.expectRevert("Position does not exist");
        repay(Bob, Carol_Position, 5);
        checkOrderQuantity(Alice_Order, 20);
        checkOrderQuantity(Bob_Order, 5000);
        checkOrderQuantity(Carol_Order, 30);
        checkBorrowingQuantity(Bob_Position, 10);
    }
    
    // repay buy order correctly adjusts balances
    function test_RepayBuyOrderCheckBalances() public {
        depositBuyOrder(Alice, 1800, 90);
        depositSellOrder(Bob, 30, 110);
        borrow(Bob, Alice_Order, 1600);
        uint256 bookBalance = quoteToken.balanceOf(OrderBook);
        uint256 lenderBalance = quoteToken.balanceOf(Alice);
        uint256 borrowerBalance = quoteToken.balanceOf(Bob);
        repay(Bob, Bob_Position, 1200);
        assertEq(quoteToken.balanceOf(OrderBook), bookBalance + 1200 * WAD);
        assertEq(quoteToken.balanceOf(Alice), lenderBalance);
        assertEq(quoteToken.balanceOf(Bob), borrowerBalance - 1200 * WAD);
        checkOrderQuantity(Alice_Order, 1800);
        checkOrderQuantity(Bob_Order, 30);
        checkBorrowingQuantity(Bob_Position, 400);
    }

    // repay sell order correctly adjusts external balances
    function test_RepaySellOrderCheckBalances() public {
        depositSellOrder(Alice, 20, 110);
        depositBuyOrder(Bob, 3000, 90);
        borrow(Bob, Alice_Order, 10);
        uint256 bookBalance = baseToken.balanceOf(OrderBook);
        uint256 lenderBalance = baseToken.balanceOf(Alice);
        uint256 borrowerBalance = baseToken.balanceOf(Bob);
        repay(Bob, Bob_Position, 8);
        assertEq(baseToken.balanceOf(OrderBook), bookBalance + 8 * WAD);
        assertEq(baseToken.balanceOf(Alice), lenderBalance);
        assertEq(baseToken.balanceOf(Bob), borrowerBalance - 8 * WAD);
        checkOrderQuantity(Alice_Order, 20);
        checkOrderQuantity(Bob_Order, 3000);
        checkBorrowingQuantity(Bob_Position, 2);
    }

    // Lender and borrower excess collaterals in quote and base tokens are correct
    function test_RepayBuyOrderExcessCollateral() public {
        depositBuyOrder(Alice, 2000, 90);
        depositSellOrder(Bob, 30, 110);
        borrow(Bob, Alice_Order, 900);
        uint256 lenderExcessCollateral = book._getExcessCollateral(Alice, InQuoteToken);
        uint256 borrowerExcessCollateral = book._getExcessCollateral(Bob, InBaseToken);
        repay(Bob, Bob_Position, 450);
        assertEq(book._getExcessCollateral(Alice, InQuoteToken), lenderExcessCollateral + 450 * WAD);
        assertEq(book._getExcessCollateral(Bob, InBaseToken), borrowerExcessCollateral + 5 * WAD);
        checkOrderQuantity(Alice_Order, 2000);
        checkOrderQuantity(Bob_Order, 30);
    }

    // Lender and borrower excess collaterals in base and quote tokens are correct
    function test_RepaySellOrderExcessCollateral() public {
        depositSellOrder(Alice, 20, 110);
        depositBuyOrder(Bob, 3000, 90);
        borrow(Bob, Alice_Order, 10);
        uint256 lenderExcessCollateral = book._getExcessCollateral(Alice, InBaseToken);
        uint256 borrowerExcessCollateral = book._getExcessCollateral(Bob, InQuoteToken);
        repay(Bob, Bob_Position, 7);
        assertEq(book._getExcessCollateral(Alice, InBaseToken), lenderExcessCollateral + 7 * WAD);
        assertEq(book._getExcessCollateral(Bob, InQuoteToken), borrowerExcessCollateral + 770 * WAD);
        checkOrderQuantity(Alice_Order, 20);
        checkOrderQuantity(Bob_Order, 3000);
    }

    function test_BorrowRepayFromIdInUsers() public {
        depositSellOrder(Alice, 20, 110);
        depositBuyOrder(Bob, 3000, 90);
        borrow(Bob, Alice_Order, 10);
        repay(Bob, Bob_Position, 10);
        checkUserBorrowId(Bob, 0, 1);
        borrow(Bob, Alice_Order, 10);
        checkUserBorrowId(Bob, 0, 1);
        checkUserBorrowId(Bob, 1, 0);
    }

}
