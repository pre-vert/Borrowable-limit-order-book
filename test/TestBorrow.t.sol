// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Setup} from "./Setup.sol";
import {StdCheats} from "forge-std/StdCheats.sol";

contract TestBorrow is Setup {
    
    // borrow fails if non-existing buy order
    function test_BorrowNonExistingBuyOrder() public {
        depositBuyOrder(acc[1], 2000, 90);
        vm.expectRevert("Order has zero assets");
        borrow(acc[1], 2, 10);
        checkOrderQuantity(1, 2000);
    }

    // borrow fails if non-existing sell order
    function test_BorrowNonExistingSellOrder() public {
        depositSellOrder(acc[1], 20, 110);
        vm.expectRevert("Order has zero assets");
        borrow(acc[1], 2, 1000);
        checkOrderQuantity(1, 20);
    }
    
    // fails if borrowing of buy order is zero
    function test_BorrowBuyOrderFailsIfZero() public {
        depositBuyOrder(acc[1], 2000, 90);
        depositSellOrder(acc[2], 30, 110);
        vm.expectRevert("Must be positive");
        borrow(acc[2], 1, 0);
        checkOrderQuantity(1, 2000);
    }

    // fails if borrowing of sell order is zero
    function test_BorrowSellOrderFailsIfZero() public {
        depositSellOrder(acc[1], 20, 110);
        depositBuyOrder(acc[2], 3000, 90);
        vm.expectRevert("Must be positive");
        borrow(acc[2], 1, 0);
        checkOrderQuantity(1, 20);
    }

    // ok if borrower of buy order is maker
    function test_BorrowBuyOrderOkIfMaker() public {
        depositBuyOrder(acc[1], 2000, 90);
        depositSellOrder(acc[1], 30, 110);
        borrow(acc[1], 1, 2000);
        checkOrderQuantity(1, 2000);
        checkBorrowingQuantity(1, 2000); 
    }

    // ok if borrower of sell order is maker
    function test_BorrowSellOrderOkIfMaker() public {
        depositSellOrder(acc[1], 20, 110);
        depositBuyOrder(acc[1], 3000, 90);
        borrow(acc[1], 1, 20);
        checkOrderQuantity(1, 20);
        checkBorrowingQuantity(1, 20); 
    }
    
    // borrow of buy order correctly adjusts balances
    function test_BorrowBuyOrderCheckBalances() public {
        depositBuyOrder(acc[1], 1800, 90);
        depositSellOrder(acc[2], 30, 110);
        uint256 bookBalance = quoteToken.balanceOf(address(book));
        uint256 lenderBalance = quoteToken.balanceOf(acc[1]);
        uint256 borrowerBalance = quoteToken.balanceOf(acc[2]);
        borrow(acc[2], 1, 1800);
        assertEq(quoteToken.balanceOf(address(book)), bookBalance - 1800);
        assertEq(quoteToken.balanceOf(acc[1]), lenderBalance);
        assertEq(quoteToken.balanceOf(acc[2]), borrowerBalance + 1800);
        checkOrderQuantity(1, 1800);
        checkOrderQuantity(2, 30);
        checkBorrowingQuantity(1, 1800); 
    }

    // borrow of sell order correctly adjusts external balances
    function test_BorowSellOrderCheckBalances() public {
        depositSellOrder(acc[1], 20, 110);
        depositBuyOrder(acc[2], 3000, 90);
        uint256 bookBalance = baseToken.balanceOf(address(book));
        uint256 lenderBalance = baseToken.balanceOf(acc[1]);
        uint256 borrowerBalance = baseToken.balanceOf(acc[2]);
        borrow(acc[2], 1, 20);
        assertEq(baseToken.balanceOf(address(book)), bookBalance - 20);
        assertEq(baseToken.balanceOf(acc[1]), lenderBalance);
        assertEq(baseToken.balanceOf(acc[2]), borrowerBalance + 20);
        checkOrderQuantity(1, 20);
        checkOrderQuantity(2, 3000);
        checkBorrowingQuantity(1, 20); 
    }

    // borrowable quantity from buy order is correct
    function test_BorrowBuyOrderOutable() public {
        depositBuyOrder(acc[1], 2000, 90);
        depositSellOrder(acc[2], 30, 110);
        assertEq(book.outableQuantity(1, 2000), 2000);
        assertEq(book.outableQuantity(1, 1900), 1900);
        assertEq(book.outableQuantity(1, 1901), 0);
        borrow(acc[2], 1, 1000);
        assertEq(book.outableQuantity(1, 1000), 1000);
    }

    // borrowable quantity from sell order is correct
    function test_BorrowSellOrderOutable() public {
        depositSellOrder(acc[1], 20, 110);
        depositBuyOrder(acc[2], 3000, 90);
        assertEq(book.outableQuantity(1, 20), 20);
        assertEq(book.outableQuantity(1, 19), 0);
        assertEq(book.outableQuantity(1, 18), 18);
        borrow(acc[2], 1, 10);
        assertEq(book.outableQuantity(1, 10), 10);
        assertEq(book.outableQuantity(1, 9), 0);
        assertEq(book.outableQuantity(1, 8), 8);
    }

    // Lender and borrower excess collaterals in quote and base token are correct
    function test_BorrowBuyOrderExcessCollateral() public {
        depositBuyOrder(acc[1], 2000, 90);
        depositSellOrder(acc[2], 30, 110);
        uint256 lenderExcessCollateral = book.getUserExcessCollateral(acc[1], inQuoteToken);
        uint256 borrowerExcessCollateral = book.getUserExcessCollateral(acc[2], inBaseToken);
        borrow(acc[2], 1, 900);
        assertEq(book.getUserExcessCollateral(acc[1], inQuoteToken), lenderExcessCollateral - 900);
        assertEq(book.getUserExcessCollateral(acc[2], inBaseToken), borrowerExcessCollateral - 900/90);
    }

    // Lender and borrower excess collaterals in base and quote token are correct
    function test_BorrowSellOrderExcessCollateral() public {
        depositSellOrder(acc[1], 20, 110);
        depositBuyOrder(acc[2], 3000, 90);
        uint256 lenderExcessCollateral = book.getUserExcessCollateral(acc[1], inBaseToken);
        uint256 borrowerExcessCollateral = book.getUserExcessCollateral(acc[2], inQuoteToken);
        borrow(acc[2], 1, 10);
        assertEq(book.getUserExcessCollateral(acc[1], inBaseToken), lenderExcessCollateral - 10);
        assertEq(book.getUserExcessCollateral(acc[2], inQuoteToken), borrowerExcessCollateral - 10*110);
    }

    function test_BorrowFromIdInUsers() public {
        depositSellOrder(acc[1], 20, 110);
        depositBuyOrder(acc[2], 3000, 90);
        checkUserBorrowId(acc[2], 0, 0);
        borrow(acc[2], 1, 10);
        checkUserBorrowId(acc[2], 0, 1);
        checkUserBorrowId(acc[2], 1, 0);
    }

    function test_BorrowTwiceFromSameOrder() public {
        depositSellOrder(acc[1], 30, 110);
        depositBuyOrder(acc[2], 5000, 90);
        borrow(acc[2], 1, 10);
        borrow(acc[2], 1, 5);
        checkBorrowingQuantity(1, 15);
        checkUserBorrowId(acc[2], 0, 1);
        checkUserBorrowId(acc[2], 1, 0);
    }

    function test_BorrowTwiceFromTwoOrders() public {
        depositSellOrder(acc[1], 30, 110);
        depositSellOrder(acc[2], 20, 100);
        depositBuyOrder(acc[3], 6000, 90);
        checkUserBorrowId(acc[3], 0, 0);
        borrow(acc[3], 1, 15);
        checkUserBorrowId(acc[3], 0, 1);
        borrow(acc[3], 2, 10);
        checkBorrowingQuantity(1, 15);
        checkBorrowingQuantity(2, 10);
        checkUserBorrowId(acc[3], 0, 1);
        checkUserBorrowId(acc[3], 1, 2);
    }

    // tests what happens if a user has more than the max number of positions
    function test_PositionsForUserExceedLimit() public {
        depositSellOrder(acc[1], 30, 110);
        depositSellOrder(acc[2], 20, 100);
        depositSellOrder(acc[3], 40, 120);
        depositBuyOrder(acc[3], 10000, 90);
        borrow(acc[3], 1, 15);
        borrow(acc[3], 2, 10);
        checkUserBorrowId(acc[3], 0, 1);
        checkUserBorrowId(acc[3], 1, 2);
        vm.expectRevert("Max number of positions reached for borrower");
        borrow(acc[3], 3, 5);
        checkBorrowingQuantity(3, 0);
    }

    // tests what happens if an order has more than the max number of positions
    function test_PositionsForOrderExceedLimit() public {
        depositBuyOrder(acc[1], 6000, 90);
        depositSellOrder(acc[2], 20, 100);
        depositSellOrder(acc[3], 40, 120);
        depositSellOrder(acc[4], 10, 110);
        borrow(acc[2], 1, 5);
        borrow(acc[3], 1, 10);
        checkOrderPositionId(1, 0, 1);
        checkOrderPositionId(1, 1, 2);
        vm.expectRevert("Max number of positions reached for order");
        borrow(acc[4], 1, 8);
        checkBorrowingQuantity(3, 0);
    }

}
