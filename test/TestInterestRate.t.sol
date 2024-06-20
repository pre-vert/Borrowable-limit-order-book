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

}
