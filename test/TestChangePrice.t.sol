// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Setup} from "./Setup.sol";
import {MathLib, WAD} from "../lib/MathLib.sol";

contract TestChangePrice is Setup {

    // ChangePairedPrice() with a new paired price for buy order
    // initial limit price is B = 4000, paire limit price is 4000
    // change paired price to 4400

    function test_ChangeBuyOrderPairedPrice() public depositBuy(B) {
        changePairedPrice(Alice, FirstOrderId, B + 2);
        checkOrderPairedPrice(FirstOrderId, B + 2);
    }

    // When caller is not maker of buy order, revert
    function test_RevertBuyOrderPairedIfNotMaker() public depositBuy(B) {
        vm.expectRevert("Only maker");
        changePairedPrice(Bob, FirstOrderId, B + 2);
    }

    // When new paired price of buy order with zero quantity, reverts
    function test_RevertBuyOrderPairedIfZeroQuantity() public depositBuy(B) {
        withdraw(Alice, FirstOrderId, DepositQT);
        vm.expectRevert("No order");
        changePairedPrice(Alice, FirstOrderId, B + 2);
    }

    // When new paired price is previous one, reverts
    function test_RevertBuyOrderPairedIfSame() public depositBuy(B) {
        vm.expectRevert("Same price");
        changePairedPrice(Alice, FirstOrderId, B + 1);
    }

    // When new paired price in buy order is in wrong order with limit price, revert
    function test_RevertBuyOrderPairedIfNotConsistent() public depositBuy(B) {
        vm.expectRevert("Inconsistent prices");
        changePairedPrice(Alice, FirstOrderId, B - 2);
    }

    // When new paired price in buy order is in wrong order with limit price, revert
    function test_RevertBuyOrderPairedIfTooFar() public depositBuy(B) {
        vm.expectRevert("Paired price too far");
        changePairedPrice(Alice, FirstOrderId, B + 10);
    }

}
