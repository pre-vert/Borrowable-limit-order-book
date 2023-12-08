// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Setup} from "./Setup.sol";
import {MathLib, WAD} from "../lib/MathLib.sol";

contract TestBorrow is Setup {
    
    // borrow fails if non-existing buy order
    function test_BorrowNonExistingBuyOrder() public {
        depositBuyOrder(Alice, 2000, 90);
        vm.expectRevert("Order has zero assets");
        borrow(Alice, Bob_Order, 10);
        checkOrderQuantity(1, 2000);
    }

    // borrow fails if non-existing sell order
    function test_BorrowNonExistingSellOrder() public {
        depositSellOrder(Alice, 20, 110);
        vm.expectRevert("Order has zero assets");
        borrow(Alice, Bob_Order, 1000);
        checkOrderQuantity(1, 20);
    }
    
    // fails if borrowing of buy order is zero
    function test_BorrowBuyOrderFailsIfZero() public {
        depositBuyOrder(Alice, 2000, 90);
        depositSellOrder(Bob, 30, 110);
        vm.expectRevert("Must be positive");
        borrow(Bob, Alice_Order, 0);
        checkOrderQuantity(Alice_Order, 2000);
    }

    // fails if borrowing of sell order is zero
    function test_BorrowSellOrderFailsIfZero() public {
        depositSellOrder(Alice, 20, 110);
        depositBuyOrder(Bob, 3000, 90);
        vm.expectRevert("Must be positive");
        borrow(Bob, Alice_Order, 0);
        checkOrderQuantity(Alice_Order, 20);
    }

    // ok if borrower of buy order is maker
    function test_BorrowBuyOrderOkIfMaker() public {
        depositBuyOrder(Alice, DepositQT, LowPrice);
        depositSellOrder(Alice, DepositBT, HighPrice);
        borrow(Alice, Alice_Order, DepositQT / 2);
        checkOrderQuantity(Alice_Order, DepositQT);
        checkBorrowingQuantity(Alice_Order, DepositQT / 2); 
    }

    // ok if borrower of sell order is maker
    function test_BorrowSellOrderOkIfMaker() public {
        depositSellOrder(Alice, DepositBT, HighPrice);
        depositBuyOrder(Alice, DepositQT, LowPrice);
        borrow(Alice, Alice_Order, DepositBT / 2);
        checkOrderQuantity(Alice_Order, DepositBT);
        checkBorrowingQuantity(1, DepositBT / 2); 
    }
    
    // borrow of buy order correctly adjusts balances
    function test_BorrowBuyOrderCheckBalances() public {
        depositBuyOrder(Alice, DepositQT, LowPrice);
        depositSellOrder(Bob, DepositBT, HighPrice);
        uint256 bookBalance = quoteToken.balanceOf(OrderBook);
        uint256 lenderBalance = quoteToken.balanceOf(Alice);
        uint256 borrowerBalance = quoteToken.balanceOf(Bob);
        borrow(Bob, Alice_Order, DepositQT / 2);
        assertEq(quoteToken.balanceOf(OrderBook), bookBalance - WAD * DepositQT / 2);
        assertEq(quoteToken.balanceOf(Alice), lenderBalance);
        assertEq(quoteToken.balanceOf(Bob), borrowerBalance + WAD * DepositQT / 2);
        checkOrderQuantity(Alice_Order, DepositQT);
        checkOrderQuantity(Bob_Order, DepositBT);
        checkBorrowingQuantity(1, DepositQT / 2); 
    }

    // borrow of sell order correctly adjusts external balances
    function test_FailsIfBorrowAllDeposit() public {
        depositSellOrder(Alice, 20, 110);
        depositBuyOrder(Bob, 3000, 90);
        vm.expectRevert("Borrow too much 0");
        borrow(Bob, Alice_Order, 20); 
    }
    
    // borrow sell order correctly adjusts external balances
    function test_BorowSellOrderCheckBalances() public {
        uint256 borrowedQuantity = DepositBT - 2 * book.minDeposit(SellOrder) / WAD;
        console.log("DepositBT: ", DepositBT);
        console.log("borrowedQuantity: ", borrowedQuantity);
        depositSellOrder(Alice, DepositBT, 110);
        depositBuyOrder(Bob, DepositQT, 90);
        uint256 bookBalance = baseToken.balanceOf(OrderBook);
        uint256 lenderBalance = baseToken.balanceOf(Alice);
        uint256 borrowerBalance = baseToken.balanceOf(Bob);
        borrow(Bob, Alice_Order, borrowedQuantity);
        assertEq(baseToken.balanceOf(OrderBook), bookBalance - borrowedQuantity * WAD);
        assertEq(baseToken.balanceOf(Alice), lenderBalance);
        assertEq(baseToken.balanceOf(Bob), borrowerBalance + borrowedQuantity * WAD);
        checkOrderQuantity(Alice_Order, DepositBT);
        checkOrderQuantity(Bob_Order, DepositQT);
        checkBorrowingQuantity(1, borrowedQuantity); 
    }

    // borrowable quantity from buy order is correct
    function test_BorrowBuyOrderOutable() public {
        depositBuyOrder(Alice, DepositQT, LowPrice);
        depositSellOrder(Bob, DepositBT, HighPrice);
        borrow(Bob, Alice_Order, DepositQT / 2);
        repay(Bob, Alice_Order, DepositQT / 2);
        vm.expectRevert("Borrow too much 0");
        borrow(Bob, Alice_Order, DepositQT);
    }

    // borrowable quantity from sell order is correct
    function test_BorrowSellOrderOutable() public {
        depositSellOrder(Alice, DepositBT, HighPrice);
        depositBuyOrder(Bob, DepositQT, LowPrice);
        borrow(Bob, Alice_Order, DepositBT / 2);
        repay(Bob, Alice_Order, DepositBT / 2);
        vm.expectRevert("Borrow too much 0");
        borrow(Bob, Alice_Order, DepositBT);
    }

    // Lender and borrower excess collaterals in quote and base token are correct
    function test_BorrowBuyOrderExcessCollateral() public {
        depositBuyOrder(Alice, 2000, 90);
        depositSellOrder(Bob, 30, 110);
        uint256 lenderExcessCollateral = book._getExcessCollateral(Alice, InQuoteToken);
        uint256 borrowerExcessCollateral = book._getExcessCollateral(Bob, InBaseToken);
        borrow(Bob, Alice_Order, 900);
        assertEq(book._getExcessCollateral(Alice, InQuoteToken), lenderExcessCollateral - 900 * WAD);
        assertEq(book._getExcessCollateral(Bob, InBaseToken), borrowerExcessCollateral - 10 * WAD);
    }

    // Lender and borrower excess collaterals in base and quote token are correct
    function test_BorrowSellOrderExcessCollateral() public {
        depositSellOrder(Alice, 20, 110);
        depositBuyOrder(Bob, 3000, 90);
        uint256 lenderExcessCollateral = book._getExcessCollateral(Alice, InBaseToken);
        uint256 borrowerExcessCollateral = book._getExcessCollateral(Bob, InQuoteToken);
        borrow(Bob, Alice_Order, 10);
        assertEq(book._getExcessCollateral(Alice, InBaseToken), lenderExcessCollateral - 10 * WAD);
        assertEq(book._getExcessCollateral(Bob, InQuoteToken), borrowerExcessCollateral - 10*110 * WAD);
    }

    // Bob borrows from Alice's sell order, borrowFromIds array correctly updates
    function test_BorrowFromIdInUsers() public {
        depositSellOrder(Alice, 20, 110);
        depositBuyOrder(Bob, 3000, 90);
        checkUserBorrowId(Bob, 0, No_Order);
        borrow(Bob, Alice_Order, 10);
        checkUserBorrowId(Bob, 0, Alice_Order);
        checkUserBorrowId(Bob, 1, No_Order);
    }

    // Bob borrows twice from Alice's sell order, borrowing positions should be aggregated
    function test_BorrowTwiceFromSameOrder() public {
        depositSellOrder(Alice, 30, 110);
        depositBuyOrder(Bob, 5000, 90);
        borrow(Bob, Alice_Order, 10);
        borrow(Bob, Alice_Order, 5);
        checkUserBorrowId(Bob, 0, Alice_Order);
        checkUserBorrowId(Bob, 1, Alice_Order);
        checkBorrowingQuantity(1, 15);
        checkBorrowingQuantity(2, 0);
    }

    // Alice borrows from Alice's and Bob's sell order, borrowFromIds arrary correctly updates
    function test_BorrowTwiceFromTwoOrders() public {
        setPriceFeed(95);
        depositSellOrder(Alice, 30, 110);
        depositSellOrder(Bob, 20, 100);
        depositBuyOrder(Carol, 6000, 90);
        checkUserBorrowId(Carol, 0, No_Order);
        borrow(Carol, Alice_Order, 15);
        checkUserBorrowId(Carol, 0, Alice_Order);
        borrow(Carol, Bob_Order, 10);
        checkBorrowingQuantity(1, 15);
        checkBorrowingQuantity(2, 10);
        checkUserBorrowId(Carol, 0, Alice_Order);
        checkUserBorrowId(Carol, 1, Bob_Order);
    }

    // fail if user has more than max number of positions
    function test_PositionsForUserExceedLimit() public {
        setPriceFeed(95);
        depositSellOrder(Alice, 30, 110);
        depositSellOrder(Bob, 20, 100);
        depositSellOrder(Carol, 40, 120);
        depositBuyOrder(Dave, 10000, 90);
        borrow(Dave, Alice_Order, 15);
        borrow(Dave, Bob_Order, 10);
        checkUserBorrowId(Dave, 0, Alice_Order);
        checkUserBorrowId(Dave, 1, Bob_Order);
        vm.expectRevert("Max positions reached for borrower");
        borrow(Dave, Carol_Order, 5);
        checkBorrowingQuantity(3, 0);
    }

    // fail if order has more than max number of positions
    function test_PositionsForOrderExceedLimit() public {
        setPriceFeed(95);
        depositBuyOrder(Alice, 6000, 90);
        depositSellOrder(Bob, 20, 100);
        depositSellOrder(Carol, 40, 120);
        depositSellOrder(Dave, 10, 110);
        borrow(Bob, Alice_Order, 5);
        borrow(Carol, Alice_Order, 10);
        checkOrderPositionId(Alice_Order, 0, 1);
        checkOrderPositionId(Alice_Order, 1, 2);
        vm.expectRevert("Max positions reached for order");
        borrow(Dave, Alice_Order, 8);
        checkBorrowingQuantity(3, 0);
    }

    // borrower of buy order is maker correctly adjusts balances
    //

    function test_MakerBorrowsHerBuyOrderCheckBalances() public {
        depositBuyOrder(Alice, DepositQT, LowPrice);
        depositSellOrder(Alice, DepositBT, HighPrice);
        uint256 bookBalance = quoteToken.balanceOf(OrderBook);
        uint256 lenderBorrowerBalance = quoteToken.balanceOf(Alice);
        borrow(Alice, Alice_Order, DepositQT / 2);
        assertEq(quoteToken.balanceOf(OrderBook), bookBalance - WAD * DepositQT / 2);
        assertEq(quoteToken.balanceOf(Alice), lenderBorrowerBalance + WAD * DepositQT / 2);
        checkOrderQuantity(Alice_Order, DepositQT);
        checkOrderQuantity(Alice_Order + 1, DepositBT);
        checkBorrowingQuantity(1, DepositQT / 2); 
    }

    // maker cross-borrows her own orders correctly adjusts balances
    function test_MakerCrossBorrowsHerOrdersCheckBalances() public {
        setPriceFeed(95);
        depositBuyOrder(Alice, 3600, 90);
        depositSellOrder(Alice, 60, 100);
        uint256 bookQuoteBalance = quoteToken.balanceOf(OrderBook);
        uint256 lenderBorrowerQuoteBalance = quoteToken.balanceOf(Alice);
        uint256 bookBaseBalance = baseToken.balanceOf(OrderBook);
        uint256 lenderBorrowerBaseBalance = baseToken.balanceOf(Alice);
        borrow(Alice, Alice_Order, 900);
        borrow(Alice, Alice_Order + 1, 10);
        assertEq(quoteToken.balanceOf(OrderBook), bookQuoteBalance - 900 * WAD);
        assertEq(quoteToken.balanceOf(Alice), lenderBorrowerQuoteBalance + 900 * WAD);
        assertEq(baseToken.balanceOf(OrderBook), bookBaseBalance - 10 * WAD);
        assertEq(baseToken.balanceOf(Alice), lenderBorrowerBaseBalance + 10 * WAD);
        checkOrderQuantity(Alice_Order, 3600); // borrowing does'nt change quantity in order
        checkOrderQuantity(Alice_Order + 1, 60);
        checkBorrowingQuantity(1, 900);
        checkBorrowingQuantity(2, 10); 
    }

    // maker loop-borrows her own orders correctly adjusts balances
    function test_MakerLoopBorrowsHerOrdersCheckBalances() public {
        setPriceFeed(95);
        depositBuyOrder(Alice, 4500, 90);
        depositSellOrder(Alice, 60, 100);
        uint256 bookQuoteBalance = quoteToken.balanceOf(OrderBook);
        uint256 lenderBorrowerQuoteBalance = quoteToken.balanceOf(Alice);
        uint256 bookBaseBalance = baseToken.balanceOf(OrderBook);
        uint256 lenderBorrowerBaseBalance = baseToken.balanceOf(Alice);
        borrow(Alice, Alice_Order, 1800);
        depositBuyOrder(Alice, 1800, 90);
        assertEq(quoteToken.balanceOf(OrderBook), bookQuoteBalance);
        assertEq(quoteToken.balanceOf(Alice), lenderBorrowerQuoteBalance);
        assertEq(baseToken.balanceOf(OrderBook), bookBaseBalance);
        assertEq(baseToken.balanceOf(Alice), lenderBorrowerBaseBalance);
        checkOrderQuantity(Alice_Order, 4500 + 1800); // borrowing doesn't change quantity in order
        checkOrderQuantity(Alice_Order + 1, 60);
        checkBorrowingQuantity(1, 1800);
    }

    // users can't borrow non-borrowable buy orders
    function test_CantBorrowNonBorrowableBuyOrder() public {
        depositBuyOrder(Alice, 3000, 90);
        depositSellOrder(Bob, 30, 110);
        makeOrderNonBorrowable(Alice, Alice_Order);
        vm.expectRevert("Order non borrowable");
        borrow(Bob, Alice_Order, 1000);
        // makeOrderBorrowable(Alice, Alice_Order);
        // checkOrderIsBorrowable(Alice_Order);
    }

    // users can't borrow non-borrowable sell orders
    function test_CantBorrowNonBorrowableSellOrder() public {
        setPriceFeed(95);
        depositSellOrder(Alice, 30, 100);
        depositBuyOrder(Bob, 3000, 90);
        makeOrderNonBorrowable(Alice, Alice_Order);
        vm.expectRevert("Order non borrowable");
        borrow(Bob, Alice_Order, 10);
    }

    // users can't borrow borrowed buy orders after repayment
    function test_CantBorrowNonBorrowableBuyOrderAfterRepay() public {
        depositBuyOrder(Alice, 3000, 90);
        depositSellOrder(Bob, 30, 110);
        borrow(Bob, Alice_Order, 900);
        makeOrderNonBorrowable(Alice, Alice_Order);
        repay(Bob, Alice_Order, 900);
        vm.expectRevert("Order non borrowable");
        borrow(Bob, Alice_Order, 1000);
    }

    // users can't borrow borrowed buy orders after repayment
    function test_CantBorrowNonBorrowableSellOrderAfterRepay() public {
        setPriceFeed(95);
        depositSellOrder(Alice, 30, 100);
        depositBuyOrder(Bob, 3000, 90);
        borrow(Bob, Alice_Order, 10);
        repay(Bob, Alice_Order, 10);
        makeOrderNonBorrowable(Alice, Alice_Order);
        vm.expectRevert("Order non borrowable");
        borrow(Bob, Alice_Order, 10);
    }

}
