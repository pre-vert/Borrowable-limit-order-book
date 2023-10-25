// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Setup} from "./Setup.sol";
import {StdCheats} from "forge-std/StdCheats.sol";

contract TestRepay is Setup {

    // repay fails if non-existing buy order
    function testFailRepayNonExistingBuyOrder() public {
        depositBuyOrder(USER1, 2000, 90);
        depositSellOrder(USER2, 30, 110);
        vm.startPrank(USER2);
        book.borrow(1, 0);
        book.repay(3, 0);
        vm.expectRevert("Order has zero assets");
    }

    // repay fails if non-existing sell order
    function testFailRepayNonExistingSellOrder() public {
        depositSellOrder(USER1, 20, 110);
        depositSellOrder(USER2, 3000, 90);
        vm.startPrank(USER2);
        book.borrow(3, 0);
        book.repay(3, 0);
        vm.expectRevert("Order has zero assets");
    }
    
    // fails if repay buy order for zero
    function testRepayBuyOrderFailsIfZero() public {
        depositBuyOrder(USER1, 2000, 90);
        depositSellOrder(USER2, 30, 110);
        vm.startPrank(USER2);
        book.borrow(1, 1000);
        vm.expectRevert("Must be positive");
        book.repay(1, 0);
    }

    // fails if repay sell order for zero
    function testRepaySellOrderFailsIfZero() public {
        depositSellOrder(USER1, 20, 110);
        depositBuyOrder(USER2, 3000, 90);
        vm.prank(USER2);
        book.borrow(1, 10);
        vm.expectRevert("Must be positive");
        book.repay(1, 5);
    }

    // fails if repay buy order > borrowed amount
    function testRepayBuyOrderFailsIfTooMuch() public {
        depositBuyOrder(USER1, 2000, 90);
        depositSellOrder(USER2, 30, 110);
        vm.startPrank(USER2);
        book.borrow(1, 1000);
        vm.expectRevert("Quantity exceeds limit");
        book.repay(1, 1400);
    }

    // fails if repay sell order > borrowed amount
    function testRepaySellOrderFailsIfTooMuch() public {
        depositSellOrder(USER1, 20, 110);
        depositBuyOrder(USER2, 3000, 90);
        vm.startPrank(USER2);
        book.borrow(1, 10);
        vm.expectRevert("Quantity exceeds limit");
        book.repay(1, 15);
    }

    // ok if borrower then repayer of buy order is maker
    function testRepayBuyOrderOkIfMaker() public {
        depositBuyOrder(USER1, 2000, 90);
        depositSellOrder(USER1, 30, 110);
        vm.startPrank(USER1);
        book.borrow(1, 1000);
        book.repay(1, 500);
    }

    // ok if borrower then repayer of sell order is maker
    function testRepaySellOrderOkIfMaker() public {
        depositSellOrder(USER1, 20, 110);
        depositBuyOrder(USER1, 3000, 90);
        vm.startPrank(USER1);
        book.borrow(1, 20);
        book.repay(1, 10);
    }

    // fails if borrower repay non-borrowed buy order
    function testFailsRepayNonBorrowedBuyOrder() public {
        depositBuyOrder(USER1, 2000, 90);
        depositBuyOrder(USER1, 3000, 80);
        depositSellOrder(USER2, 50, 110);
        vm.startPrank(USER2);
        book.borrow(1, 1000);
        book.repay(2, 500);
        vm.expectRevert("Must be positive");
    }

    // fails if borrower repay non-borrowed sell order
    function testFailsRepayNonBorrowedSellOrder() public {
        depositSellOrder(USER1, 20, 110);
        depositSellOrder(USER1, 30, 120);
        depositBuyOrder(USER2, 5000, 100);
        vm.startPrank(USER2);
        book.borrow(1, 10);
        book.repay(2, 5);
        vm.expectRevert("Must be positive");
    }
    
    // repay buy order correctly adjusts external balances
    function testRepayBuyOrderCheckBalances() public {
        depositBuyOrder(USER1, 1800, 90);
        depositSellOrder(USER2, 30, 110);
        vm.prank(USER2);
        book.borrow(1, 1600);
        uint256 bookBalance = quoteToken.balanceOf(address(book));
        uint256 lenderBalance = quoteToken.balanceOf(USER1);
        uint256 borrowerBalance = quoteToken.balanceOf(USER2);
        vm.prank(USER2);
        book.repay(1, 1200);
        assertEq(quoteToken.balanceOf(address(book)), bookBalance + 1200);
        assertEq(quoteToken.balanceOf(USER1), lenderBalance);
        assertEq(quoteToken.balanceOf(USER2), borrowerBalance - 1200);
    }

    // repay sell order correctly adjusts external balances
    function testBorowSellOrderCheckBalances() public {
        depositSellOrder(USER1, 20, 110);
        depositBuyOrder(USER2, 3000, 90);
        vm.prank(USER2);
        book.borrow(1, 10);
        uint256 bookBalance = baseToken.balanceOf(address(book));
        uint256 lenderBalance = baseToken.balanceOf(USER1);
        uint256 borrowerBalance = baseToken.balanceOf(USER2);
        vm.prank(USER2);
        book.repay(1, 8);
        assertEq(baseToken.balanceOf(address(book)), bookBalance + 8);
        assertEq(baseToken.balanceOf(USER1), lenderBalance);
        assertEq(baseToken.balanceOf(USER2), borrowerBalance - 8);
    }

    // Lender and borrower excess collaterals in quote and base tokens are correct
    function testRepayBuyOrderExcessCollateral() public {
        depositBuyOrder(USER1, 2000, 90);
        depositSellOrder(USER2, 30, 110);
        vm.prank(USER2);
        book.borrow(1, 900);
        uint256 lenderExcessCollateral = book.getUserExcessCollateral(USER1, inQuoteToken);
        uint256 borrowerExcessCollateral = book.getUserExcessCollateral(USER2, inBaseToken);
        vm.prank(USER2);
        book.repay(1, 450);
        assertEq(book.getUserExcessCollateral(USER1, inQuoteToken), lenderExcessCollateral + 450);
        assertEq(book.getUserExcessCollateral(USER2, inBaseToken), borrowerExcessCollateral + 450/90);
    }

    // Lender and borrower excess collaterals in base and quote tokens are correct
    function testRepaySellOrderExcessCollateral() public {
        depositSellOrder(USER1, 20, 110);
        depositBuyOrder(USER2, 3000, 90);
        vm.prank(USER2);
        book.borrow(1, 10);
        uint256 lenderExcessCollateral = book.getUserExcessCollateral(USER1, inBaseToken);
        uint256 borrowerExcessCollateral = book.getUserExcessCollateral(USER2, inQuoteToken);
        vm.prank(USER2);
        book.repay(1, 7);
        assertEq(book.getUserExcessCollateral(USER1, inBaseToken), lenderExcessCollateral + 7);
        assertEq(book.getUserExcessCollateral(USER2, inQuoteToken), borrowerExcessCollateral + 7*110);
    }
}
