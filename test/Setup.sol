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

    uint256 constant public accountNumber = 10;
    uint256 constant public receiveQuoteToken = 10000;
    uint256 constant public receiveBaseToken = 100;

    mapping(uint256 => address) public acc;

    function setUp() public {
        deployBook = new DeployBook();
        (book, quoteToken, baseToken) = deployBook.run();
        createAccounts();
        initialTransfers();
    }

    function createAccounts() public {
        for (uint8 i = 0; i < accountNumber; i++) {
            acc[i] = makeAddr(vm.toString(i));
        }
    }
    
    // funding an army of traders
    function initialTransfers() public {
        for (uint8 i = 0; i < accountNumber; i++) {
            vm.startPrank(address(msg.sender)); // contract deployer
            quoteToken.transfer(acc[i], receiveQuoteToken);
            baseToken.transfer(acc[i], receiveBaseToken);
            vm.stopPrank();
            vm.startPrank(acc[i]);
            quoteToken.approve(address(book), receiveQuoteToken);
            baseToken.approve(address(book), receiveBaseToken);
            vm.stopPrank();
        }
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

    function withdraw(
        address _user,
        uint256 _orderId,
        uint256 _quantity
    ) public {
        vm.prank(_user);
        book.withdraw(_orderId, _quantity);
    }

    function take(
        address _user,
        uint256 _orderId,
        uint256 _quantity
    ) public {
        vm.prank(_user);
        book.take(_orderId, _quantity);
    }

    function repay(
        address _user,
        uint256 _orderId,
        uint256 _quantity
    ) public {
        vm.prank(_user);
        book.repay(_orderId, _quantity);
    }

    function borrow(
        address _user,
        uint256 _orderId,
        uint256 _quantity
    ) public {
        vm.prank(_user);
        book.borrow(_orderId, _quantity);
    }

    function testTransferTokenUSER() public {
        assertEq(receiveQuoteToken, quoteToken.balanceOf(acc[1]));
        assertEq(receiveBaseToken, baseToken.balanceOf(acc[1]));
    }

    function displayBalances(uint256 firstN) public view {
        console.log("Contract  QT: ", quoteToken.balanceOf(address(book)));
        console.log("Contract  BT: ", baseToken.balanceOf(address(book)));
        for (uint8 i = 0; i < firstN; i++) {
            console.log("Account", i, "QT: ", quoteToken.balanceOf(acc[i]));
            console.log("Account", i, "BT: ", baseToken.balanceOf(acc[i]));
        }
    }

    function checkOrderQuantity(uint256 _orderId, uint256 _quantity) public {
        (,, uint256 quantity,) = book.orders(_orderId);
        assertEq(quantity, _quantity);
    }

}
