// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

/// @notice tests of aggegate lending and borrowing

import {Test, console} from "forge-std/Test.sol";
import {Setup} from "./Setup.sol";
import {MathLib, WAD} from "../lib/MathLib.sol";

contract TestInterestRate is Setup {
    using MathLib for uint256;
    
    // test initial values of model's parameters

    function test_InitialValuesAtStart() public {
        vm.warp(0); // setting starting timestamp to 0
        assertEq(block.timestamp, 0);
        assertEq(getPoolDeposits(B), 0);
        assertEq(getPoolBorrows(B), 0);
        assertEq(getPoolLastTimeStamp(B), 0);
        assertEq(getTimeWeightedRate(B), 0);
        assertEq(getTimeUrWeightedRate(B), 0);
        assertEq(getUtilizationRate(B), 0);
        assertEq(getBorrowingRate(B), book.ALPHA() + book.BETA() * 0);
        assertEq(getLendingRate(B), 0);
        assertEq(getAvailableAssets(B), 0);
    }
    
    // deposit buy order in genesis pool
    // add DAY * instantRate / YEAR to time-weighted rates (starting from 0) 

    function test_InterestRateAfterDeposit() public {
        vm.warp(0); // setting starting timestamp to 0
        uint256 preDepositTimeWeightedRate = getTimeWeightedRate(B); // equals 0
        uint256 preDepositTimeUrWeightedRate = 0;
        uint256 preDepositUtilizationRate = getUtilizationRate(B); // equals 0
        uint256 preDepositBorrowingRate = book.ALPHA() + book.BETA() * preDepositUtilizationRate / WAD;
        vm.warp(DAY - 1);      // setting timestamp to one day for first deposit
        assertEq(block.timestamp, DAY - 1);
        depositBuyOrder(Alice, B, DepositQT, B + 1);
        assertEq(getTimeWeightedRate(B), preDepositTimeWeightedRate + (DAY - 1) * preDepositBorrowingRate / YEAR + 1);  
        assertEq(getTimeUrWeightedRate(B), 
            preDepositTimeUrWeightedRate + (DAY - 1) * preDepositUtilizationRate * preDepositBorrowingRate / (YEAR * WAD));
        assertEq(getBorrowingRate(B), book.ALPHA() + book.BETA() * getUtilizationRate(B) / WAD);
    }

    // deposit buy order in genesis pool, borrow from pool

    function test_InterestRateAfterBorrow() public {
        vm.warp(DAY - 1);
        depositBuyOrder(Alice, B, DepositQT, B + 1);
        uint256 preBorrowUtilizationRate = getUtilizationRate(B);
        assertEq(preBorrowUtilizationRate, 0);
        uint256 preBorrowTimeWeightedRate = getTimeWeightedRate(B);
        uint256 preBorrowTimeUrWeightedRate = getTimeUrWeightedRate(B);
        uint256 preBorrowBorrowingRate = book.ALPHA() + book.BETA() * preBorrowUtilizationRate / WAD;
        vm.warp(2 * DAY - 1);
        depositSellOrder(Bob, B + 3, DepositBT);
        borrow(Bob, B, DepositQT / 2);
        assertEq(getTimeWeightedRate(B), preBorrowTimeWeightedRate + DAY * preBorrowBorrowingRate / YEAR + 1);  
        assertEq(getTimeUrWeightedRate(B), preBorrowTimeUrWeightedRate + DAY * preBorrowUtilizationRate * preBorrowBorrowingRate / (YEAR * WAD) );
        assertEq(getBorrowingRate(B), book.ALPHA() + book.BETA() * getUtilizationRate(B) / WAD);
        assertEq(getPositionWeightedRate(FirstPositionId), getTimeWeightedRate(B)); 
    }

    // deposit buy order in genesis pool, borrow from pool, then repay with interest rate one year later

    function test_InterestRateAfterRepay() public {
        vm.warp(0);
        depositBuyOrder(Alice, B, DepositQT, B + 1);
        depositSellOrder(Bob, B + 3, DepositBT);
        borrow(Bob, B, DepositQT / 2);
        uint256 preRepayUtilizationRate = getUtilizationRate(B);
        uint256 poolWeightedRate = 0;
        assertEq(getTimeWeightedRate(B), poolWeightedRate);
        uint256 positionWeightedRate = 0;
        assertEq(getPositionWeightedRate(B), positionWeightedRate);
        uint256 preRepayBorrowingRate = book.ALPHA() + book.BETA() * preRepayUtilizationRate / WAD;

        vm.warp(YEAR - 1);
        console.log(" ");
        console.log("One year passed");

        poolWeightedRate = poolWeightedRate + (YEAR - 1) * preRepayBorrowingRate / YEAR + 1;
        uint256 rateDiff = poolWeightedRate - positionWeightedRate;
        uint256 borrowInterestRate = rateDiff.wTaylorCompoundedUp();
        uint256 borrowedAmount = (DepositQT / 2) + (DepositQT / 2) * borrowInterestRate / WAD;
        console.log("borrowed amount + interest rate 1e4 (in tests):", borrowedAmount / WAD, "USDC");
        repay(Bob, FirstPositionId, borrowedAmount);
        assertEq(getTimeWeightedRate(B), poolWeightedRate);  
        assertEq(getBorrowingRate(B), book.ALPHA() + book.BETA() * getUtilizationRate(B) / WAD);
        assertEq(getPositionWeightedRate(FirstPositionId), getTimeWeightedRate(B));
        assertEq(getPositionQuantity(FirstPositionId), 0);
    }
    
    // deposit buy order in genesis pool, borrow from pool, repay with interest rate one year later and withdraw

    // assertEq(getTimeUrWeightedRate(B), preRepayTimeUrWeightedRate + (YEAR - 1) * preRepayUtilizationRate * preRepayBorrowingRate / (YEAR * WAD) );

    function test_InterestRateAfterWithdraw() public {
        vm.warp(0);
        depositBuyOrder(Alice, B, DepositQT, B + 1);
        depositSellOrder(Bob, B + 3, DepositBT);
        borrow(Bob, B, DepositQT / 2);

        vm.warp(YEAR - 1);
        console.log(" ");
        console.log("One year passed");

        // steps necessary to calculate the max borrower has to repay:
        uint256 preRepayUtilizationRate = getUtilizationRate(B);
        uint256 preRepayBorrowingRate = book.ALPHA() + book.BETA() * preRepayUtilizationRate / WAD;
        uint256 poolWeightedRate = 0 + (YEAR - 1) * preRepayBorrowingRate / YEAR + 1;
        uint256 poolUrWeightedRate = 0 + preRepayUtilizationRate * (YEAR - 1) * preRepayBorrowingRate / (YEAR * WAD) + 1;
        console.log("poolUrWeightedRate : ", poolUrWeightedRate);
        uint256 rateDiff = poolWeightedRate - 0;
        uint256 borrowInterestRate = rateDiff.wTaylorCompoundedUp();
        uint256 borrowedAmount = (DepositQT / 2) + (DepositQT / 2) * borrowInterestRate / WAD;
        repay(Bob, FirstPositionId, borrowedAmount);
        assertEq(getUtilizationRate(B), 0); // returns to zero;
        assertEq(getLendingRate(B), 0); // returns to zero;
        assertEq(getOrderWeightedRate(FirstOrderId), 0);
        uint256 rateDiffLend = poolUrWeightedRate - 0;
        uint256 lendInterestRate = rateDiffLend.wTaylorCompoundedUp();
        uint256 aliceBalance = DepositQT + DepositQT * lendInterestRate / WAD;
        aliceBalance = 1e5 * (aliceBalance / 1e5);
        assertEq(aliceBalance / 1e5, book.viewUserQuoteDeposit(FirstOrderId) / 1e5);
        withdraw(Alice, FirstOrderId, book.viewUserQuoteDeposit(FirstOrderId));
        assertEq(getOrderQuantity(FirstOrderId), 0);
        assertEq(book.viewUserQuoteDeposit(FirstOrderId), 0);
    }


    


    // // take buy order
    // // Alice receives 900/90 = 10 BT from Bob, which are used to create a sell order
    // // The 10 BT given by Bob increases total assets in BT

    // function test_TakeBuyOrderdecreaseTotalAssets() public {
    //     vm.warp(DAY);
    //     depositBuyOrder(Alice, 2000, 90);
    //     uint256 totalQuoteAssets = book.totalQuoteAssets();
    //     uint256 totalBaseAssets = book.totalBaseAssets();
    //     uint256 totalQuoteBorrow = book.totalQuoteBorrow();
    //     uint256 totalBaseBorrow = book.totalBaseBorrow();
    //     uint256 buyOrderTimeWeightedRate = book.getTimeWeightedRate(BuyOrder);
    //     uint256 sellOrderTimeWeightedRate = book.getTimeWeightedRate(SellOrder);
    //     uint256 buyOrderinstantRate = book.getInstantRate(BuyOrder); // pulling IR before updated in take()
    //     uint256 sellOrderinstantRate = book.getInstantRate(SellOrder);
    //     vm.warp(2 * DAY);
    //     setPriceFeed(80);
    //     take(Bob, Alice_Order, 900);
    //     assertEq(book.getTimeWeightedRate(BuyOrder), buyOrderTimeWeightedRate + DAY * buyOrderinstantRate);
    //     assertEq(book.getTimeWeightedRate(SellOrder), sellOrderTimeWeightedRate + DAY * sellOrderinstantRate);
    //     assertEq(book.totalQuoteAssets(), totalQuoteAssets - 900 * WAD);
    //     assertEq(book.totalBaseAssets(), totalBaseAssets + 10 * WAD);
    //     assertEq(book.totalQuoteBorrow(), totalQuoteBorrow);
    //     assertEq(book.totalBaseBorrow(), totalBaseBorrow);
    //     assertEq(book.getUtilizationRate(BuyOrder), 0);
    //     //assertEq(book.getUtilizationRate(SellOrder), 5 * WAD / 10);
    //     checkInstantRate(BuyOrder);
    //     checkInstantRate(SellOrder);
    // }

    // // Bob takes Alice's sell order for 18 BT and gives 18 * 110 = 1980 QT
    // // which are used to create a new buy order for 1980
    // // Total BT assets are decreasing by 18
    // // Total QT assets are increasing by 1980

    // function test_TakeSellOrderdecreaseTotalAssets() public {
    //     vm.warp(DAY);
    //     depositSellOrder(Alice, 20, 110);
    //     uint256 totalQuoteAssets = book.totalQuoteAssets();
    //     uint256 totalBaseAssets = book.totalBaseAssets();
    //     uint256 totalQuoteBorrow = book.totalQuoteBorrow();
    //     uint256 totalBaseBorrow = book.totalBaseBorrow();
    //     uint256 buyOrderTimeWeightedRate = book.getTimeWeightedRate(BuyOrder);
    //     uint256 sellOrderTimeWeightedRate = book.getTimeWeightedRate(SellOrder);
    //     uint256 buyOrderinstantRate = book.getInstantRate(BuyOrder);
    //     uint256 sellOrderinstantRate = book.getInstantRate(SellOrder);
    //     vm.warp(2 * DAY);
    //     setPriceFeed(120);
    //     take(Bob, Alice_Order, 18);
    //     assertEq(book.getTimeWeightedRate(BuyOrder), buyOrderTimeWeightedRate + DAY * buyOrderinstantRate);
    //     assertEq(book.getTimeWeightedRate(SellOrder), sellOrderTimeWeightedRate + DAY * sellOrderinstantRate);
    //     assertEq(book.totalQuoteAssets(), totalQuoteAssets + 1980 * WAD);
    //     assertEq(book.totalBaseAssets(), totalBaseAssets - 18 * WAD);
    //     assertEq(book.totalQuoteBorrow(), totalQuoteBorrow);
    //     assertEq(book.totalBaseBorrow(), totalBaseBorrow);
    //     assertEq(book.getUtilizationRate(BuyOrder), 0);
    //     assertEq(book.getUtilizationRate(SellOrder), 0);
    //     checkInstantRate(BuyOrder);
    //     checkInstantRate(SellOrder);
    // }

    // // borrow buy order
    // function test_TotalBorrowIncreaseAfterBorrowBuyOrder() public {
    //     vm.warp(DAY);
    //     setPriceFeed(110);
    //     depositBuyOrder(Alice, 6000, 100);
    //     vm.warp(2 * DAY);
    //     depositSellOrder(Bob, 60, 120);
    //     uint256 totalQuoteAssets = book.totalQuoteAssets();
    //     uint256 totalBaseAssets = book.totalBaseAssets();
    //     uint256 totalQuoteBorrow = book.totalQuoteBorrow();
    //     uint256 totalBaseBorrow = book.totalBaseBorrow();
    //     uint256 buyOrderTimeWeightedRate = book.getTimeWeightedRate(BuyOrder);
    //     uint256 sellOrderTimeWeightedRate = book.getTimeWeightedRate(SellOrder);
    //     uint256 buyOrderinstantRate = book.getInstantRate(BuyOrder); // pulling IR before updated in borrow()
    //     uint256 sellOrderinstantRate = book.getInstantRate(SellOrder);
    //     vm.warp(4 * DAY);
    //     borrow(Bob, Alice_Order, 1500);
    //     assertEq(book.getTimeWeightedRate(BuyOrder), buyOrderTimeWeightedRate + 2 * DAY * buyOrderinstantRate);
    //     assertEq(book.getTimeWeightedRate(SellOrder), sellOrderTimeWeightedRate + 2 * DAY * sellOrderinstantRate);
    //     assertEq(book.totalQuoteAssets(), totalQuoteAssets);
    //     assertEq(book.totalBaseAssets(), totalBaseAssets);
    //     assertEq(book.totalQuoteBorrow(), totalQuoteBorrow + 1500 * WAD);
    //     assertEq(book.totalBaseBorrow(), totalBaseBorrow);
    //     assertEq(book.getUtilizationRate(BuyOrder), book.totalQuoteBorrow() * WAD / book.totalQuoteAssets());
    //     assertEq(book.getUtilizationRate(SellOrder), 0);
    //     checkInstantRate(BuyOrder);
    //     checkInstantRate(SellOrder);
    // }

    // // Total borrow increase after borrow sell order
    // function test_TotalBorrowIncreaseAfterBorrowSellOrder() public {
    //     vm.warp(DAY);
    //     setPriceFeed(110);
    //     depositSellOrder(Alice, 20, 120);
    //     vm.warp(2 * DAY);
    //     depositBuyOrder(Bob, 6000, 100);
    //     uint256 totalQuoteAssets = book.totalQuoteAssets();
    //     uint256 totalBaseAssets = book.totalBaseAssets();
    //     uint256 totalQuoteBorrow = book.totalQuoteBorrow();
    //     uint256 totalBaseBorrow = book.totalBaseBorrow();
    //     uint256 buyOrderTimeWeightedRate = book.getTimeWeightedRate(BuyOrder);
    //     uint256 sellOrderTimeWeightedRate = book.getTimeWeightedRate(SellOrder);
    //     uint256 buyOrderinstantRate = book.getInstantRate(BuyOrder);
    //     uint256 sellOrderinstantRate = book.getInstantRate(SellOrder);
    //     vm.warp(4 * DAY);
    //     borrow(Bob, Alice_Order, 15);
    //     assertEq(book.getTimeWeightedRate(BuyOrder), buyOrderTimeWeightedRate + 2 * DAY * buyOrderinstantRate);
    //     assertEq(book.getTimeWeightedRate(SellOrder), sellOrderTimeWeightedRate + 2 * DAY * sellOrderinstantRate);
    //     assertEq(book.totalQuoteAssets(), totalQuoteAssets);
    //     assertEq(book.totalBaseAssets(), totalBaseAssets);
    //     assertEq(book.totalQuoteBorrow(), totalQuoteBorrow);
    //     assertEq(book.totalBaseBorrow(), totalBaseBorrow + 15 * WAD);
    //     assertEq(book.getUtilizationRate(BuyOrder), 0);
    //     assertEq(book.getUtilizationRate(SellOrder), book.totalBaseBorrow() * WAD / book.totalBaseAssets());
    //     checkInstantRate(BuyOrder);
    //     checkInstantRate(SellOrder);
    // }

    // // repay buy order
    // function test_TotalBorrowDecreaseAfterRepayBuyOrder() public {
    //     setPriceFeed(110);
    //     vm.warp(DAY);
    //     depositBuyOrder(Alice, 6000, 100);
    //     vm.warp(2 * DAY);
    //     depositSellOrder(Bob, 60, 120);
    //     vm.warp(4 * DAY);
    //     borrow(Bob, Alice_Order, 2500);
    //     uint256 totalQuoteAssets = book.totalQuoteAssets();
    //     uint256 totalBaseAssets = book.totalBaseAssets();
    //     // uint256 totalQuoteBorrow = book.totalQuoteBorrow();
    //     uint256 totalBaseBorrow = book.totalBaseBorrow();
    //     uint256 buyOrderTimeWeightedRate = book.getTimeWeightedRate(BuyOrder);
    //     uint256 sellOrderTimeWeightedRate = book.getTimeWeightedRate(SellOrder);
    //     uint256 buyOrderinstantRate = book.getInstantRate(BuyOrder); // pulling IR before updated in repay()
    //     uint256 sellOrderinstantRate = book.getInstantRate(SellOrder);
    //     vm.warp(369 * DAY);
    //     repay(Bob, Bob_Position, 1500);
    //     checkInstantRate(BuyOrder);
    //     checkInstantRate(SellOrder);
    //     assertEq(book.getTimeWeightedRate(BuyOrder), buyOrderTimeWeightedRate + 365 * DAY * buyOrderinstantRate);
    //     assertEq(book.getTimeWeightedRate(SellOrder), sellOrderTimeWeightedRate + 365 * DAY * sellOrderinstantRate);
    //     assertEq(book.totalQuoteAssets(), totalQuoteAssets);
    //     assertEq(book.totalBaseAssets(), totalBaseAssets);
    //     // assertEq(book.totalQuoteBorrow(), totalQuoteBorrow - 1500 * WAD); // interest load is missing but hard to calculate
    //     assertEq(book.totalBaseBorrow(), totalBaseBorrow);
    //     assertEq(book.getUtilizationRate(BuyOrder), book.totalQuoteBorrow() * WAD / book.totalQuoteAssets());
    //     assertEq(book.getUtilizationRate(SellOrder), 0);
    // }

    // // Total borrow decrease after repay sell order
    // function test_TotalBorrowDecreaseAfterRepaySellOrder() public {
    //     setPriceFeed(115);
    //     vm.warp(DAY);
    //     depositSellOrder(Alice, 20, 120);
    //     vm.warp(2 * DAY);
    //     depositBuyOrder(Bob, 6000, 110);
    //     vm.warp(4 * DAY);
    //     borrow(Bob, Alice_Order, 15);
    //     uint256 totalQuoteAssets = book.totalQuoteAssets();
    //     uint256 totalBaseAssets = book.totalBaseAssets();
    //     uint256 totalQuoteBorrow = book.totalQuoteBorrow();
    //     // uint256 totalBaseBorrow = book.totalBaseBorrow();
    //     uint256 buyOrderTimeWeightedRate = book.getTimeWeightedRate(BuyOrder);
    //     uint256 sellOrderTimeWeightedRate = book.getTimeWeightedRate(SellOrder);
    //     uint256 buyOrderinstantRate = book.getInstantRate(BuyOrder);
    //     uint256 sellOrderinstantRate = book.getInstantRate(SellOrder);
    //     vm.warp(369 * DAY);
    //     repay(Bob, Bob_Position, 10);
    //     assertEq(book.getTimeWeightedRate(BuyOrder), buyOrderTimeWeightedRate + 365 * DAY * buyOrderinstantRate);
    //     assertEq(book.getTimeWeightedRate(SellOrder), sellOrderTimeWeightedRate + 365 * DAY * sellOrderinstantRate);
    //     assertEq(book.totalQuoteAssets(), totalQuoteAssets);
    //     assertEq(book.totalBaseAssets(), totalBaseAssets);
    //     assertEq(book.totalQuoteBorrow(), totalQuoteBorrow);
    //     // assertEq(book.totalBaseBorrow(), totalBaseBorrow - 10 * WAD);
    //     assertEq(book.getUtilizationRate(BuyOrder), 0);
    //     assertEq(book.getUtilizationRate(SellOrder), book.totalBaseBorrow() * WAD / book.totalBaseAssets());
    //     checkInstantRate(BuyOrder);
    //     checkInstantRate(SellOrder);
    // }
    
    // function test_MultipleActionsTrackingIRM() public {
    //     vm.warp(0); // setting starting timestamp to 0
    //     setPriceFeed(110);
    //     checkInstantRate(BuyOrder);
    //     checkInstantRate(SellOrder);
    //     vm.warp(DAY);
    //     depositBuyOrder(Alice, 6000, 100);
    //     checkInstantRate(BuyOrder);
    //     checkInstantRate(SellOrder);
    //     vm.warp(2 * DAY);
    //     depositSellOrder(Bob, 60, 120);
    //     checkInstantRate(BuyOrder);
    //     checkInstantRate(SellOrder);
    //     vm.warp(3 * DAY);
    //     withdraw(Alice, Alice_Order, 2000);
    //     checkInstantRate(BuyOrder);
    //     checkInstantRate(SellOrder);
    //     vm.warp(4 * DAY);
    //     borrow(Bob, Alice_Order, 1500);
    //     checkInstantRate(BuyOrder);
    //     checkInstantRate(SellOrder);
    //     vm.warp(369 * DAY);
    //     repay(Bob, Bob_Position, 1000);
    //     checkInstantRate(BuyOrder);
    //     checkInstantRate(SellOrder);
    //     setPriceFeed(90);
    //     vm.warp(370 * DAY);
    //     take(Carol, Alice_Order, 1000);
    // }
}
