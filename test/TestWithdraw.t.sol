// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import {console} from "../lib/forge-std/src/Test.sol";
import {Setup} from "./Setup.sol";
import {MathLib, WAD} from "../lib/MathLib.sol";

contract TestWithdraw is Setup {
    
    // User can withdraw after depositing in base account
    function test_DepositInAccountWithdraw() public depositInAccount(DepositBT) {
       withdrawFromBaseAccount(Bob, DepositBT);
    }
    
    // withdraw fails if withdraw non-existing Buy order
    function test_RemoveNonExistingBuyOrder() public depositBuy(B) {
        vm.expectRevert("No order");
        withdraw(Alice, SecondOrderId, DepositQT);
    }
    
    // withdraw fails if withdraw non-existing sell order
    function test_RemoveNonExistingSellOrder() public setLowPrice() depositSell(B + 1) {
        vm.expectRevert("No order");
        withdraw(Alice, SecondOrderId, DepositBT);
    }

    // withdraw fails if removal of buy order is zero
    function testRemoveBuyOrderFailsIfZero() public depositBuy(B) {
        vm.expectRevert("Remove zero");
        withdraw(Alice, FirstOrderId, 0);
    }
    
    // withdraw fails if removal of sell order is zero
    function testRemoveSellOrderFailsIfZero() public setLowPrice() depositSell(B + 1) {
        vm.expectRevert("Remove zero");
        withdraw(Alice, FirstOrderId, 0);
    }

    // withdraw from base account fails if zero
    function test_WithdrawFromBaseAccountFailsIfZero() public depositInAccount(DepositBT) {
       vm.expectRevert("Remove zero");
       withdrawFromBaseAccount(Bob, 0);
    }

    // withdraw fails if remover of buy order is not maker
    function test_RemoveBuyOrderFailsIfNotMaker() public depositBuy(B) {
        vm.expectRevert("Not maker");
        withdraw(Bob, FirstOrderId, DepositQT);
        assertEq(getOrderQuantity(FirstOrderId), DepositQT);
    }
    
    // withdraw fails if remover of sell order is not maker
    function test_RemoveSellOrderFailsIfNotMaker() public setLowPrice() depositSell(B + 1) {
        vm.expectRevert("Not maker");
        withdraw(Alice, FirstOrderId, DepositBT);
        assertEq(getOrderQuantity(FirstOrderId), DepositBT);
    }

    // withdraw from base account fails if not maker
    function test_DepositInAccountWithdrawFailsIfNotMaker() public depositInAccount(DepositBT) {
       vm.expectRevert("Remove too much_4");
       withdrawFromBaseAccount(Alice, DepositBT);
    }
    
    // withdraw of buy order correctly adjusts external balances
    function test_RemoveBuyOrderCheckBalances() public depositBuy(B) {
        uint256 bookBalance = quoteToken.balanceOf(OrderBook);
        uint256 userBalance = quoteToken.balanceOf(Alice);
        withdraw(Alice, FirstOrderId, DepositQT);
        assertEq(quoteToken.balanceOf(OrderBook), bookBalance - DepositQT);
        assertEq(quoteToken.balanceOf(Alice), userBalance + DepositQT);
        assertEq(getOrderQuantity(FirstOrderId), 0);
    }

    // withdraw of sell order correctly adjusts external balances
    function test_RemoveSellOrderCheckBalances() public setLowPrice() depositSell(B + 1) {
        vm.warp(0);
        // uint256 bookBalance = baseToken.balanceOf(OrderBook);
        // uint256 userBalance = baseToken.balanceOf(Bob);
        withdraw(Bob, FirstOrderId, DepositBT);
        // assertEq(baseToken.balanceOf(OrderBook), bookBalance - DepositBT);
        // assertEq(baseToken.balanceOf(Bob), userBalance + DepositBT);
        // assertEq(getOrderQuantity(FirstOrderId), 0);
    }

    // Withdraw from account in base assets correctly adjusts external balances
    function test_DepositBaseAccountCheckBalances() public depositInAccount(DepositBT) {
        uint256 OrderBookBalance = baseToken.balanceOf(OrderBook);
        uint256 userBalance = baseToken.balanceOf(Bob);
        withdrawFromBaseAccount(Bob, DepositBT / 2);
        assertEq(baseToken.balanceOf(OrderBook), OrderBookBalance - DepositBT / 2);
        assertEq(baseToken.balanceOf(Bob), userBalance + DepositBT / 2);
    }

    // withdrawable quantity from buy order is correct
    function test_RemoveBuyOrderOutable() public depositBuy(B) {
        uint256 minDeposit = book.viewMinDeposit(BuyOrder);
        vm.expectRevert("Remove too much_3");
        withdraw(Alice, FirstOrderId, DepositQT - minDeposit / 2);
    }

    // withdrawable quantity from sell order is correct
    function test_RemoveSellOrderOutable() public setLowPrice() depositSell(B + 1) {
        uint256 minDeposit = book.viewMinDeposit(SellOrder);
        console.log("minDeposit : ", minDeposit);
        vm.expectRevert("Remove too much_3");
        withdraw(Bob, FirstOrderId, DepositBT - minDeposit / 2);
    }

    // Withdraw buy order, user excess collateral is correct
    function test_WithdrawBuyOrderExcessCollateral() public depositBuy(B) {
        withdraw(Alice, FirstOrderId, DepositQT);
        (, uint256 userEC) = book.viewUserExcessCollateral(Alice, 0);
        assertEq(userEC, 0);
    }

    // Withdraw sell order, user excess collateral is correct
    function test_WithdrawSellOrderExcessCollateral() public setLowPrice() depositSell(B + 1) {
        withdraw(Bob, FirstOrderId, DepositBT);
        (, uint256 userEC) = book.viewUserExcessCollateral(Bob, 0);
        assertEq(userEC, 0);
    }

    // User excess collateral is correct after withdraw base account
    function test_WithdrawFromAccountExcessCollateral() public depositInAccount(DepositBT) {
        withdrawFromBaseAccount(Bob, DepositBT / 2);
       (bool isPositive, uint256 userEC) = book.viewUserExcessCollateral(Bob, 0);
        assertEq(userEC, DepositBT / 2);
        assertEq(isPositive, true);
    }
}
