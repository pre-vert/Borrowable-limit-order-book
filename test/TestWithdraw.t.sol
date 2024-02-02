// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import {console} from "../lib/forge-std/src/Test.sol";
import {Setup} from "./Setup.sol";
import {MathLib, WAD} from "../lib/MathLib.sol";

contract TestWithdraw is Setup {
    
    // // withdraw fails if withdraw non-existing sell order
    // function test_RemoveNonExistingSellOrder() public {
    //     depositSellOrder(Alice, 20, 110);
    //     vm.expectRevert("Order has zero assets");
    //     withdraw(Alice, Bob_Order, 10);
    //     checkOrderQuantity(Alice_Order, 20);
    // }

    // // withdraw fails if remove non-existing buy order
    // function test_RemoveNonExistingBuyOrder() public {
    //     depositBuyOrder(Alice, 2000, 90);
    //     vm.expectRevert("Order has zero assets");
    //     withdraw(Alice, Bob_Order, 0);
    //     checkOrderQuantity(1, 2000);
    // }
    
    // // withdraw fails if removal of buy order is zero
    // function testRemoveBuyOrderFailsIfZero() public {
    //     depositBuyOrder(Alice, 2000, 90);
    //     vm.expectRevert("Must be positive");
    //     withdraw(Alice, Alice_Order, 0);
    //     checkOrderQuantity(Alice_Order, 2000);
    // }

    // // withdraw fails if removal of sell order is zero
    // function test_RemoveSellOrderFailsIfZero() public {
    //     depositSellOrder(Alice, 20, 110);
    //     vm.expectRevert("Must be positive");
    //     withdraw(Alice, Alice_Order, 0);
    //     checkOrderQuantity(Alice_Order, 20);
    // }

    // // withdraw fails if remover of buy order is not maker
    // function test_RemoveBuyOrderFailsIfNotMaker() public {
    //     depositBuyOrder(Alice, 2000, 90);
    //     vm.expectRevert("Only maker can modify order");
    //     withdraw(Bob, Alice_Order, 2000);
    //     checkOrderQuantity(Alice_Order, 2000);
    // }

    // // withdraw fails if remover of sell order is not maker
    // function test_RemoveSellOrderFailsIfNotMaker() public {
    //     depositSellOrder(Alice, 20, 110);
    //     vm.expectRevert("Only maker can modify order");
    //     withdraw(Bob, Alice_Order, 20);
    //     checkOrderQuantity(Alice_Order, 20);
    // }
    
    // // withdraw of buy order correctly adjusts external balances
    // function test_RemoveBuyOrderCheckBalances() public {
    //     depositBuyOrder(Alice, 2000, 90);
    //     uint256 bookBalance = quoteToken.balanceOf(OrderBook);
    //     uint256 userBalance = quoteToken.balanceOf(Alice);
    //     withdraw(Alice, Alice_Order, 2000);
    //     assertEq(quoteToken.balanceOf(OrderBook), bookBalance - 2000 * WAD);
    //     assertEq(quoteToken.balanceOf(Alice), userBalance + 2000 * WAD);
    //     checkOrderQuantity(Alice_Order, 0);
    // }

    // // withdraw of sell order correctly adjusts external balances
    // function test_RemoveSellOrderCheckBalances() public {
    //     depositSellOrder(Alice, 20, 110);
    //     uint256 bookBalance = baseToken.balanceOf(OrderBook);
    //     uint256 userBalance = baseToken.balanceOf(Alice);
    //     withdraw(Alice, Alice_Order, 20);
    //     assertEq(baseToken.balanceOf(OrderBook), bookBalance - 20 * WAD);
    //     assertEq(baseToken.balanceOf(Alice), userBalance + 20 * WAD);
    //     checkOrderQuantity(Alice_Order, 0);
    // }

    // // withdrawable quantity from buy order is correct
    // function test_RemoveBuyOrderOutable() public {
    //     uint256 minDeposit = book.minDeposit(BuyOrder);
    //     depositBuyOrder(Alice, DepositQT, LowPrice);
    //     withdraw(Alice, Alice_Order, DepositQT);
    //     depositBuyOrder(Alice, DepositQT, LowPrice);
    //     vm.expectRevert("Remove too much_1");
    //     withdraw(Alice, Alice_Order, DepositQT - minDeposit / WAD);
    //     depositBuyOrder(Alice, DepositQT, LowPrice);
    //     withdraw(Alice, Alice_Order, DepositQT + 1 - minDeposit / WAD);
    // }

    // // withdrawable quantity from sell order is correct
    // function test_RemoveSellOrderOutable() public {
    //     uint256 minDeposit = book.minDeposit(SellOrder);
    //     depositSellOrder(Alice, DepositBT, HighPrice);
    //     withdraw(Alice, Alice_Order, DepositBT);
    //     depositSellOrder(Alice, DepositBT, HighPrice);
    //     vm.expectRevert("Remove too much_1");
    //     withdraw(Alice, Alice_Order, DepositBT - minDeposit / WAD);
    //     depositSellOrder(Alice, DepositBT, HighPrice);
    //     withdraw(Alice, Alice_Order, DepositBT + 1 - minDeposit / WAD);
    // }

    // // Depositor excess collateral is correct
    // function test_DepositorBuyOrderExcessCollateral() public {
    //     depositBuyOrder(Alice, 2000, 90);
    //     assertEq(book._getExcessCollateral(Alice, BuyOrder), 2000 * WAD);
    //     withdraw(Alice, Alice_Order, 1000);
    //     assertEq(book._getExcessCollateral(Alice, BuyOrder), 1000 * WAD);
    // }

    // function test_DepositorSellOrderExcessCollateral() public {
    //     depositSellOrder(Alice, 20, 110);
    //     assertEq(book._getExcessCollateral(Alice, SellOrder), 20 * WAD);
    //     withdraw(Alice, Alice_Order, 10);
    //     assertEq(book._getExcessCollateral(Alice, SellOrder), 10 * WAD);
    // }

    // // add new order if same order but different maker
    // function test_RedepositAfterRemoveBuyOrder() public {
    //     depositBuyOrder(Alice, DepositQT, 90);
    //     withdraw(Alice, Alice_Order, DepositQT);
    //     checkOrderQuantity(Alice_Order, 0);
    //     depositBuyOrder(Bob, DepositQT, 90);
    //     checkOrderQuantity(Alice_Order, 0);
    //     depositBuyOrder(Alice, 2 * DepositQT, 90);
    //     checkOrderQuantity(Alice_Order, 2 * DepositQT);
    // }

    // function test_RedepositAfterRemoveDepositIdInUsers() public {
    //     setPriceFeed(120);
    //     depositBuyOrder(Alice, 3000, 110);
    //     withdraw(Alice, Alice_Order, 3000);
    //     checkUserDepositId(Alice, 0, Alice_Order);
    //     depositBuyOrder(Alice, 2000, 110);
    //     checkUserDepositId(Alice, 0, Alice_Order);
    //     checkUserDepositId(Alice, 1, No_Order);
    // }

}
