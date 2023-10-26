// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Token} from "../src/Token.sol";
import {Book} from "../src/Book.sol";
//import {MathLib, WAD} from "../lib/MathLib.sol";
import {DeployBook} from "../script/DeployBook.s.sol";
import {StdCheats} from "forge-std/StdCheats.sol";

contract Setup is StdCheats, Test {
    Book public book;
    Token public baseToken;
    Token public quoteToken;
    DeployBook public deployBook;

    bool constant public buyOrder = true;
    bool constant public sellOrder = false;
    bool constant public inQuoteToken = true;
    bool constant public inBaseToken = false;

    uint256 constant public receiveQuoteToken = 10000;
    uint256 constant public receiveBaseToken = 100;

    address public USER1 = makeAddr("user1");
    address public USER2 = makeAddr("user2");
    address public USER3 = makeAddr("user3");
    address public USER4 = makeAddr("user4");
    address public USER5 = makeAddr("user5");
    address public USER6 = makeAddr("user6");
    address public USER7 = makeAddr("user7");
    address public USER8 = makeAddr("user8");

    function setUp() public {
        deployBook = new DeployBook();
        (book, quoteToken, baseToken) = deployBook.run();
        initialTransfers();
    }

    function initialTransfers() public {
        vm.startPrank(address(msg.sender)); // contract deployer
        quoteToken.transfer(USER1, receiveQuoteToken);
        quoteToken.transfer(USER2, receiveQuoteToken);
        quoteToken.transfer(USER3, receiveQuoteToken);
        quoteToken.transfer(USER4, receiveQuoteToken);
        quoteToken.transfer(USER5, receiveQuoteToken);
        quoteToken.transfer(USER6, receiveQuoteToken);
        quoteToken.transfer(USER7, receiveQuoteToken);
        quoteToken.transfer(USER8, receiveQuoteToken);
        baseToken.transfer(USER1, receiveBaseToken);
        baseToken.transfer(USER2, receiveBaseToken);
        baseToken.transfer(USER3, receiveBaseToken);
        baseToken.transfer(USER4, receiveBaseToken);
        baseToken.transfer(USER5, receiveBaseToken);
        baseToken.transfer(USER6, receiveBaseToken);
        baseToken.transfer(USER7, receiveBaseToken);
        baseToken.transfer(USER8, receiveBaseToken);
        vm.startPrank(USER1);
        quoteToken.approve(address(book), receiveQuoteToken);
        baseToken.approve(address(book), receiveBaseToken);
        vm.startPrank(USER2);
        quoteToken.approve(address(book), receiveQuoteToken);
        baseToken.approve(address(book), receiveBaseToken);
        vm.startPrank(USER3);
        quoteToken.approve(address(book), receiveQuoteToken);
        baseToken.approve(address(book), receiveBaseToken);
        vm.startPrank(USER4);
        quoteToken.approve(address(book), receiveQuoteToken);
        baseToken.approve(address(book), receiveBaseToken);
        vm.startPrank(USER5);
        quoteToken.approve(address(book), receiveQuoteToken);
        baseToken.approve(address(book), receiveBaseToken);
        vm.startPrank(USER6);
        quoteToken.approve(address(book), receiveQuoteToken);
        baseToken.approve(address(book), receiveBaseToken);
        vm.startPrank(USER7);
        quoteToken.approve(address(book), receiveQuoteToken);
        baseToken.approve(address(book), receiveBaseToken);
        vm.startPrank(USER8);
        quoteToken.approve(address(book), receiveQuoteToken);
        baseToken.approve(address(book), receiveBaseToken);
        vm.stopPrank();
    }

    function depositBuyOrder(
        address _user,
        uint256 _quantity,
        uint256 _price
    ) public {
        vm.prank(_user);
        book.deposit(_quantity, _price, buyOrder);
    }

    function depositSellOrder(
        address _user,
        uint256 _quantity,
        uint256 _price
    ) public {
        vm.prank(_user);
        book.deposit(_quantity, _price, sellOrder);
    }

    function borrowOrder(
        address _user,
        uint256 _orderId,
        uint256 _quantity
    ) public {
        vm.prank(_user);
        book.borrow(_orderId, _quantity);
    }

    function testDeployerBalances() public {
        assertEq(quoteToken.balanceOf(msg.sender), quoteToken.getInitialSupply() - 8 * receiveQuoteToken);
        assertEq(baseToken.balanceOf(msg.sender), baseToken.getInitialSupply() - 8 * receiveBaseToken);
    }

    function testTransferTokenUSER() public {
        assertEq(receiveQuoteToken, quoteToken.balanceOf(USER1));
        assertEq(receiveQuoteToken, quoteToken.balanceOf(USER2));
    }

    function displayBalances() public view {
        console.log("Contract QT: ", quoteToken.balanceOf(address(book)));
        console.log("Contract BT: ", baseToken.balanceOf(address(book)));
        console.log("USER1 QT: ", quoteToken.balanceOf(USER1));
        console.log("USER1 BT: ", baseToken.balanceOf(USER1));
        console.log("USER2 QT: ", quoteToken.balanceOf(USER2));
        console.log("USER2 BT: ", baseToken.balanceOf(USER2));
    }

}
