// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
//import "forge-std/console.sol";
import {Setup} from "./Setup.sol";
import {MathLib, WAD} from "../lib/MathLib.sol";

contract TestPool is Setup {

    // create first buy order seeds the genesis pool correctly
    function test_DepositBuyOrderCreatesPool() public depositBuy(LowPriceId) {
        console.log("block.timestamp: ", block.timestamp);
        (uint256 deposits,
        uint256 borrows,
        uint256 lastTimeStamp,
        uint256 timeWeightedRate,
        uint256 timeUrWeightedRate,
        uint256 topOrder,
        uint256 bottomOrder,
        uint256 topPosition,
        uint256 bottomPosition) = book.pools(LowPriceId);
        assertEq(deposits, DepositQT);
        assertEq(borrows, 0);
        assertEq(lastTimeStamp, 1);
        assertEq(timeWeightedRate, timeWeightedRate);
        assertEq(timeUrWeightedRate, timeUrWeightedRate);
        assertEq(topOrder, 1);
        assertEq(bottomOrder, 0);
        assertEq(topPosition, 0);
        assertEq(bottomPosition, 0);
        assertEq(book.limitPrice(LowPriceId), initialPriceWAD);
    }

    // create first sell order seeds the genesis pool correctly
    function test_DepositSellOrderCreatesPool() public setLowPrice() depositSell(FirstPoolId) {
        console.log("block.timestamp: ", block.timestamp);
        (uint256 deposits,
        uint256 borrows,
        uint256 lastTimeStamp,
        uint256 timeWeightedRate,
        uint256 timeUrWeightedRate,
        uint256 topOrder,
        uint256 bottomOrder,
        uint256 topPosition,
        uint256 bottomPosition) = book.pools(FirstPoolId);
        assertEq(deposits, DepositBT);
        assertEq(borrows, 0);
        assertEq(lastTimeStamp, 0); // check
        assertEq(timeWeightedRate, 0); // check
        assertEq(timeUrWeightedRate, 0); // check
        assertEq(topOrder, 1);
        assertEq(bottomOrder, 0);
        assertEq(topPosition, 0);
        assertEq(bottomPosition, 0);
        assertEq(book.limitPrice(LowPriceId), initialPriceWAD);
    }

    // create buy and sell order seeds second pool correctly
    function test_DepositBuySellOrderCreatesPool() public 
        depositBuy(LowPriceId) setLowPrice() depositSell(HighPriceId) {
        console.log("block.timestamp: ", block.timestamp);
        (uint256 deposits,
        uint256 borrows,
        uint256 lastTimeStamp,
        uint256 timeWeightedRate,
        uint256 timeUrWeightedRate,
        uint256 topOrder,
        uint256 bottomOrder,
        uint256 topPosition,
        uint256 bottomPosition) = book.pools(HighPriceId);
        assertEq(deposits, DepositBT);
        assertEq(borrows, 0);
        assertEq(lastTimeStamp, 0); // check
        assertEq(timeWeightedRate, 0); // check
        assertEq(timeUrWeightedRate, 0); // check
        assertEq(topOrder, 1);
        assertEq(bottomOrder, 0);
        assertEq(topPosition, 0);
        assertEq(bottomPosition, 0);
        assertEq(book.limitPrice(HighPriceId), initialPriceWAD + initialPriceWAD / 10);
    }

    // create sell then buy order seeds the second pool correctly
    function test_DepositSellBuyOrderCreatesPool() public 
        setLowPrice() depositSell(FirstPoolId) setHighPrice() depositBuy(FirstPoolId - 1) {
        (uint256 deposits,
        uint256 borrows,
        uint256 lastTimeStamp,
        uint256 timeWeightedRate,
        uint256 timeUrWeightedRate,
        uint256 topOrder,
        uint256 bottomOrder,
        uint256 topPosition,
        uint256 bottomPosition) = book.pools(FirstPoolId - 1);
        assertEq(deposits, DepositQT);
        assertEq(borrows, 0);
        assertEq(lastTimeStamp, 1);
        assertEq(timeWeightedRate, timeWeightedRate);
        assertEq(timeUrWeightedRate, timeUrWeightedRate);
        assertEq(topOrder, 1);
        assertEq(bottomOrder, 0);
        assertEq(topPosition, 0);
        assertEq(bottomPosition, 0);
        assertEq(book.limitPrice(FirstPoolId - 1), 10 * initialPriceWAD / 11);
    }

    // create first order sets the last time stamp correctly
    function test_SetTimeStampCorrectly() public {
        vm.warp(10); // sets block.timestamp
        depositBuyOrder(Alice, LowPriceId, DepositQT, HighPriceId);
        console.log("block.timestamp: ", block.timestamp);
        (,,uint256 lastTimeStamp,,,,,,) = book.pools(0);
        assertEq(lastTimeStamp, 10);
    }

    
}
