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

    // constants //
    bool constant public BuyOrder = true;
    bool constant public SellOrder = false;
    bool constant public InQuoteToken = true;
    bool constant public InBaseToken = false;
    uint256 constant public B = 1111111110;
    uint256 constant public AccountNumber = 102;
    uint256 constant public ReceivedQuoteToken = 10000000 * WAD;
    uint256 constant public ReceivedBaseToken = 5000 * WAD;
    uint256 constant public YEAR = 365 days; // number of seconds in one year
    uint256 constant public DAY = 1 days; // number of seconds in one day
    uint256 constant FirstRow = 0;
    uint256 constant SecondRow = 1;
    uint256 constant NoOrderId = 0;
    uint256 constant FirstOrderId = 1;
    uint256 constant SecondOrderId = 2;
    uint256 constant ThirdOrderId = 3;
    uint256 constant FourthOrderId = 4;
    uint256 constant NoPositionId = 0;
    uint256 constant FirstPositionId = 1;
    uint256 constant SecondPositionId = 2;
    uint256 constant ThirdPositionId = 3;
    uint256 constant DepositQT = 20000 * WAD;
    uint256 constant DepositBT = 10 * WAD;
    uint256 constant TakeQT = 900 * WAD;
    uint256 constant TakeBT = 10 * WAD;
    uint256 constant LowPrice = 3990 * WAD;
    uint256 constant HighPrice = 4010 * WAD;
    uint256 constant UltraLowPrice = 3500 * WAD;
    uint256 constant UltraHighPrice = 4500 * WAD;

    // variables //
    uint256 public genesisLimitPriceWAD; // initial limit price in WAD of genesis pool = 4000
    uint256 public initialPrice = genesisLimitPriceWAD / WAD + 1; // initial price feed
    uint256 public priceStep;
    uint256 public minDepositBase;
    uint256 public minDepositQuote;
    uint256 public liquidationLTV;
    address OrderBook;
    address Alice;
    address Bob;
    address Carol;
    address Dave;
    address Linda;
    address Takashi;

    mapping(uint256 => address) public acc;

    modifier depositBuy(uint256 _poolId) {
        depositBuyOrder(Alice, _poolId, DepositQT, _poolId + 1);
        _;
    }

    modifier depositSell(uint256 _poolId) {
        depositSellOrder(Bob, _poolId, DepositBT);
        _;
    }

    modifier depositInAccount(uint256 _quantity) {
        depositInBaseAccount(Bob, _quantity);
        _;
    }

    modifier setLowPrice() {
        setPriceFeed(LowPrice / WAD);
        _;
    }

    modifier setHighPrice() {
        setPriceFeed(HighPrice / WAD);
        _;
    }

    modifier setUltraLowPrice() {
        setPriceFeed(UltraLowPrice / WAD);
        _;
    }

    modifier setUltraHighPrice() {
        setPriceFeed(UltraHighPrice / WAD);
        _;
    }

    function setUp() public {
        deployBook = new DeployBook();
        (
            book, 
            quoteToken,
            baseToken,
            genesisLimitPriceWAD,
            minDepositBase,
            minDepositQuote,
            liquidationLTV
        )
        = deployBook.run();
        fundingAccounts(AccountNumber);
        setPriceFeed(genesisLimitPriceWAD / WAD + 1);
    }
    
    // funding an army of traders
    function fundingAccounts(uint256 _accountNumber) public {
        for (uint256 i = 1; i <= _accountNumber; i++) {
            _receiveTokens(i, ReceivedQuoteToken, ReceivedBaseToken);
            _allowTokens(i, AccountNumber * ReceivedQuoteToken, AccountNumber * ReceivedBaseToken);
        }
        OrderBook = address(book);
        Alice = acc[1];
        Bob = acc[2];
        Carol = acc[3];
        Dave = acc[4];
        Linda = acc[AccountNumber - 1];
        Takashi = acc[AccountNumber];
    }

    function _receiveTokens(uint256 _userId, uint256 _quoteTokens, uint256 _baseTokens) internal {
        // acc[_userId] = makeAddr(vm.toString(_userId));
        acc[_userId] = vm.addr(_userId);
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

    function setPriceFeed(uint256 _price) public {
        book.setPriceFeed(_price * WAD);
    }

    //******** ACTIONS  *********//
    
    function depositBuyOrder(
        address _user,
        uint256 _poolId,
        uint256 _quantity,
        uint256 _pairedPoolId
    ) public {
        vm.prank(_user);
        book.deposit( _poolId, _quantity, _pairedPoolId);
    }

    function depositSellOrder(
        address _user,
        uint256 _poolId,
        uint256 _quantity
    ) public {
        vm.prank(_user);
        book.deposit(_poolId, _quantity, 0);
    }

    function depositInBaseAccount(address _user, uint256 _quantity) public {
        vm.prank(_user);
        book.depositInCollateralAccount(_quantity);
    }

    function withdraw(address _user, uint256 _orderId, uint256 _quantity) public {
        vm.prank(_user);
        book.withdraw(_orderId, _quantity);
    }

    function withdrawFromBaseAccount(address _user, uint256 _quantity) public {
        vm.prank(_user);
        book.withdrawFromAccount(_quantity, InBaseToken);
    }

    function withdrawFromQuoteAccount(address _user, uint256 _quantity) public {
        vm.prank(_user);
        book.withdrawFromAccount(_quantity, InQuoteToken);
    }

    function borrow(address _user, uint256 _poolId, uint256 _quantity) public {
        vm.prank(_user);
        book.borrow(_poolId, _quantity);
    }
    
    function repay(address _user, uint256 _positionId, uint256 _quantity) public {
        vm.prank(_user);
        book.repay(_positionId, _quantity);
    }

    function takeQuoteTokens(uint256 _poolId, uint256 _takenQuantity) public {
        vm.prank(Takashi);
        book.takeQuoteTokens(_poolId, _takenQuantity);
    }

    function takeBaseTokens(uint256 _poolId, uint256 _takenQuantity) public {
        vm.prank(Takashi);
        book.takeBaseTokens(_poolId, _takenQuantity);
    }

    function liquidateUser(address _borrower, uint256 _quantity) public {
        vm.prank(Linda);
        book.liquidateUser(_borrower, _quantity);
    }

     function changePairedPrice(address _user, uint256 _orderId, uint256 _pairedPoolId) public {
        vm.prank(_user);
        book.changePairedPrice(_orderId, _pairedPoolId);
    }

    //******** CHECK ORDERS  *********//

    // check maker of order
    function checkOrderMaker(uint256 _orderId, address _maker) public {
        (, address maker,,,) = book.orders(_orderId);
        assertEq(maker, _maker);
    }

    // get order quantity
    function getOrderQuantity(uint256 _orderId) public  view returns (uint256 quantity_) {
        (,,, quantity_,) = book.orders(_orderId);
    }

    // check limit price in order
    function checkPoolId(uint256 _orderId, uint256 _poolId) public {
        (uint256 poolId,,,,) = book.orders(_orderId);
        assertEq(poolId, _poolId);
    }

    // check paired pool id in order
    function checkOrderPairedPrice(uint256 _orderId, uint256 _pairedPoolId) public {
        (,, uint256 pairedPoolId,,) = book.orders(_orderId);
        assertEq(pairedPoolId, _pairedPoolId);
    }

    // time-weighted and UR-weighted average interest rate for supply since initial deposit or reset
    function getOrderWeightedRate(uint256 _orderId) public view returns (uint256 timeWeightedRate_) {
        (,,,, timeWeightedRate_) = book.orders(_orderId);
    }

    //******** CHECK POSITIONS  *********//

    // // check assets borrowed in position = _quantity
    // function checkBorrowingQuantity(uint256 _positionId, uint256 _quantity) public {
    //     (,, uint256 quantity,) = book.positions(_positionId);
    //     assertEq(quantity, _quantity);
    // }

    function getPositionQuantity(uint256 _positionId) public view returns (uint256 _quantity) {
        (,, _quantity, ) = book.positions(_positionId);
    }

    function getPositionWeightedRate(uint256 _positionId) public view returns (uint256 _weightedRate) {
        (,,, _weightedRate) = book.positions(_positionId);
    }

    //******** CHECK USERS  *********//
    
    // input row, starting at 0, returns order id
    function checkUserDepositId(address _user, uint256 _row, uint256 _orderId) public {
        assertEq(book.getUserDepositIds(_user)[_row], _orderId);
    }

    // input row, starting 0, returns position id
    function checkUserBorrowId(address _user, uint256 _row, uint256 _positionId) public {
        assertEq(book.getUserBorrowFromIds(_user)[_row], _positionId);
    }

    function checkUserBaseAccount(address _user, uint256 _quantity) public {
        (uint256 baseAccount,) = book.users(_user);
        assertEq(baseAccount, _quantity);
    }

    function checkUserQuoteAccount(address _user, uint256 _quantity) public {
        (, uint256 quoteAccount) = book.users(_user);
        assertEq(quoteAccount, _quantity);
    }

    //******** CHECK POOLS & INTEREST RATES *********//

    // get deposited assets in pool
    function getPoolDeposits(uint256 _poolId) public view returns (uint256 poolDeposits_) {
        (poolDeposits_,,,,,,,,) = book.pools(_poolId);
    }

    // get borrowed assets in pool
    function getPoolBorrows(uint256 _poolId) public view returns (uint256 poolBorrows_) {
        (, poolBorrows_,,,,,,,) = book.pools(_poolId);
    }

    // get last timestamp in pool = _time
    function getPoolLastTimeStamp(uint256 _poolId) public view returns (uint256 lastTimeStamp_) {
        (,, lastTimeStamp_,,,,,,) = book.pools(_poolId);
    }

    // get timeWeightedRate in pool 
    function getTimeWeightedRate(uint256 _poolId) public view returns (uint256 timeWeightedRate_) {
        (,,, timeWeightedRate_,,,,,) = book.pools(_poolId);
    }

    // get timeURWeightedRate in pool = _rate
    function getTimeUrWeightedRate(uint256 _poolId) public view returns (uint256 timeURWeightedRate_) {
        (,,,, timeURWeightedRate_,,,,) = book.pools(_poolId);
    }

    // get UR in pool
    function getUtilizationRate(uint256 _poolId) public view returns (uint256 utilizationRate_) {
        utilizationRate_ = book.viewUtilizationRate(_poolId);
    }

    // get annual borrowing rate in pool
    function getBorrowingRate(uint256 _poolId) public view returns (uint256 borrowingRate_) {
        borrowingRate_ = book.viewBorrowingRate(_poolId);
    }

    // get annual Lending rate in pool
    function getLendingRate(uint256 _poolId) public view returns (uint256 lendingRate_) {
        lendingRate_ = book.viewLendingRate(_poolId);
    }

    // get annual Lending rate in pool
    function getAvailableAssets(uint256 _poolId) public view returns (uint256 availableAssets_) {
        availableAssets_ = book.viewPoolAvailableAssets(_poolId);
    }

    // function getBorrowingRate(uint256 _poolId) public view returns (uint256 ) {
    //     uint256 uR = book.viewUtilizationRate(_poolId);
    //     borrowing = book.viewBorrowingRate(_poolId);
    //     assertEq(bR, _rate);
    //     console.log("Utilization rate (1e04): ", uR * 1e4 / WAD);
    //     console.log("Annualized rate (1e05): ", bR * 1e5 / WAD);
    // }   

}
