// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Setup} from "./Setup.sol";
import {MathLib, WAD} from "../lib/MathLib.sol";

contract TestChangePrice is Setup {

    // Calling ChangeLimitPrice() with a new limit price changes the limit price
    function test_ChangeBuyOrderLimitPrice() public {
        depositBuyOrder(Alice, 1000, 90);
        changeLimitPrice(Alice, Alice_Order, 95);
        checkOrderPrice(Alice_Order, 95);
    }

    // Calling ChangeLimitPrice() with a new limit price changes the limit price
    function test_ChangeSellOrderLimitPrice() public {
        depositSellOrder(Alice, 10, 110);
        changeLimitPrice(Alice, Alice_Order, 115);
        checkOrderPrice(Alice_Order, 115);
    }
    
    // When buy order's price is zero, revert
    function test_RevertBuyOrderIfZeroLimitPrice() public {
        depositBuyOrder(Alice, 1000, 90);
        vm.expectRevert("Must be positive");
        changeLimitPrice(Alice, Alice_Order, 0);
    }

    // When sell order's price is zero, revert
    function test_RevertSellOrderIfZeroLimitPrice() public {
        depositSellOrder(Alice, 10, 110);
        vm.expectRevert("Must be positive");
        changeLimitPrice(Alice, Alice_Order, 0);
    }

    // When caller is not maker of buy order, revert
    function test_RevertBuyOrderIfNotMaker() public {
        depositBuyOrder(Alice, 1000, 90);
        vm.expectRevert("Only maker can modify order");
        changeLimitPrice(Bob, Alice_Order, 80);
    }

    // When caller is not maker of sell order, revert
    function test_RevertSellOrderIfNotMaker() public {
        depositSellOrder(Alice, 10, 110);
        vm.expectRevert("Only maker can modify order");
        changeLimitPrice(Carol, Alice_Order, 120);
    }

    // When new buy order's limit price is not consistent, revert
    function test_RevertBuyOrderIfNotConsistent() public {
        depositBuyOrder(Alice, 1000, 90);
        setPriceFeed(120);
        vm.expectRevert("Inconsistent prices");
        changeLimitPrice(Alice, Alice_Order, 110);
    }

    // When new sell order's limit price is not consistent, revert
    function test_RevertSellOrderIfNotConsistent() public {
        depositSellOrder(Alice, 10, 110);
        setPriceFeed(90);
        vm.expectRevert("Inconsistent prices");
        changeLimitPrice(Alice, Alice_Order, 95);
    }

    // If buy order is borrowed, changing limit price reverts
    function test_RevertBuyOrderIfBorrowed() public {
        depositBuyOrder(Alice, 3000, 90);
        depositSellOrder(Bob, 30, 110);
        borrow(Bob, Alice_Order, 1000);
        vm.expectRevert("Order must not be borrowed from");
        changeLimitPrice(Alice, Alice_Order, 95);
    }

    // If sell order is borrowed, changing limit price reverts
    function test_RevertSellOrderIfBorrowed() public {
        depositSellOrder(Alice, 30, 110);
        depositBuyOrder(Bob, 3000, 90);
        borrow(Bob, Alice_Order, 10);
        vm.expectRevert("Order must not be borrowed from");
        changeLimitPrice(Alice, Alice_Order, 111);
    }




    // Check that filling 0 in paired price while depositing sets buy order's paired price to limit price + 10%
    function test_SetBuyOrderPairedPriceToZeroOk() public {
        depositBuyOrderWithPairedPrice(Alice, 1000, 90, 0);
        checkOrderPairedPrice(Alice_Order, 90 + 90 / 10);
    }

    // Check that filling 0 in paired price while depositing sets buy order's paired price to limit price - 10%
    function test_SetSellOrderPairedPriceToZeroOk() public {
        depositSellOrderWithPairedPrice(Alice, 10, 110, 0);
        checkOrderPairedPrice(Alice_Order, 110 - 110/11);
    }

    // Calling ChangePairedPrice() with a new paired price changes the paired price
    function test_ChangeBuyOrderPairedPrice() public {
        depositBuyOrder(Alice, 1000, 90);
        changePairedPrice(Alice, Alice_Order, 95);
        checkOrderPairedPrice(Alice_Order, 95);
    }

    // Calling ChangePairedPrice() with a new paired price changes the paired price
    function test_ChangeSellOrderPairedPrice() public {
        depositSellOrder(Alice, 10, 110);
        changePairedPrice(Alice, Alice_Order, 90);
        checkOrderPairedPrice(Alice_Order, 90);
    }

    // When buy order's paired price is zero, revert
    function test_RevertBuyOrderIfZeroPairedPrice() public {
        depositBuyOrder(Alice, 1000, 90);
        vm.expectRevert("Must be positive");
        changePairedPrice(Alice, Alice_Order, 0);
    }

    // When sell order's paired price is zero, revert
    function test_RevertSellOrderIfZeroPairedPrice() public {
        depositSellOrder(Alice, 10, 110);
        vm.expectRevert("Must be positive");
        changePairedPrice(Alice, Alice_Order, 0);
    }

    // When caller is not maker of buy order, revert
    function test_RevertBuyOrderPairedIfNotMaker() public {
        depositBuyOrder(Alice, 1000, 90);
        vm.expectRevert("Only maker can modify order");
        changePairedPrice(Bob, Alice_Order, 80);
    }

    // When caller is not maker of sell order, revert
    function test_RevertSellOrderPairedIfNotMaker() public {
        depositSellOrder(Alice, 10, 110);
        vm.expectRevert("Only maker can modify order");
        changePairedPrice(Carol, Alice_Order, 120);
    }

    // When changed buy order's paired price is not consistent, revert
    function test_RevertBuyOrderPairedIfNotConsistent() public {
        depositBuyOrder(Alice, 1000, 90);
        setPriceFeed(70);
        vm.expectRevert("Inconsistent prices");
        changePairedPrice(Alice, Alice_Order, 80);
    }

    // When changed sell order's paired price is not consistent, revert
    function test_RevertSellOrderPairedIfNotConsistent() public {
        depositSellOrder(Alice, 10, 110);
        setPriceFeed(130);
        vm.expectRevert("Inconsistent prices");
        changePairedPrice(Alice, Alice_Order, 120);
    }

    // When changed buy order's paired price is not consistent, revert
    function test_PairedPriceReturnsToInitialValue() public {
        setPriceFeed(95);
        depositBuyOrder(Alice, 3000, 90);
        depositSellOrder(Alice, 30, 99);
        checkOrderPairedPrice(Alice_Order, 99);
        checkOrderPairedPrice(Alice_Order + 1, 90);
    }


}
