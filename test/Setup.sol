// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import {Test, console} from "../lib/forge-std/src/Test.sol";
import {Token} from "../src/Token.sol";
import {Book} from "../src/Book.sol";
//import {MathLib, WAD} from "../lib/MathLib.sol";
import {DeployBook} from "../script/DeployBook.s.sol";
import {StdCheats} from "../lib/forge-std/src/StdCheats.sol";

contract Setup is StdCheats, Test {
    Book public book;
    Token public baseToken;
    Token public quoteToken;
    DeployBook public deployBook;

    bool constant public buyOrder = true;
    bool constant public sellOrder = false;
    bool constant public inQuoteToken = true;
    bool constant public inBaseToken = false;

    uint256 constant public accountNumber = 5;
    uint256 constant public receiveQuoteToken = 10000;
    uint256 constant public receiveBaseToken = 100;

    uint256 testNumber = 42;

    mapping(uint256 => address) public acc;

    function setUp() public {
        deployBook = new DeployBook();
        (book, quoteToken, baseToken) = deployBook.run();
        fundingAccounts(accountNumber);
    }
    
    // funding an army of traders
    function fundingAccounts(uint256 _accountNumber) public {
        for (uint8 i = 0; i < _accountNumber; i++) {
            acc[i] = makeAddr(vm.toString(i));
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

    function checkBorrowingQuantity(uint256 _positionId, uint256 _quantity) public {
        (,, uint256 quantity) = book.positions(_positionId);
        assertEq(quantity, _quantity);
    }
    
    function checkUserDepositId(address _user, uint256 _row, uint256 _orderId) public {
        assertEq(book.getUserDepositIds(_user)[_row], _orderId);
    }

    function checkUserBorrowId(address _user, uint256 _row, uint256 _orderId) public {
        assertEq(book.getUserBorrowFromIds(_user)[_row], _orderId);
    }
    

}
