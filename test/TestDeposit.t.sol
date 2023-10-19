// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Token} from "../src/Token.sol";
import {OrderBook} from "../src/OrderBook.sol";
import {DeployOrderBook} from "../script/DeployOrderBook.s.sol";
import {StdCheats} from "forge-std/StdCheats.sol";

contract TestDeposit is StdCheats, Test {
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

    function testDeployerBalances() public {
        assertEq(quoteToken.balanceOf(msg.sender), quoteToken.getInitialSupply() - 2 * SEND_QUOTE_QUANTITY);
        assertEq(baseToken.balanceOf(msg.sender), baseToken.getInitialSupply() - 2 * SEND_BASE_QUANTITY);
    }

    function testTransferTokenUSER() public {
        assertEq(SEND_QUOTE_QUANTITY, quoteToken.balanceOf(USER1));
        assertEq(SEND_QUOTE_QUANTITY, quoteToken.balanceOf(USER2));
    }

    function testDepositFailsIfZeroDeposit() public {
        vm.prank(USER1);
        vm.expectRevert("Must be positive");
        orderBook.deposit(0, BUY_ORDER_PRICE, true);
        vm.expectRevert("Must be positive");
        orderBook.deposit(0, BUY_SELL_PRICE, false);
    }

    function testDepositFailsIfZeroPrice() public {
        vm.prank(USER1);
        vm.expectRevert("Must be positive");
        orderBook.deposit(PLACE_QUOTE_QUANTITY, 0, true);
        vm.expectRevert("Must be positive");
        orderBook.deposit(PLACE_QUOTE_QUANTITY, 0, false);
    }

    modifier depositOneBuyOrder() {
        vm.prank(USER1);
        orderBook.deposit(PLACE_QUOTE_QUANTITY, BUY_ORDER_PRICE, true);
        _;
    }

    modifier depositOneSellOrder() {
        vm.prank(USER1);
        orderBook.deposit(PLACE_BASE_QUANTITY, SELL_ORDER_PRICE, false);
        _;
    }

    function testDepositOneBuyOrder() public depositOneBuyOrder {
        OrderBook.Order memory order = orderBook.orders[1];
        assertEq(order.quantity, PLACE_QUOTE_QUANTITY);
        assertEq(order.price, BUY_ORDER_PRICE);
        assertEq(order.isBuyOrder, true);
        assertEq(order.maker, USER1);
    }

    function testDepositOneSellOrder() public depositOneSellOrder {
        OrderBook.Order memory order = orderBook.orders[1];
        assertEq(order.quantity, PLACE_BASE_QUANTITY);
        assertEq(order.price, SELL_ORDER_PRICE);
        assertEq(order.isBuyOrder, false);
        assertEq(order.maker, USER1);
    }

    function testDepositOneBuyOrderCheckBalances() public {
        uint256 OrderBookBalance = quoteToken.balanceOf(address(orderBook));
        uint256 userBalance = quoteToken.balanceOf(USER1);
        vm.prank(USER1);
        orderBook.deposit(PLACE_QUOTE_QUANTITY, BUY_ORDER_PRICE, true);
        uint256 OrderBookBalanceAfter = quoteToken.balanceOf(address(orderBook));
        uint256 userBalanceAfter = quoteToken.balanceOf(USER1);
        assertEq(OrderBookBalanceAfter, OrderBookBalance + PLACE_QUOTE_QUANTITY);
        assertEq(userBalanceAfter, userBalance - PLACE_QUOTE_QUANTITY);
    }

    function testDepositOneSellOrderCheckBalances() public {
        uint256 OrderBookBalance = baseToken.balanceOf(address(orderBook));
        uint256 userBalance = baseToken.balanceOf(USER1);
        vm.prank(USER1);
        orderBook.deposit(PLACE_BASE_QUANTITY, SELL_ORDER_PRICE, false);
        uint256 OrderBookBalanceAfter = baseToken.balanceOf(address(orderBook));
        uint256 userBalanceAfter = baseToken.balanceOf(USER1);
        assertEq(OrderBookBalanceAfter, OrderBookBalance + PLACE_BASE_QUANTITY);
        assertEq(userBalanceAfter, userBalance - PLACE_BASE_QUANTITY);
    }

    function testDepositTwoBuyOrders()
        public
        depositOneBuyOrder
    {
        vm.prank(USER2);
        orderBook.deposit(PLACE_QUOTE_QUANTITY, BUY_ORDER_PRICE, true);
        OrderBook.Order memory order = orderBook.orders[2];
        assertEq(order.quantity, PLACE_QUOTE_QUANTITY);
        assertEq(order.price, BUY_ORDER_PRICE);
        assertEq(order.isBuyOrder, true);
        assertEq(order.maker, USER2);
    }

    function testDepositTwoOrders() 
        public
        depositOneBuyOrder
        depositOneSellOrder
    {
        OrderBook.Order memory buyOrder = orderBook.orders[1];
        OrderBook.Order memory sellOrder = orderBook.orders[2];
        assertEq(buyOrder.quantity, PLACE_QUOTE_QUANTITY);
        assertEq(buyOrder.price, BUY_ORDER_PRICE);
        assertEq(buyOrder.isBuyOrder, true);
        assertEq(buyOrder.maker, USER1);
        assertEq(sellOrder.quantity, PLACE_BASE_QUANTITY);
        assertEq(sellOrder.price, SELL_ORDER_PRICE);
        assertEq(sellOrder.isBuyOrder, false);
        assertEq(sellOrder.maker, USER1);
    }
}
