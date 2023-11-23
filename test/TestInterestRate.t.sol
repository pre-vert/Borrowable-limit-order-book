// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

/// @notice tests of interest rate model

import {Test, console} from "forge-std/Test.sol";
import {Setup} from "./Setup.sol";
import {MathLib, WAD} from "../lib/MathLib.sol";

contract TestInterestRate is Setup {

    // borrow fails if non-existing sell order
    function test_BorrowNonExistingSellOrder() public {
        depositBuyOrder(Alice, 6000, 100);
        depositSellOrder(Alice, 30, 110);
        // vm.expectRevert("Order has zero assets");
        // borrow(Alice, 2, 1000);
        // checkOrderQuantity(1, 20);
    }

}
