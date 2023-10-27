// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Setup} from "./Setup.sol";
import {StdCheats} from "forge-std/StdCheats.sol";

contract TestWithdraw is Setup {

    // withdraw fails if remove non-existing buy order
    function testFailRemoveNonExistingBuyOrder() public {
        depositBuyOrder(acc[1], 2000, 90);
        vm.prank(acc[1]);
        book.withdraw(2, 0);
        vm.expectRevert("Order has zero assets");
    }

    // withdraw fails if remove non-existing sell order
    function testFailRemoveNonExistingSellOrder() public {
        depositSellOrder(acc[1], 20, 110);
        vm.prank(acc[1]);
        book.withdraw(2, 0);
        vm.expectRevert("Order has zero assets");
    }
    
    // withdraw fails if removal of buy order is zero
    function testRemoveBuyOrderFailsIfZero() public {
        depositBuyOrder(acc[1], 2000, 90);
        vm.expectRevert("Must be positive");
        vm.prank(acc[2]);
        book.withdraw(1, 0);
    }

    // withdraw fails if removal of sell order is zero
    function testRemoveSellOrderFailsIfZero() public {
        depositSellOrder(acc[1], 20, 110);
        vm.expectRevert("Must be positive");
        vm.prank(acc[1]);
        book.withdraw(1, 0);
    }

    // withdraw fails if remover of buy order is not maker
    function testRemoveBuyOrderFailsIfNotMaker() public {
        depositBuyOrder(acc[1], 2000, 90);
        vm.expectRevert("Only maker can remove order");
        vm.prank(acc[2]);
        book.withdraw(1, 2000);
    }

    // withdraw fails if remover of sell order is not maker
    function testRemoveSellOrderFailsIfNotMaker() public {
        depositSellOrder(acc[2], 20, 110);
        vm.expectRevert("Only maker can remove order");
        vm.prank(acc[1]);
        book.withdraw(1, 20);
    }
    
    // withdraw of buy order correctly adjusts external balances
    function testRemoveBuyOrderCheckBalances() public {
        depositBuyOrder(acc[1], 2000, 90);
        uint256 bookBalance = quoteToken.balanceOf(address(book));
        uint256 userBalance = quoteToken.balanceOf(acc[1]);
        vm.prank(acc[1]);
        book.withdraw(1, 2000);
        assertEq(quoteToken.balanceOf(address(book)), bookBalance - 2000);
        assertEq(quoteToken.balanceOf(acc[1]), userBalance + 2000);
    }

    // withdraw of sell order correctly adjusts external balances
    function testRemoveSellOrderCheckBalances() public {
        depositSellOrder(acc[1], 20, 110);
        uint256 bookBalance = baseToken.balanceOf(address(book));
        uint256 userBalance = baseToken.balanceOf(acc[1]);
        vm.prank(acc[1]);
        book.withdraw(1, 20);
        assertEq(baseToken.balanceOf(address(book)), bookBalance - 20);
        assertEq(baseToken.balanceOf(acc[1]), userBalance + 20);
    }

    // withdrawable quantity from buy order is correct
    function testRemoveBuyOrderOutable() public {
        depositBuyOrder(acc[1], 2000, 90);
        assertEq(book.outableQuantity(1, 2000), 2000);
        assertEq(book.outableQuantity(1, 1900), 1900);
        assertEq(book.outableQuantity(1, 1901), 1900);
    }

    // withdrawable quantity from sell order is correct
    function testRemoveSellOrderOutable() public {
        depositSellOrder(acc[1], 20, 110);
        assertEq(book.outableQuantity(1, 20), 20);
        assertEq(book.outableQuantity(1, 19), 18);
    }

    // Depositor excess collateral is correct
    function testDepositorBuyOrderExcessCollateral() public {
        depositBuyOrder(acc[1], 2000, 90);
        assertEq(book.getUserExcessCollateral(acc[1], buyOrder), 2000);
        vm.prank(acc[1]);
        book.withdraw(1, 1000);
        assertEq(book.getUserExcessCollateral(acc[1], buyOrder), 1000);
    }

    function testDepositorSellOrderExcessCollateral() public {
        depositSellOrder(acc[1], 20, 110);
        assertEq(book.getUserExcessCollateral(acc[1], sellOrder), 20);
        vm.prank(acc[1]);
        book.withdraw(1, 10);
        assertEq(book.getUserExcessCollateral(acc[1], sellOrder), 10);
    }

    // add new order if same order but different maker
    function testNewQuantityAfterRemoveBuyOrder() public {
        depositBuyOrder(acc[1], 3000, 90);
        vm.prank(acc[1]);
        book.withdraw(1, 3000);
        (,, uint256 quantity,) = book.orders(1);
        assertEq(quantity, 0);
    }

    // add new order if same order but different maker
    function testNewQuantityAfterRemoveSellOrder() public {
        depositSellOrder(acc[1], 20, 110);
        vm.prank(acc[1]);
        book.withdraw(1, 20);
        (,, uint256 quantity,) = book.orders(1);
        assertEq(quantity, 0);
    }
}
