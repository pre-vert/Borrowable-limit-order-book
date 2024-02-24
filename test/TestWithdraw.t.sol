// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import {console} from "../lib/forge-std/src/Test.sol";
import {Setup} from "./Setup.sol";
import {MathLib, WAD} from "../lib/MathLib.sol";

contract TestWithdraw is Setup {
    
    // withdraw fails if withdraw non-existing Buy order
    function test_RemoveNonExistingBuyOrder() public depositBuy(FirstPoolId) {
        vm.expectRevert("No order");
        withdraw(Alice, SecondOrderId, DepositQT);
        checkOrderQuantity(SecondOrderId, 0);
    }
    
    // withdraw fails if withdraw non-existing sell order
    function test_RemoveNonExistingSellOrder() public setLowPrice() depositSell(FirstPoolId) {
        vm.expectRevert("No order");
        withdraw(Alice, SecondOrderId, DepositBT);
        checkOrderQuantity(SecondOrderId, 0);
    }

    // withdraw fails if removal of buy order is zero
    function testRemoveBuyOrderFailsIfZero() public depositBuy(FirstPoolId) {
        vm.expectRevert("Remove zero");
        withdraw(Alice, FirstOrderId, 0);
        checkOrderQuantity(FirstOrderId, DepositQT);
    }
    
    // withdraw fails if removal of sell order is zero
    function testRemoveSellOrderFailsIfZero() public setLowPrice() depositSell(FirstPoolId) {
        vm.expectRevert("Remove zero");
        withdraw(Alice, FirstOrderId, 0);
        checkOrderQuantity(FirstOrderId, DepositBT);
    }

    // withdraw fails if remover of buy order is not maker
    function test_RemoveBuyOrderFailsIfNotMaker() public depositBuy(FirstPoolId) {
        vm.expectRevert("Not maker");
        withdraw(Bob, FirstOrderId, DepositQT);
        checkOrderQuantity(FirstOrderId, DepositQT);
    }
    
    // withdraw fails if remover of buy order is not maker
    function test_RemoveSellOrderFailsIfNotMaker() public setLowPrice() depositSell(FirstPoolId) {
        vm.expectRevert("Not maker");
        withdraw(Alice, FirstOrderId, DepositBT);
        checkOrderQuantity(FirstOrderId, DepositBT);
    }
    
    // withdraw of buy order correctly adjusts external balances
    function test_RemoveBuyOrderCheckBalances() public depositBuy(FirstPoolId) {
        uint256 bookBalance = quoteToken.balanceOf(OrderBook);
        uint256 userBalance = quoteToken.balanceOf(Alice);
        withdraw(Alice, FirstOrderId, DepositQT);
        assertEq(quoteToken.balanceOf(OrderBook), bookBalance - DepositQT);
        assertEq(quoteToken.balanceOf(Alice), userBalance + DepositQT);
        checkOrderQuantity(FirstOrderId, 0);
    }

    // withdraw of sell order correctly adjusts external balances
    function test_RemoveSellOrderCheckBalances() public setLowPrice() depositSell(FirstPoolId) {
        uint256 bookBalance = baseToken.balanceOf(OrderBook);
        uint256 userBalance = baseToken.balanceOf(Bob);
        withdraw(Bob, FirstOrderId, DepositBT);
        assertEq(baseToken.balanceOf(OrderBook), bookBalance - DepositBT);
        assertEq(baseToken.balanceOf(Bob), userBalance + DepositBT);
        checkOrderQuantity(FirstOrderId, 0);
    }

    // withdrawable quantity from buy order is correct
    function test_RemoveBuyOrderOutable() public depositBuy(FirstPoolId) {
        uint256 minDeposit = book.minDeposit(BuyOrder);
        vm.expectRevert("Remove too much_3");
        withdraw(Alice, FirstOrderId, DepositQT - minDeposit / 2);
    }

    // withdrawable quantity from sell order is correct
    function test_RemoveSellOrderOutable() public setLowPrice() depositSell(FirstPoolId) {
        uint256 minDeposit = book.minDeposit(SellOrder);
        console.log("minDeposit : ", minDeposit);
        vm.expectRevert("Remove too much_3");
        withdraw(Bob, FirstOrderId, DepositBT - minDeposit / 2);
    }

    // Withdraw buy order, user excess collateral is correct
    function test_WithdrawBuyOrderExcessCollateral() public depositBuy(FirstPoolId) {
        withdraw(Alice, FirstOrderId, DepositQT);
        uint256 userEC = book.getUserExcessCollateral(Alice, 0, book.ALTV());
        assertEq(userEC, 0);
    }

    // Withdraw sell order, user excess collateral is correct
    function test_WithdrawSellOrderExcessCollateral() public setLowPrice() depositSell(FirstPoolId) {
        withdraw(Bob, FirstOrderId, DepositBT);
        uint256 userEC = book.getUserExcessCollateral(Bob, 0, book.ALTV());
        assertEq(userEC, 0);
    }

}
