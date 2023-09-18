// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Token} from "../src/Token.sol";
import {OrderBook} from "../src/OrderBook.sol";
import {DeployOrderBook} from "../script/DeployOrderBook.s.sol";
import {StdCheats} from "forge-std/StdCheats.sol";

contract OrderBookTest is StdCheats, Test {
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

    function testDeplyerBalances() public {
        assertEq(
            quoteToken.balanceOf(msg.sender),
            quoteToken.getInitialSupply() - 2 * SEND_QUOTE_QUANTITY
        );
        assertEq(
            baseToken.balanceOf(msg.sender),
            baseToken.getInitialSupply() - 2 * SEND_BASE_QUANTITY
        );
    }

    function testTransferTokenUSER() public {
        assertEq(SEND_QUOTE_QUANTITY, quoteToken.balanceOf(USER1));
    }

    function testPlaceBuyOrderFailsIfZeroDeposit() public {
        vm.prank(USER1);
        vm.expectRevert("placeOrder: Zero quantity is not allowed");
        orderBook.placeOrder(0, BUY_ORDER_PRICE, true);
    }

    function testPlaceSellOrderFailsIfZeroDeposit() public {
        vm.prank(USER1);
        vm.expectRevert("placeOrder: Zero quantity is not allowed");
        orderBook.placeOrder(0, SELL_ORDER_PRICE, false);
    }

    function testPlaceBuyOrderFailsIfZeroPrice() public {
        vm.prank(USER1);
        vm.expectRevert("placeOrder: Zero price is not allowed");
        orderBook.placeOrder(PLACE_QUOTE_QUANTITY, 0, true);
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

    function testPlaceOneBuyOrder() public placeOneBuyOrder {
        OrderBook.Order memory order = orderBook.getOrder(0);
        assertEq(order.maker, USER1);
        assertEq(order.isBuyOrder, true);
        assertEq(order.quantity, PLACE_QUOTE_QUANTITY);
        assertEq(order.price, BUY_ORDER_PRICE);
        assertEq(1, orderBook.getBookSize());
    }

    function testPlaceOneSellOrder() public placeOneSellOrder {
        OrderBook.Order memory order = orderBook.getOrder(0);
        assertEq(order.maker, USER1);
        assertEq(order.isBuyOrder, false);
        assertEq(order.quantity, PLACE_BASE_QUANTITY);
        assertEq(order.price, SELL_ORDER_PRICE);
        assertEq(1, orderBook.getBookSize());
    }

    function testPlaceOneBuyOrderCheckBalances() public {
        uint256 OrderBookBalance = quoteToken.balanceOf(address(orderBook));
        uint256 userBalance = quoteToken.balanceOf(USER1);
        vm.prank(USER1);
        orderBook.placeOrder(PLACE_QUOTE_QUANTITY, BUY_ORDER_PRICE, true);
        uint256 OrderBookBalanceAfter = quoteToken.balanceOf(
            address(orderBook)
        );
        uint256 userBalanceAfter = quoteToken.balanceOf(USER1);
        assertEq(
            OrderBookBalanceAfter,
            OrderBookBalance + PLACE_QUOTE_QUANTITY
        );
        assertEq(userBalanceAfter, userBalance - PLACE_QUOTE_QUANTITY);
    }

    function testPlaceOneSellOrderCheckBalances() public {
        uint256 OrderBookBalance = baseToken.balanceOf(address(orderBook));
        uint256 userBalance = baseToken.balanceOf(USER1);
        vm.prank(USER1);
        orderBook.placeOrder(PLACE_BASE_QUANTITY, SELL_ORDER_PRICE, false);
        uint256 OrderBookBalanceAfter = baseToken.balanceOf(address(orderBook));
        uint256 userBalanceAfter = baseToken.balanceOf(USER1);
        assertEq(OrderBookBalanceAfter, OrderBookBalance + PLACE_BASE_QUANTITY);
        assertEq(userBalanceAfter, userBalance - PLACE_BASE_QUANTITY);
    }

    function testPlaceTwoBuyOrders() public placeOneBuyOrder {
        vm.prank(USER2);
        orderBook.placeOrder(PLACE_QUOTE_QUANTITY, BUY_ORDER_PRICE, true);
        OrderBook.Order memory order = orderBook.getOrder(1);
        assertEq(order.maker, USER2);
        assertEq(order.isBuyOrder, true);
        assertEq(order.quantity, PLACE_QUOTE_QUANTITY);
        assertEq(order.price, BUY_ORDER_PRICE);
        assertEq(2, orderBook.getBookSize());
    }

    function testPlaceTwoOrders() public placeOneBuyOrder placeOneSellOrder {
        OrderBook.Order memory buyOrder = orderBook.getOrder(0);
        OrderBook.Order memory sellOrder = orderBook.getOrder(1);
        assertEq(buyOrder.maker, USER1);
        assertEq(buyOrder.isBuyOrder, true);
        assertEq(buyOrder.quantity, PLACE_QUOTE_QUANTITY);
        assertEq(buyOrder.price, BUY_ORDER_PRICE);
        assertEq(sellOrder.maker, USER1);
        assertEq(sellOrder.isBuyOrder, false);
        assertEq(sellOrder.quantity, PLACE_BASE_QUANTITY);
        assertEq(sellOrder.price, SELL_ORDER_PRICE);
        assertEq(2, orderBook.getBookSize());
    }

    function testRemoveBuyOrderFailsIfNotMaker() public placeOneBuyOrder {
        vm.prank(USER2);
        vm.expectRevert("removeOrder: Only maker can remove order");
        orderBook.removeOrder(0, PLACE_BASE_QUANTITY);
    }

    function testRemoveBuyOrder() public placeOneBuyOrder {
        vm.prank(USER1);
        orderBook.removeOrder(0, PLACE_QUOTE_QUANTITY);
        assertEq(1, orderBook.getBookSize());
    }

    function testRemoveBuyOrderCheckBalances() public placeOneBuyOrder {
        uint256 OrderBookBalance = quoteToken.balanceOf(address(orderBook));
        uint256 userBalance = quoteToken.balanceOf(USER1);
        vm.prank(USER1);
        orderBook.removeOrder(0, PLACE_QUOTE_QUANTITY);
        uint256 OrderBookBalanceAfter = quoteToken.balanceOf(
            address(orderBook)
        );
        uint256 userBalanceAfter = quoteToken.balanceOf(USER1);
        assertEq(OrderBookBalanceAfter, OrderBookBalance);
        assertEq(userBalanceAfter, userBalance);
    }

    function testRemoveThenReplaceBuyOrder() public placeOneBuyOrder {
        vm.prank(USER1);
        orderBook.removeOrder(0, PLACE_QUOTE_QUANTITY);
        vm.prank(USER2);
        orderBook.placeOrder(PLACE_QUOTE_QUANTITY, BUY_ORDER_PRICE, true);
        OrderBook.Order memory order = orderBook.getOrder(0);
        assertEq(order.maker, USER1);
        assertEq(2, orderBook.getBookSize());
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
