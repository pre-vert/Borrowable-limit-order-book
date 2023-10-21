// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Setup} from "./Setup.sol";
import {StdCheats} from "forge-std/StdCheats.sol";

contract TestWithdraw is Setup {

    function testRemoveBuyOrderFailsIfNotMaker() public {
        depositBuyOrder(USER1, 2000, 90);
        vm.expectRevert("Only maker can remove order");
        vm.prank(USER2);
        book.withdraw(1, 2000);
    }

    function testRemoveSellOrderFailsIfNotMaker() public {
        depositSellOrder(USER2, 20, 110);
        vm.expectRevert("Only maker can remove order");
        vm.prank(USER1);
        book.withdraw(1, 20);
    }

    function testRemoveBuyOrderCheckBalances() public {
        depositBuyOrder(USER1, 2000, 90);
        uint256 bookBalance = quoteToken.balanceOf(address(book));
        uint256 userBalance = quoteToken.balanceOf(USER1);
        vm.prank(USER1);
        book.withdraw(1, 2000);
        assertEq(quoteToken.balanceOf(address(book)), bookBalance - 2000);
        assertEq(quoteToken.balanceOf(USER1), userBalance + 2000);
    }
}
