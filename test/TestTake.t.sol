// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Setup} from "./Setup.sol";
import {MathLib, WAD} from "../lib/MathLib.sol";

contract TestTake is Setup {

    // taking fails if non-existing buy order
    function test_TakingFailsIfNonExistingBuyOrder() public {
        depositBuyOrder(acc[1], 2000, 90);
        vm.expectRevert("Order has zero assets");
        take(acc[2], 2, 0);
    }

    // taking fails if non existing sell order
    function test_TakingFailsIfNonExistingSellOrder() public {
        depositSellOrder(acc[1], 20, 110);
        vm.expectRevert("Order has zero assets");
        take(acc[2], 2, 0);
    }

    // taking fails if zero taken, buy order
    function test_TakeBuyOrderFailsIfZero() public {
        depositBuyOrder(acc[1], 2000, 90);
        vm.expectRevert("Must be positive");
        take(acc[2], 1, 0);
    }

    // taking fails if zero taken, sell order
    function test_TakeSellOrderFailsIfZero() public {
        depositSellOrder(acc[1], 20, 110);
        vm.expectRevert("Must be positive");
        take(acc[2], 1, 0);
    }

    // taking fails if greater than buy order
    function test_TakeBuyOrderFailsIfTooMuch() public {
        depositBuyOrder(acc[1], 2000, 90);
        assertEq(book.outable(1, 2001 * WAD), false);
        vm.expectRevert("Too much assets taken");
        take(acc[2], 1, 2001);
    }

    // taking fails if greater than sell order
    function test_TakeSellOrderFailsIfTooMuch() public {
        depositSellOrder(acc[1], 20, 110);
        assertEq(book.outable(1, 21 * WAD), false);
        vm.expectRevert("Too much assets taken");
        take(acc[2], 1, 21);
    }

    // taking of buy order correctly adjusts external balances
    function test_TakeBuyOrderCheckBalances() public {
        depositBuyOrder(acc[1], 1800, 90);
        uint256 contractQuoteBalance = quoteToken.balanceOf(address(book));
        uint256 makerQuoteBalance = quoteToken.balanceOf(acc[1]);
        uint256 makerBaseBalance = baseToken.balanceOf(acc[1]);
        uint256 takerQuoteBalance = quoteToken.balanceOf(acc[2]);
        uint256 takerBaseBalance = baseToken.balanceOf(acc[2]);
        take(acc[2], 1, 1800);
        assertEq(quoteToken.balanceOf(address(book)), contractQuoteBalance - 1800 * WAD);
        assertEq(quoteToken.balanceOf(acc[1]), makerQuoteBalance);
        assertEq(baseToken.balanceOf(acc[1]), makerBaseBalance + 20 * WAD);
        assertEq(quoteToken.balanceOf(acc[2]), takerQuoteBalance + 1800 * WAD);
        assertEq(baseToken.balanceOf(acc[2]), takerBaseBalance - 20 * WAD);
    }

    // taking of sell order correctly adjusts external balances
    function test_TakeSellOrderCheckBalances() public {
        depositSellOrder(acc[1], 20, 110);
        uint256 contractBaseBalance = baseToken.balanceOf(address(book));
        uint256 makerBaseBalance = baseToken.balanceOf(acc[1]);
        uint256 makerQuoteBalance = quoteToken.balanceOf(acc[1]);
        uint256 takerBaseBalance = baseToken.balanceOf(acc[2]);
        uint256 takerQuoteBalance = quoteToken.balanceOf(acc[2]);
        take(acc[2], 1, 20);
        assertEq(baseToken.balanceOf(address(book)), contractBaseBalance - 20 * WAD);
        assertEq(baseToken.balanceOf(acc[1]), makerBaseBalance);
        assertEq(quoteToken.balanceOf(acc[1]), makerQuoteBalance + 20 * 110 * WAD);
        assertEq(baseToken.balanceOf(acc[2]), takerBaseBalance + 20 * WAD);
        assertEq(quoteToken.balanceOf(acc[2]), takerQuoteBalance - 20 * 110 * WAD);
    }

    // taking of buy order by maker herself correctly adjusts external balances
    function test_MakerTakesBuyOrderCheckBalances() public {
        depositBuyOrder(acc[1], 1800, 90);
        uint256 contractQuoteBalance = quoteToken.balanceOf(address(book));
        uint256 makerQuoteBalance = quoteToken.balanceOf(acc[1]);
        uint256 makerBaseBalance = baseToken.balanceOf(acc[1]);
        take(acc[1], 1, 900);
        assertEq(quoteToken.balanceOf(address(book)), contractQuoteBalance - 900 * WAD);
        assertEq(quoteToken.balanceOf(acc[1]), makerQuoteBalance + 900 * WAD);
        assertEq(baseToken.balanceOf(acc[1]), makerBaseBalance);
    }

}
