// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Token} from "../src/Token.sol";
import {OrderBook} from "../src/OrderBook.sol";
import {DeployOrderBook} from "../script/DeployOrderBook.s.sol";
import {StdCheats} from "forge-std/StdCheats.sol";

contract TestTakeOrder is StdCheats, Test {
    OrderBook public orderBook;
    Token public baseToken;
    Token public quoteToken;
    DeployOrderBook public deployOrderBook;

    address public USER1 = makeAddr("user1");
    address public USER2 = makeAddr("user2");
    uint256 constant SEND_QUOTE_QUANTITY = 10000;
    uint256 constant APPROVE_QUOTE_QUANTITY = 5000;
    uint256 constant PLACE_QUOTE_QUANTITY = 3000;
    uint256 constant SEND_BASE_QUANTITY = 100;
    uint256 constant APPROVE_BASE_QUANTITY = 50;
    uint256 constant PLACE_BASE_QUANTITY = 30;
    uint256 constant CURRENT_PRICE = 100; // 1 baseToken = 100 quoteToken
    uint256 constant BUY_ORDER_PRICE = 90;
    uint256 constant SELL_ORDER_PRICE = 110;

    function setUp() public {
        deployOrderBook = new DeployOrderBook();
        (orderBook, quoteToken, baseToken) = deployOrderBook.run();

        vm.prank(address(msg.sender)); // contract deployer
        quoteToken.transfer(USER1, SEND_QUOTE_QUANTITY);
        vm.prank(address(msg.sender));
        quoteToken.transfer(USER2, SEND_QUOTE_QUANTITY);
        vm.prank(address(msg.sender));
        baseToken.transfer(USER1, SEND_BASE_QUANTITY);
        vm.prank(address(msg.sender));
        baseToken.transfer(USER2, SEND_BASE_QUANTITY);
        vm.prank(USER1);
        quoteToken.approve(address(orderBook), APPROVE_QUOTE_QUANTITY);
        vm.prank(USER2);
        quoteToken.approve(address(orderBook), APPROVE_QUOTE_QUANTITY);
        vm.prank(USER1);
        baseToken.approve(address(orderBook), APPROVE_BASE_QUANTITY);
        vm.prank(USER2);
        baseToken.approve(address(orderBook), APPROVE_BASE_QUANTITY);
    }

    modifier placeOneBuyOrder() {
        vm.prank(USER1);
        orderBook.placeOrder(PLACE_QUOTE_QUANTITY, BUY_ORDER_PRICE, true);
        _;
    }

    modifier placeOneSellOrder() {
        vm.prank(USER1);
        orderBook.placeOrder(PLACE_BASE_QUANTITY, SELL_ORDER_PRICE, false);
        _;
    }

    function testTakeBuyOrder() public placeOneBuyOrder {
        vm.prank(USER2);
        orderBook.takeOrder(0, PLACE_QUOTE_QUANTITY);
        assertEq(0, orderBook.getBookSize());
    }

    function testTakeBuyOrderCheckBalances() public placeOneBuyOrder {
        uint256 makerQuoteBalance = quoteToken.balanceOf(USER1);
        uint256 makerBaseBalance = baseToken.balanceOf(USER1);
        uint256 takerQuoteBalance = quoteToken.balanceOf(USER2);
        uint256 takerBaseBalance = baseToken.balanceOf(USER2);
        vm.prank(USER2);
        orderBook.takeOrder(0, PLACE_QUOTE_QUANTITY);
        uint256 makerQuoteBalanceAfter = quoteToken.balanceOf(USER1);
        uint256 makerBaseBalanceAfter = baseToken.balanceOf(USER1);
        uint256 takerQuoteBalanceAfter = quoteToken.balanceOf(USER2);
        uint256 takerBaseBalanceAfter = baseToken.balanceOf(USER2);
        assertEq(makerQuoteBalanceAfter, makerQuoteBalance);
        assertEq(
            makerBaseBalanceAfter,
            makerBaseBalance + PLACE_QUOTE_QUANTITY / BUY_ORDER_PRICE
        );
        assertEq(
            takerQuoteBalanceAfter,
            takerQuoteBalance + PLACE_QUOTE_QUANTITY
        );
        assertEq(
            takerBaseBalanceAfter,
            takerBaseBalance - PLACE_QUOTE_QUANTITY / BUY_ORDER_PRICE
        );
    }
}
