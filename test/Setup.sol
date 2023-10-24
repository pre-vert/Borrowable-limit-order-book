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

    address public USER1 = makeAddr("user1");
    address public USER2 = makeAddr("user2");
    address public USER3 = makeAddr("user3");

    function setUp() public {
        deployBook = new DeployBook();
        (book, quoteToken, baseToken) = deployBook.run();
        initialTransfers();
    }

    function initialTransfers() public {
        vm.startPrank(address(msg.sender)); // contract deployer
        quoteToken.transfer(USER1, 10000);
        quoteToken.transfer(USER2, 10000);
        baseToken.transfer(USER1, 100);
        baseToken.transfer(USER2, 100);
        vm.startPrank(USER1);
        quoteToken.approve(address(book), 10000);
        baseToken.approve(address(book), 100);
        vm.startPrank(USER2);
        quoteToken.approve(address(book), 10000);
        baseToken.approve(address(book), 100);
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

    function testDeployerBalances() public {
        assertEq(quoteToken.balanceOf(msg.sender), quoteToken.getInitialSupply() - 2 * 10000);
        assertEq(baseToken.balanceOf(msg.sender), baseToken.getInitialSupply() - 2 * 100);
    }

    function testTransferTokenUSER() public {
        assertEq(10000, quoteToken.balanceOf(USER1));
        assertEq(10000, quoteToken.balanceOf(USER2));
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
