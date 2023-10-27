// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Setup} from "./Setup.sol";
import {StdCheats} from "forge-std/StdCheats.sol";

contract TestBorrow is Setup {

    // borrow fails if non-existing buy order
    function testFailBorrowNonExistingBuyOrder() public {
        depositBuyOrder(acc[1], 2000, 90);
        depositSellOrder(acc[2], 30, 110);
        vm.prank(acc[2]);
        book.borrow(3, 0);
        vm.expectRevert("Order has zero assets");
    }

    // borrow fails if non-existing sell order
    function testFailBorrowNonExistingSellOrder() public {
        depositSellOrder(acc[1], 20, 110);
        depositSellOrder(acc[2], 3000, 90);
        vm.prank(acc[2]);
        book.borrow(3, 0);
        vm.expectRevert("Order has zero assets");
    }
    
    // fails if borrowing of buy order is zero
    function testBorrowBuyOrderFailsIfZero() public {
        depositBuyOrder(acc[1], 2000, 90);
        depositSellOrder(acc[2], 30, 110);
        vm.expectRevert("Must be positive");
        vm.prank(acc[2]);
        book.borrow(1, 0);
    }

    // fails if borrowing of sell order is zero
    function testBorrowSellOrderFailsIfZero() public {
        depositSellOrder(acc[1], 20, 110);
        depositBuyOrder(acc[2], 3000, 90);
        vm.expectRevert("Must be positive");
        vm.prank(acc[2]);
        book.borrow(1, 0);
    }

    // ok if borrower of buy order is maker
    function testBorrowBuyOrderOkIfMaker() public {
        depositBuyOrder(acc[1], 2000, 90);
        depositSellOrder(acc[1], 30, 110);
        vm.prank(acc[1]);
        book.borrow(1, 2000);
    }

    // ok if borrower of sell order is maker
    function testBorrowSellOrderOkIfMaker() public {
        depositSellOrder(acc[1], 20, 110);
        depositBuyOrder(acc[1], 3000, 90);
        vm.prank(acc[1]);
        book.borrow(1, 20);
    }
    
    // borrow of buy order correctly adjusts external balances
    function testBorrowBuyOrderCheckBalances() public {
        depositBuyOrder(acc[1], 1800, 90);
        depositSellOrder(acc[2], 30, 110);
        uint256 bookBalance = quoteToken.balanceOf(address(book));
        uint256 lenderBalance = quoteToken.balanceOf(acc[1]);
        uint256 borrowerBalance = quoteToken.balanceOf(acc[2]);
        vm.prank(acc[2]);
        book.borrow(1, 1800);
        assertEq(quoteToken.balanceOf(address(book)), bookBalance - 1800);
        assertEq(quoteToken.balanceOf(acc[1]), lenderBalance);
        assertEq(quoteToken.balanceOf(acc[2]), borrowerBalance + 1800);
    }

    // borrow of sell order correctly adjusts external balances
    function testBorowSellOrderCheckBalances() public {
        depositSellOrder(acc[1], 20, 110);
        depositBuyOrder(acc[2], 3000, 90);
        uint256 bookBalance = baseToken.balanceOf(address(book));
        uint256 lenderBalance = baseToken.balanceOf(acc[1]);
        uint256 borrowerBalance = baseToken.balanceOf(acc[2]);
        vm.prank(acc[2]);
        book.borrow(1, 20);
        assertEq(baseToken.balanceOf(address(book)), bookBalance - 20);
        assertEq(baseToken.balanceOf(acc[1]), lenderBalance);
        assertEq(baseToken.balanceOf(acc[2]), borrowerBalance + 20);
    }

    // borrowable quantity from buy order is correct
    function testBorrowBuyOrderOutable() public {
        depositBuyOrder(acc[1], 2000, 90);
        depositSellOrder(acc[2], 30, 110);
        assertEq(book.outableQuantity(1, 2000), 2000);
        assertEq(book.outableQuantity(1, 1900), 1900);
        assertEq(book.outableQuantity(1, 1901), 1900);
        vm.prank(acc[2]);
        book.borrow(1, 1000);
        assertEq(book.outableQuantity(1, 1000), 1000);
    }

    // borrowable quantity from sell order is correct
    function testBorrowSellOrderOutable() public {
        depositSellOrder(acc[1], 20, 110);
        depositBuyOrder(acc[2], 3000, 90);
        assertEq(book.outableQuantity(1, 20), 20);
        vm.prank(acc[2]);
        book.borrow(1, 10);
        assertEq(book.outableQuantity(1, 10), 10);
    }

    // Lender and borrower excess collaterals in quote and base token are correct
    function testBorrowBuyOrderExcessCollateral() public {
        depositBuyOrder(acc[1], 2000, 90);
        depositSellOrder(acc[2], 30, 110);
        uint256 lenderExcessCollateral = book.getUserExcessCollateral(acc[1], inQuoteToken);
        uint256 borrowerExcessCollateral = book.getUserExcessCollateral(acc[2], inBaseToken);
        vm.prank(acc[2]);
        book.borrow(1, 900);
        assertEq(book.getUserExcessCollateral(acc[1], inQuoteToken), lenderExcessCollateral - 900);
        assertEq(book.getUserExcessCollateral(acc[2], inBaseToken), borrowerExcessCollateral - 900/90);
    }

    // Lender and borrower excess collaterals in base and quote token are correct
    function testBorrowSellOrderExcessCollateral() public {
        depositSellOrder(acc[1], 20, 110);
        depositBuyOrder(acc[2], 3000, 90);
        uint256 lenderExcessCollateral = book.getUserExcessCollateral(acc[1], inBaseToken);
        uint256 borrowerExcessCollateral = book.getUserExcessCollateral(acc[2], inQuoteToken);
        vm.prank(acc[2]);
        book.borrow(1, 10);
        assertEq(book.getUserExcessCollateral(acc[1], inBaseToken), lenderExcessCollateral - 10);
        assertEq(book.getUserExcessCollateral(acc[2], inQuoteToken), borrowerExcessCollateral - 10*110);
    }
}
