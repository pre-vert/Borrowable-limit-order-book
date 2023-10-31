// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Setup} from "./Setup.sol";
import {StdCheats} from "forge-std/StdCheats.sol";

contract TestRepay is Setup {

    // repay fails if non-existing buy order
    function test_RepayNonExistingBuyOrder() public {
        depositBuyOrder(acc[1], 2000, 90);
        depositSellOrder(acc[2], 30, 110);
        borrow(acc[2], 1, 1000);
        vm.expectRevert("Order has zero assets");
        repay(acc[2], 3, 10);
        vm.expectRevert("Order has zero assets");
        repay(acc[2], 3, 0);
        checkOrderQuantity(1, 2000);
        checkOrderQuantity(2, 30);
        checkBorrowingQuantity(1, 1000); 
    }

    // repay fails if non-existing sell order
    function test_RepayNonExistingSellOrder() public {
        depositSellOrder(acc[1], 20, 110);
        depositBuyOrder(acc[2], 3000, 90);
        borrow(acc[2], 1, 10);
        vm.expectRevert("Order has zero assets");
        repay(acc[2], 3, 10);
        vm.expectRevert("Order has zero assets");
        repay(acc[2], 3, 0);
        checkOrderQuantity(1, 20);
        checkOrderQuantity(2, 3000);
        checkBorrowingQuantity(1, 10); 
    }
    
    // fails if repay buy order for zero
    function test_RepayBuyOrderFailsIfZero() public {
        depositBuyOrder(acc[1], 2000, 90);
        depositSellOrder(acc[2], 30, 110);
        borrow(acc[2], 1, 1000);
        vm.expectRevert("Must be positive");
        repay(acc[2], 1, 0);
        checkOrderQuantity(1, 2000);
        checkOrderQuantity(2, 30);
    }

    // fails if repay sell order for zero
    function test_RepaySellOrderFailsIfZero() public {
        depositSellOrder(acc[1], 20, 110);
        depositBuyOrder(acc[2], 3000, 90);
        borrow(acc[2], 1, 10);
        vm.expectRevert("Must be positive");
        repay(acc[2], 1, 0);
        checkOrderQuantity(1, 20);
        checkOrderQuantity(2, 3000);
    }

    // fails if repay buy order > borrowed amount
    function test_RepayBuyOrderFailsIfTooMuch() public {
        depositBuyOrder(acc[1], 2000, 90);
        depositSellOrder(acc[2], 30, 110);
        borrow(acc[2], 1, 1000);
        vm.expectRevert("Quantity exceeds limit");
        repay(acc[2], 1, 1400);
        checkOrderQuantity(1, 2000);
        checkOrderQuantity(2, 30);
    }

    // fails if repay sell order > borrowed amount
    function test_RepaySellOrderFailsIfTooMuch() public {
        depositSellOrder(acc[1], 20, 110);
        depositBuyOrder(acc[2], 3000, 90);
        borrow(acc[2], 1, 10);
        vm.expectRevert("Quantity exceeds limit");
        repay(acc[2], 1, 15);
        checkOrderQuantity(1, 20);
        checkOrderQuantity(2, 3000);
    }

    // ok if borrower then repayer of buy order is maker
    function test_RepayBuyOrderOkIfMaker() public {
        depositBuyOrder(acc[1], 2000, 100);
        depositSellOrder(acc[1], 30, 110);
        borrow(acc[1], 1, 1000);
        checkBorrowingQuantity(1, 1000);
        repay(acc[1], 1, 500);
        checkOrderQuantity(1, 2000);
        checkOrderQuantity(2, 30);
        checkBorrowingQuantity(1, 500);
    }

    // ok if borrower then repayer of sell order is maker
    function test_RepaySellOrderOkIfMaker() public {
        depositSellOrder(acc[1], 20, 100);
        depositBuyOrder(acc[1], 3000, 90);
        borrow(acc[1], 1, 20);
        checkBorrowingQuantity(1, 20); 
        repay(acc[1], 1, 10);
        checkOrderQuantity(1, 20);
        checkOrderQuantity(2, 3000);
        checkBorrowingQuantity(1, 10); 
    }

    // fails if borrower repay non-borrowed buy order
    function test_RepayNonBorrowedBuyOrder() public {
        depositBuyOrder(acc[1], 2000, 90);
        depositSellOrder(acc[2], 50, 110);
        borrow(acc[2], 1, 1000);
        depositBuyOrder(acc[3], 3000, 80);
        vm.expectRevert("Must be positive");
        repay(acc[2], 3, 500);
        checkOrderQuantity(1, 2000);
        checkOrderQuantity(2, 50);
        checkOrderQuantity(3, 3000);
        checkBorrowingQuantity(1, 1000); 
    }

    // fails if borrower repay non-borrowed sell order
    function test_RepayNonBorrowedSellOrder() public {
        depositSellOrder(acc[1], 20, 110);
        depositBuyOrder(acc[2], 5000, 100);
        borrow(acc[2], 1, 10);
        depositSellOrder(acc[3], 30, 120);
        vm.expectRevert("Must be positive");
        repay(acc[2], 3, 5);
        checkOrderQuantity(1, 20);
        checkOrderQuantity(2, 5000);
        checkOrderQuantity(3, 30);
        checkBorrowingQuantity(1, 10);
    }
    
    // repay buy order correctly adjusts balances
    function test_RepayBuyOrderCheckBalances() public {
        depositBuyOrder(acc[1], 1800, 90);
        depositSellOrder(acc[2], 30, 110);
        borrow(acc[2], 1, 1600);
        uint256 bookBalance = quoteToken.balanceOf(address(book));
        uint256 lenderBalance = quoteToken.balanceOf(acc[1]);
        uint256 borrowerBalance = quoteToken.balanceOf(acc[2]);
        repay(acc[2], 1, 1200);
        assertEq(quoteToken.balanceOf(address(book)), bookBalance + 1200);
        assertEq(quoteToken.balanceOf(acc[1]), lenderBalance);
        assertEq(quoteToken.balanceOf(acc[2]), borrowerBalance - 1200);
        checkOrderQuantity(1, 1800);
        checkOrderQuantity(2, 30);
        checkBorrowingQuantity(1, 400);
    }

    // repay sell order correctly adjusts external balances
    function test_BorowSellOrderCheckBalances() public {
        depositSellOrder(acc[1], 20, 110);
        depositBuyOrder(acc[2], 3000, 90);
        borrow(acc[2], 1, 10);
        uint256 bookBalance = baseToken.balanceOf(address(book));
        uint256 lenderBalance = baseToken.balanceOf(acc[1]);
        uint256 borrowerBalance = baseToken.balanceOf(acc[2]);
        repay(acc[2], 1, 8);
        assertEq(baseToken.balanceOf(address(book)), bookBalance + 8);
        assertEq(baseToken.balanceOf(acc[1]), lenderBalance);
        assertEq(baseToken.balanceOf(acc[2]), borrowerBalance - 8);
        checkOrderQuantity(1, 20);
        checkOrderQuantity(2, 3000);
        checkBorrowingQuantity(1, 2);
    }

    // Lender and borrower excess collaterals in quote and base tokens are correct
    function test_RepayBuyOrderExcessCollateral() public {
        depositBuyOrder(acc[1], 2000, 90);
        depositSellOrder(acc[2], 30, 110);
        borrow(acc[2], 1, 900);
        uint256 lenderExcessCollateral = book.getUserExcessCollateral(acc[1], inQuoteToken);
        uint256 borrowerExcessCollateral = book.getUserExcessCollateral(acc[2], inBaseToken);
        repay(acc[2], 1, 450);
        assertEq(book.getUserExcessCollateral(acc[1], inQuoteToken), lenderExcessCollateral + 450);
        assertEq(book.getUserExcessCollateral(acc[2], inBaseToken), borrowerExcessCollateral + 450/90);
        checkOrderQuantity(1, 2000);
        checkOrderQuantity(2, 30);
    }

    // Lender and borrower excess collaterals in base and quote tokens are correct
    function test_RepaySellOrderExcessCollateral() public {
        depositSellOrder(acc[1], 20, 110);
        depositBuyOrder(acc[2], 3000, 90);
        borrow(acc[2], 1, 10);
        uint256 lenderExcessCollateral = book.getUserExcessCollateral(acc[1], inBaseToken);
        uint256 borrowerExcessCollateral = book.getUserExcessCollateral(acc[2], inQuoteToken);
        repay(acc[2], 1, 7);
        assertEq(book.getUserExcessCollateral(acc[1], inBaseToken), lenderExcessCollateral + 7);
        assertEq(book.getUserExcessCollateral(acc[2], inQuoteToken), borrowerExcessCollateral + 7*110);
        checkOrderQuantity(1, 20);
        checkOrderQuantity(2, 3000);
    }

    function test_BorrowRepayFromIdInUsers() public {
        depositSellOrder(acc[1], 20, 110);
        depositBuyOrder(acc[2], 3000, 90);
        borrow(acc[2], 1, 10);
        repay(acc[2], 1, 10);
        checkUserBorrowId(acc[2], 0, 1);
        borrow(acc[2], 1, 10);
        checkUserBorrowId(acc[2], 0, 1);
        checkUserBorrowId(acc[2], 1, 0);
    }

}
