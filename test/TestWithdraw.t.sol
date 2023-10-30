// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import {console} from "../lib/forge-std/src/Test.sol";
import {Setup} from "./Setup.sol";
// import {StdCheats} from "forge-std/StdCheats.sol";

contract TestWithdraw is Setup {
    
    // withdraw fails if remove non-existing sell order
    function test_RemoveNonExistingSellOrder() public {
        depositSellOrder(acc[1], 20, 110);
        vm.expectRevert("Order has zero assets");
        withdraw(acc[1], 2, 10);
        checkOrderQuantity(1, 20);
    }

    // withdraw fails if remove non-existing buy order
    function test_RemoveNonExistingBuyOrder() public {
        depositBuyOrder(acc[1], 2000, 90);
        vm.expectRevert("Order has zero assets");
        withdraw(acc[1], 2, 0);
        checkOrderQuantity(1, 2000);
    }
    
    // withdraw fails if removal of buy order is zero
    function testRemoveBuyOrderFailsIfZero() public {
        depositBuyOrder(acc[1], 2000, 90);
        vm.expectRevert("Must be positive");
        withdraw(acc[1], 1, 0);
        checkOrderQuantity(1, 2000);
    }

    // withdraw fails if removal of sell order is zero
    function test_RemoveSellOrderFailsIfZero() public {
        depositSellOrder(acc[1], 20, 110);
        vm.expectRevert("Must be positive");
        withdraw(acc[1], 1, 0);
        checkOrderQuantity(1, 20);
    }

    // withdraw fails if remover of buy order is not maker
    function test_RemoveBuyOrderFailsIfNotMaker() public {
        depositBuyOrder(acc[1], 2000, 90);
        vm.expectRevert("Only maker can remove order");
        withdraw(acc[2], 1, 2000);
        checkOrderQuantity(1, 2000);
    }

    // withdraw fails if remover of sell order is not maker
    function test_RemoveSellOrderFailsIfNotMaker() public {
        depositSellOrder(acc[1], 20, 110);
        vm.expectRevert("Only maker can remove order");
        withdraw(acc[2], 1, 20);
        checkOrderQuantity(1, 20);
    }
    
    // withdraw of buy order correctly adjusts external balances
    function test_RemoveBuyOrderCheckBalances() public {
        depositBuyOrder(acc[1], 2000, 90);
        uint256 bookBalance = quoteToken.balanceOf(address(book));
        uint256 userBalance = quoteToken.balanceOf(acc[1]);
        withdraw(acc[1], 1, 2000);
        assertEq(quoteToken.balanceOf(address(book)), bookBalance - 2000);
        assertEq(quoteToken.balanceOf(acc[1]), userBalance + 2000);
        checkOrderQuantity(1, 0);
    }

    // withdraw of sell order correctly adjusts external balances
    function test_RemoveSellOrderCheckBalances() public {
        depositSellOrder(acc[1], 20, 110);
        uint256 bookBalance = baseToken.balanceOf(address(book));
        uint256 userBalance = baseToken.balanceOf(acc[1]);
        withdraw(acc[1], 1, 20);
        assertEq(baseToken.balanceOf(address(book)), bookBalance - 20);
        assertEq(baseToken.balanceOf(acc[1]), userBalance + 20);
        checkOrderQuantity(1, 0);
    }

    // withdrawable quantity from buy order is correct
    function test_RemoveBuyOrderOutable() public {
        depositBuyOrder(acc[1], 2000, 90);
        assertEq(book.outableQuantity(1, 2000), 2000);
        assertEq(book.outableQuantity(1, 1900), 1900);
        assertEq(book.outableQuantity(1, 1901), 0);
    }

    // withdrawable quantity from sell order is correct
    function test_RemoveSellOrderOutable() public {
        depositSellOrder(acc[1], 20, 110);
        assertEq(book.outableQuantity(1, 20), 20);
        assertEq(book.outableQuantity(1, 19), 0);
        assertEq(book.outableQuantity(1, 18), 18);
    }

    // Depositor excess collateral is correct
    function test_DepositorBuyOrderExcessCollateral() public {
        depositBuyOrder(acc[1], 2000, 90);
        assertEq(book.getUserExcessCollateral(acc[1], buyOrder), 2000);
        withdraw(acc[1], 1, 1000);
        assertEq(book.getUserExcessCollateral(acc[1], buyOrder), 1000);
    }

    function test_DepositorSellOrderExcessCollateral() public {
        depositSellOrder(acc[1], 20, 110);
        assertEq(book.getUserExcessCollateral(acc[1], sellOrder), 20);
        withdraw(acc[1], 1, 10);
        assertEq(book.getUserExcessCollateral(acc[1], sellOrder), 10);
    }

    // add new order if same order but different maker
    function test_NewQuantityAfterRemoveBuyOrder() public {
        depositBuyOrder(acc[1], 3000, 90);
        withdraw(acc[1], 1, 3000);
        checkOrderQuantity(1, 0);
        depositBuyOrder(acc[2], 5000, 90);
        checkOrderQuantity(1, 0);
        checkOrderQuantity(2, 5000);
        depositBuyOrder(acc[1], 4000, 90);
        checkOrderQuantity(1, 4000);
    }

}
