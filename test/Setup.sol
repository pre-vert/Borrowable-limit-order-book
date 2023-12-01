// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import {Test, console} from "../lib/forge-std/src/Test.sol";
import {Token} from "../src/Token.sol";
import {Book} from "../src/Book.sol";
import {DeployBook} from "../script/DeployBook.s.sol";
import {StdCheats} from "../lib/forge-std/src/StdCheats.sol";
import {MathLib, WAD} from "../lib/MathLib.sol";

contract Setup is StdCheats, Test {
    Book public book;
    Token public baseToken;
    Token public quoteToken;
    DeployBook public deployBook;

    bool constant public BuyOrder = true;
    bool constant public SellOrder = false;
    bool constant public InQuoteToken = true;
    bool constant public InBaseToken = false;
    // uint256 constant public Alpha = book.ALPHA();
    // uint256 constant public Beta = book.BETA();
    // uint256 constant public Gamma = book.GAMMA();

    uint256 constant public AccountNumber = 4;
    uint256 constant public ReceivedQuoteToken = 10000 * WAD;
    uint256 constant public ReceivedBaseToken = 100 * WAD;
    uint256 public constant YEAR = 365 days; // number of seconds in one year
    uint256 constant public DAY = 1 days; // number of seconds in one day

    address OrderBook;
    address Alice;
    address Bob;
    address Carol;
    address Dave;
    address PoorGuy;
    uint256 constant No_Order = 0;
    uint256 constant Alice_Order = 1;
    uint256 constant Bob_Order = 2;
    uint256 constant Carol_Order = 3;
    uint256 constant Dave_Order = 4;
    uint256 constant Alice_Position = 1;
    uint256 constant Bob_Position = 1;
    uint256 constant Carol_Position = 2;

    mapping(uint256 => address) public acc;

    function setUp() public {
        deployBook = new DeployBook();
        (book, quoteToken, baseToken) = deployBook.run();
        fundingAccounts(AccountNumber);
    }
    
    // funding an army of traders
    function fundingAccounts(uint256 _accountNumber) public {
        for (uint8 i = 1; i <= _accountNumber; i++) {
            _receiveTokens(i, ReceivedQuoteToken, ReceivedBaseToken);
            _allowTokens(i, ReceivedQuoteToken, ReceivedBaseToken);
        }
        _receiveTokens(_accountNumber + 1, ReceivedQuoteToken / 5, ReceivedBaseToken / 5);
        _allowTokens(_accountNumber + 1, ReceivedQuoteToken, ReceivedBaseToken);
        OrderBook = address(book);
        Alice = acc[1];
        Bob = acc[2];
        Carol = acc[3];
        Dave = acc[4];
        PoorGuy = acc[_accountNumber + 1];
    }

    function _receiveTokens(uint256 _userId, uint256 _quoteTokens, uint256 _baseTokens) internal {
        acc[_userId] = makeAddr(vm.toString(_userId));
        vm.startPrank(address(msg.sender)); // contract deployer
        quoteToken.transfer(acc[_userId], _quoteTokens);
        baseToken.transfer(acc[_userId], _baseTokens);
        vm.stopPrank();
    }

    function _allowTokens(uint256 _userId, uint256 _quoteTokens, uint256 _baseTokens) internal {
        vm.startPrank(acc[_userId]);
        quoteToken.approve(address(book), _quoteTokens);
        baseToken.approve(address(book), _baseTokens);
        vm.stopPrank();
    }

    function depositBuyOrder(address _user, uint256 _quantity, uint256 _price) public {
        vm.prank(_user);
        book.deposit(_quantity * WAD, _price * WAD, BuyOrder);
    }

    function depositSellOrder(address _user, uint256 _quantity, uint256 _price) public {
        vm.prank(_user);
        book.deposit(_quantity * WAD, _price * WAD, SellOrder);
    }

    function withdraw(address _user, uint256 _orderId, uint256 _quantity) public {
        vm.prank(_user);
        book.withdraw(_orderId, _quantity * WAD);
    }

    function take(address _user, uint256 _orderId, uint256 _quantity) public {
        vm.prank(_user);
        book.take(_orderId, _quantity * WAD);
    }

    function repay(address _user, uint256 _positionId, uint256 _quantity) public {
        vm.prank(_user);
        book.repay(_positionId, _quantity * WAD);
    }

    function borrow(address _user, uint256 _orderId, uint256 _quantity) public {
        vm.prank(_user);
        book.borrow(_orderId, _quantity * WAD);
    }

    function liquidate(address _user, uint256 _positionId) public {
        vm.prank(_user);
        book.liquidate(_positionId);
    }

    function setPriceFeed(uint256 _price) public {
        book.setPriceFeed(_price * WAD);
    }

    // check assets in order == _quantity
    function checkOrderQuantity(uint256 _orderId, uint256 _quantity) public {
        (,, uint256 quantity,) = book.orders(_orderId);
        assertEq(quantity, _quantity * WAD);
        console.log("order quantity: ", quantity / WAD);
    }

    // check assets borrowed in position = _quantity
    function checkBorrowingQuantity(uint256 _positionId, uint256 _quantity) public {
        (,, uint256 quantity,) = book.positions(_positionId);
        assertEq(quantity, _quantity * WAD);
        console.log("borrowing quantity: ", quantity / WAD);
    }

    function checkOrderPositionId(uint256 _orderId, uint256 _row, uint256 _positionId) public {
        assertEq(book.getOrderPositionIds(_orderId)[_row], _positionId);
    }
    
    function checkUserDepositId(address _user, uint256 _row, uint256 _orderId) public {
        assertEq(book.getUserDepositIds(_user)[_row], _orderId);
    }

    function checkUserBorrowId(address _user, uint256 _row, uint256 _orderId) public {
        assertEq(book.getUserBorrowFromIds(_user)[_row], _orderId);
    }

    function checkInstantRate(bool _isBuyOrder) public {
        uint256 annualRate = book.ALPHA() +
            book.BETA() * book.getUtilizationRate(_isBuyOrder) / WAD +
            book.GAMMA() * book.getUtilizationRate(!_isBuyOrder) / WAD;
        assertEq(book.getInstantRate(_isBuyOrder), annualRate / YEAR);
        if (_isBuyOrder) {
            console.log("Utilization rate in buy order market (1e04): ", book.getUtilizationRate(_isBuyOrder) * 1e4 / WAD);
            console.log("Annualized rate in buy order market (1e05): ", book.getInstantRate(_isBuyOrder) * 1e5 * YEAR / WAD);
        }
        else {
            console.log("Utilization rate in sell order market (1e04): ", book.getUtilizationRate(_isBuyOrder) * 1e4 / WAD);
            console.log("Annualized rate in sell order market (1e05): ", book.getInstantRate(_isBuyOrder) * 1e5 * YEAR / WAD);
        }
    }
    

}
