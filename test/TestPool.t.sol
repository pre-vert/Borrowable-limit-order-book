// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
//import "forge-std/console.sol";
import {Setup} from "./Setup.sol";
import {MathLib, WAD} from "../lib/MathLib.sol";

contract TestPool is Setup {

    // deposit first buy order seeds the genesis pool correctly
    // GenPoolId is id of first buy order pool ever created, since 1,000,000,000 is even
    // First sell order pool is GenPoolId + 1
    // As a result the limit price of the buy order pool is 2000

    function test_DepositBuyOrderCreatesPool() public depositBuy(B) {
        console.log("block.timestamp: ", block.timestamp);
        (uint256 deposits,
        uint256 borrows,
        uint256 lastTimeStamp,
        uint256 timeWeightedRate,
        uint256 timeUrWeightedRate,
        uint256 topOrder,
        uint256 bottomOrder,
        uint256 topPosition,
        uint256 bottomPosition) = book.pools(B);
        assertEq(deposits, DepositQT);
        assertEq(borrows, 0);
        assertEq(lastTimeStamp, 1);
        assertEq(timeWeightedRate, timeWeightedRate);
        assertEq(timeUrWeightedRate, timeUrWeightedRate);
        assertEq(topOrder, 1);
        assertEq(bottomOrder, 0);
        assertEq(topPosition, 0);
        assertEq(bottomPosition, 0);
        assertEq(book.limitPrice(B), genesisLimitPriceWAD);
    }

    // deposit first sell order seeds the genesis pool correctly
    // market price set initially at 2001
    // set low price at 1980, then limit price of first sell order at 2000

    function test_DepositSellOrderCreatesPool() public setLowPrice() depositSell(B + 1) {
        console.log("block.timestamp: ", block.timestamp);
        (uint256 deposits,
        uint256 borrows,
        uint256 lastTimeStamp,
        uint256 timeWeightedRate,
        uint256 timeUrWeightedRate,
        uint256 topOrder,
        uint256 bottomOrder,
        uint256 topPosition,
        uint256 bottomPosition) = book.pools(B + 1);
        assertEq(deposits, DepositBT);
        assertEq(borrows, 0);
        assertEq(lastTimeStamp, 0); 
        assertEq(timeWeightedRate, 0);
        assertEq(timeUrWeightedRate, 0);
        assertEq(topOrder, 1);
        assertEq(bottomOrder, 0);
        assertEq(topPosition, 0);
        assertEq(bottomPosition, 0);
        assertEq(book.limitPrice(B + 1), genesisLimitPriceWAD);
    }

    // create first order sets the last time stamp correctly
    function test_SetTimeStampCorrectly() public {
        vm.warp(10);           // sets block.timestamp
        depositBuyOrder(Alice, B, DepositQT, B + 1);
        (,,uint256 lastTimeStamp,,,,,,) = book.pools(B);
        assertEq(lastTimeStamp, 10);
    }

    // deposit first buy order + 2 seeds the genesis pool correctly
    // market price = 4001; limit price of pool + 2 is 4400
    
    function test_DepositBuyPlusTwoCreatesPool() public {
        setPriceFeed(4401);
        depositBuyOrder(Alice, B + 2, DepositQT, B + 3);
        assertEq(book.limitPrice(B + 2), genesisLimitPriceWAD + genesisLimitPriceWAD / 10);
    }

    // deposit buy and sell order seeds second pool correctly
    // initial market price 2001 => deposit buy order at 2000
    // then deposit sell order at 2200
    // set market price at 1980 => setLowPrice()

    function test_DepositBuySellOrderCreatesPool() public 
        depositBuy(B) setLowPrice() depositSell(B + 3) {
        assertEq(book.limitPrice(B + 3), genesisLimitPriceWAD + genesisLimitPriceWAD / 10);
    }

    // deposit sell and buy order seeds second pool correctly
    // initial market price 2001 => deposit buy order at 2000
    // then deposit sell order at 2200
    // set market price at 1980 => setLowPrice()

    function test_DepositSellBuyOrderCreatesPool() public 
        setLowPrice() depositSell(B + 1) setHighPrice() depositBuy(B) {
        assertEq(book.limitPrice(B), genesisLimitPriceWAD);
    }

    function test_DepositSellBuyOrderPlusUnCreatesPool() public 
        setLowPrice() depositSell(B + 1) setUltraHighPrice() depositBuy(B + 2) {
        assertEq(book.limitPrice(B), genesisLimitPriceWAD);
    }

    // deposit buy order below genesis limit price seeds the pool correctly
    function test_DepositBuyBelowCreatesPool() public depositBuy(B - 2) {
        assertEq(book.limitPrice(B - 2), 10 * genesisLimitPriceWAD / 11);
    }

    // deposit sell order above genesis limit price seeds the pool correctly
    function test_DepositSellAboveCreatesPool() public setLowPrice() depositSell(B + 3) {
        assertEq(book.limitPrice(B + 3), genesisLimitPriceWAD + genesisLimitPriceWAD / 10);
    }

    // deposit buy order 2 times above genesis limit price seeds the pool correctly
    function test_DepositBuyAboveTwiceCreatesPool() public {
        setPriceFeed(5000);
        depositBuyOrder(Alice, B + 4, DepositQT, B + 5);
        uint256 intPrice = genesisLimitPriceWAD + genesisLimitPriceWAD / 10;
        assertEq(book.limitPrice(B + 4), intPrice + intPrice / 10);
    }
    
    // deposit buy order 2 times below genesis limit price seeds the pool correctly
    function test_DepositBuyBelowTwiceCreatesPool() public depositBuy(B - 4) {
        uint256 intPrice = 10 * genesisLimitPriceWAD / 11;
        assertEq(book.limitPrice(B - 4), 10 * intPrice / 11);
    }

    // deposit sell order twice above genesis limit price seeds the pool correctly
    function test_DepositSellAboveTwiceCreatesPool() public setLowPrice() depositSell(B + 5) {
        uint256 intPrice = genesisLimitPriceWAD + genesisLimitPriceWAD / 10;
        assertEq(book.limitPrice(B + 5), intPrice + intPrice / 10);
    }

    // deposit sell order 3x above genesis limit price reverts
    function test_DepositBuyBelowThriceReverts() public {
        vm.expectRevert("Limit price too far");
        depositBuyOrder(Alice, B + 6, DepositQT, B + 7);
    }
    
    // deposit sell order 3x above genesis limit price reverts
    function test_DepositSellAboveThriceReverts() public setLowPrice() {
        vm.expectRevert("Limit price too far");
        depositSellOrder(Alice, B + 7, DepositQT, B + 6);
    }
}
