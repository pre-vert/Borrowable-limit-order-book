// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Setup} from "./Setup.sol";
import {StdCheats} from "forge-std/StdCheats.sol";

contract TestTake is Setup {

    function testTakeBuyOrder() public {
        depositBuyOrder(USER1, 2000, 90);
        vm.prank(USER2);
        book.take(1, 2000);
    }

    function testTakeBuyOrderCheckBalances() public {
        depositBuyOrder(USER1, 1800, 90);
        uint256 contractQuoteBalance = quoteToken.balanceOf(address(book));
        uint256 makerQuoteBalance = quoteToken.balanceOf(USER1);
        uint256 makerBaseBalance = baseToken.balanceOf(USER1);
        uint256 takerQuoteBalance = quoteToken.balanceOf(USER2);
        uint256 takerBaseBalance = baseToken.balanceOf(USER2);
        vm.prank(USER2);
        book.take(1, 1800);
        assertEq(quoteToken.balanceOf(address(book)), contractQuoteBalance - 1800);
        assertEq(quoteToken.balanceOf(USER1), makerQuoteBalance);
        assertEq(baseToken.balanceOf(USER1), makerBaseBalance + 1800 / 90);
        assertEq(quoteToken.balanceOf(USER2), takerQuoteBalance + 1800);
        assertEq(baseToken.balanceOf(USER2), takerBaseBalance - 1800 / 90);
    }
}
