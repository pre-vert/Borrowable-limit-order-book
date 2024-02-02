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
    uint256 initialPrice;
    DeployBook public deployBook;

    bool constant public BuyOrder = true;
    bool constant public SellOrder = false;
    bool constant public InQuoteToken = true;
    bool constant public InBaseToken = false;
    // bool constant public IsBorrowable = true;
    // bool constant public IsNonBorrowable = false;
    uint256 constant public AccountNumber = 27;
    uint256 constant public ReceivedQuoteToken = 20000 * WAD;
    uint256 constant public ReceivedBaseToken = 200 * WAD;
    uint256 constant public YEAR = 365 days; // number of seconds in one year
    uint256 constant public DAY = 1 days; // number of seconds in one day
    uint256 constant No_Order = 0;
    uint256 constant Alice_Order = 1;
    uint256 constant Bob_Order = 2;
    uint256 constant Carol_Order = 3;
    uint256 constant Dave_Order = 4;
    uint256 constant Alice_Position = 1;
    uint256 constant Bob_Position = 1;
    uint256 constant Carol_Position = 2;
    uint256 constant DepositQT = 1800;
    uint256 constant DepositBT = 20;
    uint256 constant TakeQT = 900;
    uint256 constant TakeBT = 10;
    int24 constant UltraLowPrice = -2;
    int24 constant VeryLowPrice = -1;
    int24 constant LowPrice = 0;
    int24 constant HighPrice = 1;
    int24 constant VeryHighPrice = 2;
    int24 constant UltraHighPrice = 3;

    address OrderBook;
    address Alice;
    address Bob;
    address Carol;
    address Dave;

    mapping(uint256 => address) public acc;

    function setUp() public {
        deployBook = new DeployBook();
        (book, quoteToken, baseToken, initialPrice) = deployBook.run();
        // book.limitPrice[0] = initialPrice;
        fundingAccounts(AccountNumber);
    }
    
    // funding an army of traders
    function fundingAccounts(uint256 _accountNumber) public {
        for (uint8 i = 1; i <= _accountNumber; i++) {
            _receiveTokens(i, ReceivedQuoteToken, ReceivedBaseToken);
            _allowTokens(i, 2 * ReceivedQuoteToken, 2 * ReceivedBaseToken);
        }
        OrderBook = address(book);
        Alice = acc[1];
        Bob = acc[2];
        Carol = acc[3];
        Dave = acc[4];
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

    function depositBuyOrder(
        address _user,
        int24 _poolId,
        uint256 _quantity,
        int24 _pairedPoolId
    ) public {
        vm.prank(_user);
        book.deposit( _poolId, _quantity * WAD, _pairedPoolId, BuyOrder);
    }

    function depositSellOrder(
        address _user,
        int24 _poolId,
        uint256 _quantity,
        int24 _pairedPoolId
    ) public {
        vm.prank(_user);
        book.deposit(_poolId, _quantity * WAD, _pairedPoolId, SellOrder);
    }

    // function depositBuyOrderWithPairedPrice(
    //     address _user,
    //     uint256 _quantity,
    //     uint256 _price,
    //     uint256 _pairedPrice
    // ) public {
    //     vm.prank(_user);
    //     book.deposit(_quantity * WAD, _price * WAD, _pairedPrice * WAD, BuyOrder);
    // }

    // function depositSellOrderWithPairedPrice(
    //     address _user,
    //     uint256 _quantity,
    //     uint256 _price,
    //     uint256 _pairedPrice
    //     ) public {
    //     vm.prank(_user);
    //     book.deposit(_quantity * WAD, _price * WAD, _pairedPrice * WAD, SellOrder, IsBorrowable);
    // }

    function withdraw(address _user, uint256 _orderId, uint256 _quantity) public {
        vm.prank(_user);
        book.withdraw(_orderId, _quantity * WAD);
    }

    function borrow(address _user, int24 _poolId, uint256 _quantity) public {
        vm.prank(_user);
        book.borrow(_poolId, _quantity * WAD);
    }
    
    function repay(address _user, uint256 _positionId, uint256 _quantity) public {
        vm.prank(_user);
        book.repay(_positionId, _quantity * WAD);
    }

    function take(address _user, int24 _poolId, uint256 _quantity) public {
        vm.prank(_user);
        book.take(_poolId, _quantity * WAD);
    }

    function liquidateBorrower(address _user, uint256 _quantity) public {
        vm.prank(_user);
        book.liquidateBorrower(_user, _quantity);
    }

    function setPriceFeed(uint256 _price) public {
        book.setPriceFeed(_price * WAD);
    }

    // check maker of order
    function checkOrderMaker(uint256 _orderId, address _maker) public {
        (, address maker,,,,) = book.orders(_orderId);
        assertEq(maker, _maker);
    }

    // check assets in order == _quantity
    function checkOrderQuantity(uint256 _orderId, uint256 _quantity) public {
        (,,, uint256 quantity,,) = book.orders(_orderId);
        assertEq(quantity, _quantity * WAD);
    }

    // check limit price in order
    function checkPoolId(uint256 _orderId, int24 _poolId) public {
        (int24 poolId,,,,,) = book.orders(_orderId);
        assertEq(poolId, _poolId);
    }

    // check paired pool id in order
    function checkOrderPairedPrice(uint256 _orderId, int24 _pairedPoolId) public {
        (,, int24 pairedPoolId,,,) = book.orders(_orderId);
        assertEq(pairedPoolId, _pairedPoolId);
    }

    // check assets borrowed in position = _quantity
    function checkBorrowingQuantity(uint256 _positionId, uint256 _quantity) public {
        (,, uint256 quantity,) = book.positions(_positionId);
        assertEq(quantity, _quantity * WAD);
    }
    
    function checkUserDepositId(address _user, uint256 _row, uint256 _orderId) public {
        assertEq(book.getUserDepositIds(_user)[_row], _orderId);
    }

    function checkUserBorrowId(address _user, uint256 _row, uint256 _orderId) public {
        assertEq(book.getUserBorrowFromIds(_user)[_row], _orderId);
    }

    function checkInstantRate(int24 _poolId) public {
        uint256 annualRate = book.ALPHA() + book.BETA() * book.getUtilizationRate(_poolId) / WAD;
        assertEq(book.getInstantRate(_poolId), annualRate / YEAR);
        console.log("Utilization rate in buy order market (1e04): ",
            book.getUtilizationRate(_poolId) * 1e4 / WAD);
        console.log("Annualized rate in buy order market (1e05): ",
            book.getInstantRate(_poolId) * 1e5 * YEAR / WAD);
    }

    // function changeLimitPrice(address _user, uint256 _orderId, int24 _poolId) public {
    //     vm.prank(_user);
    //     book.changeLimitPrice(_orderId, _poolId);
    // }

    function changePairedPrice(address _user, uint256 _orderId, int24 _pairedPoolId) public {
        vm.prank(_user);
        book.changePairedPrice(_orderId, _pairedPoolId);
    }

}
