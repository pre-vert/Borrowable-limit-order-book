// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

/// @notice tests of aggegate lending and borrowing

import {Test, console} from "forge-std/Test.sol";
import {Setup} from "./Setup.sol";
import {MathLib, WAD} from "../lib/MathLib.sol";

contract TestInterestRate is Setup {
    
    // test initial values of model's parameters
    function test_InitialValuesAtStart() public {
        vm.warp(0); // setting starting timestamp to 0
        assertEq(block.timestamp, 0);
        assertEq(book.totalQuoteAssets(), 0);
        assertEq(book.totalBaseAssets(), 0);
        assertEq(book.totalQuoteBorrow(), 0);
        assertEq(book.totalBaseBorrow(), 0);
        assertEq(book.getUtilizationRate(BuyOrder), 5 * WAD / 10);
        assertEq(book.getUtilizationRate(SellOrder), 5 * WAD / 10);
        checkInstantRate(BuyOrder);
        checkInstantRate(SellOrder);
        assertEq(book.getTimeWeightedRate(BuyOrder), 0);
        assertEq(book.getTimeWeightedRate(SellOrder), 0);
    }
    
    // deposit buy order
    // add DAY * instantRate / YEAR to time-weighted rates (here 0) 

    function test_TotalAssetsIncreaseAfterDepositBuyOrder() public {
        uint256 totalQuoteAssets = book.totalQuoteAssets();
        uint256 totalBaseAssets = book.totalBaseAssets();
        uint256 totalQuoteBorrow = book.totalQuoteBorrow();
        uint256 totalBaseBorrow = book.totalBaseBorrow();
        uint256 buyOrderTimeWeightedRate = book.getTimeWeightedRate(BuyOrder); // equals 0
        uint256 sellOrderTimeWeightedRate = book.getTimeWeightedRate(SellOrder); // equals 0
        uint256 buyOrderinstantRate = book.getInstantRate(BuyOrder); // pulling IR before updated in deposit()
        uint256 sellOrderinstantRate = book.getInstantRate(SellOrder);
        vm.warp(DAY); // setting timestamp to one day for first deposit after deployment
        assertEq(block.timestamp, DAY);
        depositBuyOrder(Alice, 2000, 90);
        assertEq(book.getTimeWeightedRate(BuyOrder), buyOrderTimeWeightedRate + (DAY - 1) * buyOrderinstantRate);
        assertEq(book.getTimeWeightedRate(SellOrder), sellOrderTimeWeightedRate + (DAY - 1) * sellOrderinstantRate);
        assertEq(book.totalQuoteAssets(), totalQuoteAssets + 2000 * WAD);
        assertEq(book.totalBaseAssets(), totalBaseAssets);
        assertEq(book.totalQuoteBorrow(), totalQuoteBorrow);
        assertEq(book.totalBaseBorrow(), totalBaseBorrow);
        assertEq(book.getUtilizationRate(BuyOrder), 0);
        assertEq(book.getUtilizationRate(SellOrder), 5 * WAD / 10);
        checkInstantRate(BuyOrder);
        checkInstantRate(SellOrder);
    }

    // deposit sell order
    function test_TotalAssetsIncreaseAfterDepositSellOrder() public {
        uint256 totalQuoteAssets = book.totalQuoteAssets();
        uint256 totalBaseAssets = book.totalBaseAssets();
        uint256 totalQuoteBorrow = book.totalQuoteBorrow();
        uint256 totalBaseBorrow = book.totalBaseBorrow();
        uint256 buyOrderTimeWeightedRate = book.getTimeWeightedRate(BuyOrder); // equals 0
        uint256 sellOrderTimeWeightedRate = book.getTimeWeightedRate(SellOrder); // equals 0
        uint256 buyOrderinstantRate = book.getInstantRate(BuyOrder);
        uint256 sellOrderinstantRate = book.getInstantRate(SellOrder);
        vm.warp(DAY); // setting timestamp to one day after start for first deposit
        depositSellOrder(Alice, 20, 110);
        assertEq(book.getTimeWeightedRate(BuyOrder), buyOrderTimeWeightedRate + (DAY - 1) * buyOrderinstantRate);
        assertEq(book.getTimeWeightedRate(SellOrder), sellOrderTimeWeightedRate + (DAY - 1) * sellOrderinstantRate);
        assertEq(book.totalQuoteAssets(), totalQuoteAssets);
        assertEq(book.totalBaseAssets(), totalBaseAssets + 20 * WAD);
        assertEq(book.totalQuoteBorrow(), totalQuoteBorrow);
        assertEq(book.totalBaseBorrow(), totalBaseBorrow);
        assertEq(book.getUtilizationRate(BuyOrder), 5 * WAD / 10);
        assertEq(book.getUtilizationRate(SellOrder), 0);
        checkInstantRate(BuyOrder);
        checkInstantRate(SellOrder);
    }

    // withdraw buy order
    function test_TotalAssetsDecreaseAfterWithdrawBuyOrder() public {
        vm.warp(DAY);
        depositBuyOrder(Alice, 2000, 90);
        uint256 totalQuoteAssets = book.totalQuoteAssets();
        uint256 totalBaseAssets = book.totalBaseAssets();
        uint256 totalQuoteBorrow = book.totalQuoteBorrow();
        uint256 totalBaseBorrow = book.totalBaseBorrow();
        uint256 buyOrderTimeWeightedRate = book.getTimeWeightedRate(BuyOrder);
        uint256 sellOrderTimeWeightedRate = book.getTimeWeightedRate(SellOrder);
        uint256 buyOrderinstantRate = book.getInstantRate(BuyOrder); // pulling IR before updated in withdraw()
        uint256 sellOrderinstantRate = book.getInstantRate(SellOrder);
        vm.warp(2 * DAY);
        withdraw(Alice, Alice_Order, 1000);
        assertEq(book.getTimeWeightedRate(BuyOrder), buyOrderTimeWeightedRate + DAY * buyOrderinstantRate);
        assertEq(book.getTimeWeightedRate(SellOrder), sellOrderTimeWeightedRate + DAY * sellOrderinstantRate);
        assertEq(book.totalQuoteAssets(), totalQuoteAssets - 1000 * WAD);
        assertEq(book.totalBaseAssets(), totalBaseAssets);
        assertEq(book.totalQuoteBorrow(), totalQuoteBorrow);
        assertEq(book.totalBaseBorrow(), totalBaseBorrow);
        assertEq(book.getUtilizationRate(BuyOrder), 0);
        assertEq(book.getUtilizationRate(SellOrder), 5 * WAD / 10);
        checkInstantRate(BuyOrder);
        checkInstantRate(SellOrder);
    }

    // withdraw sell order
    function test_TotalAssetsDecreaseAfterWithdrawSellOrder() public {
        vm.warp(DAY);
        depositSellOrder(Alice, 20, 110);
        uint256 totalQuoteAssets = book.totalQuoteAssets();
        uint256 totalBaseAssets = book.totalBaseAssets();
        uint256 totalQuoteBorrow = book.totalQuoteBorrow();
        uint256 totalBaseBorrow = book.totalBaseBorrow();
        uint256 buyOrderTimeWeightedRate = book.getTimeWeightedRate(BuyOrder);
        uint256 sellOrderTimeWeightedRate = book.getTimeWeightedRate(SellOrder);
        uint256 buyOrderinstantRate = book.getInstantRate(BuyOrder);
        uint256 sellOrderinstantRate = book.getInstantRate(SellOrder);
        vm.warp(2 * DAY);
        withdraw(Alice, Alice_Order, 10);
        assertEq(book.getTimeWeightedRate(BuyOrder), buyOrderTimeWeightedRate + DAY * buyOrderinstantRate);
        assertEq(book.getTimeWeightedRate(SellOrder), sellOrderTimeWeightedRate + DAY * sellOrderinstantRate);
        assertEq(book.totalQuoteAssets(), totalQuoteAssets);
        assertEq(book.totalBaseAssets(), totalBaseAssets - 10 * WAD);
        assertEq(book.totalQuoteBorrow(), totalQuoteBorrow);
        assertEq(book.totalBaseBorrow(), totalBaseBorrow);
        assertEq(book.getUtilizationRate(BuyOrder), 5 * WAD / 10);
        assertEq(book.getUtilizationRate(SellOrder), 0);
        checkInstantRate(BuyOrder);
        checkInstantRate(SellOrder);
    }

    // take buy order
    function test_TakeBuyOrderdecreaseTotalAssets() public {
        vm.warp(DAY);
        depositBuyOrder(Alice, 2000, 90);
        uint256 totalQuoteAssets = book.totalQuoteAssets();
        uint256 totalBaseAssets = book.totalBaseAssets();
        uint256 totalQuoteBorrow = book.totalQuoteBorrow();
        uint256 totalBaseBorrow = book.totalBaseBorrow();
        uint256 buyOrderTimeWeightedRate = book.getTimeWeightedRate(BuyOrder);
        uint256 sellOrderTimeWeightedRate = book.getTimeWeightedRate(SellOrder);
        uint256 buyOrderinstantRate = book.getInstantRate(BuyOrder); // pulling IR before updated in take()
        uint256 sellOrderinstantRate = book.getInstantRate(SellOrder);
        vm.warp(2 * DAY);
        setPriceFeed(80);
        take(Bob, Alice_Order, 1000);
        assertEq(book.getTimeWeightedRate(BuyOrder), buyOrderTimeWeightedRate + DAY * buyOrderinstantRate);
        assertEq(book.getTimeWeightedRate(SellOrder), sellOrderTimeWeightedRate + DAY * sellOrderinstantRate);
        assertEq(book.totalQuoteAssets(), totalQuoteAssets - 1000 * WAD);
        assertEq(book.totalBaseAssets(), totalBaseAssets);
        assertEq(book.totalQuoteBorrow(), totalQuoteBorrow);
        assertEq(book.totalBaseBorrow(), totalBaseBorrow);
        assertEq(book.getUtilizationRate(BuyOrder), 0);
        assertEq(book.getUtilizationRate(SellOrder), 5 * WAD / 10);
        checkInstantRate(BuyOrder);
        checkInstantRate(SellOrder);
    }

    // take sell order
    function test_TakeSellOrderdecreaseTotalAssets() public {
        vm.warp(DAY);
        depositSellOrder(Alice, 20, 110);
        uint256 totalQuoteAssets = book.totalQuoteAssets();
        uint256 totalBaseAssets = book.totalBaseAssets();
        uint256 totalQuoteBorrow = book.totalQuoteBorrow();
        uint256 totalBaseBorrow = book.totalBaseBorrow();
        uint256 buyOrderTimeWeightedRate = book.getTimeWeightedRate(BuyOrder);
        uint256 sellOrderTimeWeightedRate = book.getTimeWeightedRate(SellOrder);
        uint256 buyOrderinstantRate = book.getInstantRate(BuyOrder);
        uint256 sellOrderinstantRate = book.getInstantRate(SellOrder);
        vm.warp(2 * DAY);
        setPriceFeed(120);
        take(Bob, Alice_Order, 18);
        assertEq(book.getTimeWeightedRate(BuyOrder), buyOrderTimeWeightedRate + DAY * buyOrderinstantRate);
        assertEq(book.getTimeWeightedRate(SellOrder), sellOrderTimeWeightedRate + DAY * sellOrderinstantRate);
        assertEq(book.totalQuoteAssets(), totalQuoteAssets);
        assertEq(book.totalBaseAssets(), totalBaseAssets - 18 * WAD);
        assertEq(book.totalQuoteBorrow(), totalQuoteBorrow);
        assertEq(book.totalBaseBorrow(), totalBaseBorrow);
        assertEq(book.getUtilizationRate(BuyOrder), 5 * WAD / 10);
        assertEq(book.getUtilizationRate(SellOrder), 0);
        checkInstantRate(BuyOrder);
        checkInstantRate(SellOrder);
    }

    // borrow buy order
    function test_TotalBorrowIncreaseAfterBorrowBuyOrder() public {
        vm.warp(DAY);
        depositBuyOrder(Alice, 6000, 100);
        vm.warp(2 * DAY);
        depositSellOrder(Bob, 60, 120);
        uint256 totalQuoteAssets = book.totalQuoteAssets();
        uint256 totalBaseAssets = book.totalBaseAssets();
        uint256 totalQuoteBorrow = book.totalQuoteBorrow();
        uint256 totalBaseBorrow = book.totalBaseBorrow();
        uint256 buyOrderTimeWeightedRate = book.getTimeWeightedRate(BuyOrder);
        uint256 sellOrderTimeWeightedRate = book.getTimeWeightedRate(SellOrder);
        uint256 buyOrderinstantRate = book.getInstantRate(BuyOrder); // pulling IR before updated in borrow()
        uint256 sellOrderinstantRate = book.getInstantRate(SellOrder);
        vm.warp(4 * DAY);
        borrow(Bob, Alice_Order, 1500);
        assertEq(book.getTimeWeightedRate(BuyOrder), buyOrderTimeWeightedRate + 2 * DAY * buyOrderinstantRate);
        assertEq(book.getTimeWeightedRate(SellOrder), sellOrderTimeWeightedRate + 2 * DAY * sellOrderinstantRate);
        assertEq(book.totalQuoteAssets(), totalQuoteAssets);
        assertEq(book.totalBaseAssets(), totalBaseAssets);
        assertEq(book.totalQuoteBorrow(), totalQuoteBorrow + 1500 * WAD);
        assertEq(book.totalBaseBorrow(), totalBaseBorrow);
        assertEq(book.getUtilizationRate(BuyOrder), book.totalQuoteBorrow() * WAD / book.totalQuoteAssets());
        assertEq(book.getUtilizationRate(SellOrder), 0);
        checkInstantRate(BuyOrder);
        checkInstantRate(SellOrder);
    }

    // Total borrow increase after borrow sell order
    function test_TotalBorrowIncreaseAfterBorrowSellOrder() public {
        vm.warp(DAY);
        depositSellOrder(Alice, 20, 100);
        vm.warp(2 * DAY);
        depositBuyOrder(Bob, 6000, 120);
        uint256 totalQuoteAssets = book.totalQuoteAssets();
        uint256 totalBaseAssets = book.totalBaseAssets();
        uint256 totalQuoteBorrow = book.totalQuoteBorrow();
        uint256 totalBaseBorrow = book.totalBaseBorrow();
        uint256 buyOrderTimeWeightedRate = book.getTimeWeightedRate(BuyOrder);
        uint256 sellOrderTimeWeightedRate = book.getTimeWeightedRate(SellOrder);
        uint256 buyOrderinstantRate = book.getInstantRate(BuyOrder);
        uint256 sellOrderinstantRate = book.getInstantRate(SellOrder);
        vm.warp(4 * DAY);
        borrow(Bob, Alice_Order, 15);
        assertEq(book.getTimeWeightedRate(BuyOrder), buyOrderTimeWeightedRate + 2 * DAY * buyOrderinstantRate);
        assertEq(book.getTimeWeightedRate(SellOrder), sellOrderTimeWeightedRate + 2 * DAY * sellOrderinstantRate);
        assertEq(book.totalQuoteAssets(), totalQuoteAssets);
        assertEq(book.totalBaseAssets(), totalBaseAssets);
        assertEq(book.totalQuoteBorrow(), totalQuoteBorrow);
        assertEq(book.totalBaseBorrow(), totalBaseBorrow + 15 * WAD);
        assertEq(book.getUtilizationRate(BuyOrder), 0);
        assertEq(book.getUtilizationRate(SellOrder), book.totalBaseBorrow() * WAD / book.totalBaseAssets());
        checkInstantRate(BuyOrder);
        checkInstantRate(SellOrder);
    }

    // repay buy order
    function test_TotalBorrowDecreaseAfterRepayBuyOrder() public {
        vm.warp(DAY);
        depositBuyOrder(Alice, 6000, 100);
        vm.warp(2 * DAY);
        depositSellOrder(Bob, 60, 120);
        vm.warp(4 * DAY);
        borrow(Bob, Alice_Order, 2500);
        uint256 totalQuoteAssets = book.totalQuoteAssets();
        uint256 totalBaseAssets = book.totalBaseAssets();
        // uint256 totalQuoteBorrow = book.totalQuoteBorrow();
        uint256 totalBaseBorrow = book.totalBaseBorrow();
        uint256 buyOrderTimeWeightedRate = book.getTimeWeightedRate(BuyOrder);
        uint256 sellOrderTimeWeightedRate = book.getTimeWeightedRate(SellOrder);
        uint256 buyOrderinstantRate = book.getInstantRate(BuyOrder); // pulling IR before updated in repay()
        uint256 sellOrderinstantRate = book.getInstantRate(SellOrder);
        vm.warp(369 * DAY);
        repay(Bob, Bob_Position, 1500);
        checkInstantRate(BuyOrder);
        checkInstantRate(SellOrder);
        assertEq(book.getTimeWeightedRate(BuyOrder), buyOrderTimeWeightedRate + 365 * DAY * buyOrderinstantRate);
        assertEq(book.getTimeWeightedRate(SellOrder), sellOrderTimeWeightedRate + 365 * DAY * sellOrderinstantRate);
        assertEq(book.totalQuoteAssets(), totalQuoteAssets);
        assertEq(book.totalBaseAssets(), totalBaseAssets);
        // assertEq(book.totalQuoteBorrow(), totalQuoteBorrow - 1500 * WAD); // interest load is missing but hard to calculate
        assertEq(book.totalBaseBorrow(), totalBaseBorrow);
        assertEq(book.getUtilizationRate(BuyOrder), book.totalQuoteBorrow() * WAD / book.totalQuoteAssets());
        assertEq(book.getUtilizationRate(SellOrder), 0);
    }

    // Total borrow decrease after repay sell order
    function test_TotalBorrowDecreaseAfterRepaySellOrder() public {
        vm.warp(DAY);
        depositSellOrder(Alice, 20, 100);
        vm.warp(2 * DAY);
        depositBuyOrder(Bob, 6000, 120);
        vm.warp(4 * DAY);
        borrow(Bob, Alice_Order, 15);
        uint256 totalQuoteAssets = book.totalQuoteAssets();
        uint256 totalBaseAssets = book.totalBaseAssets();
        uint256 totalQuoteBorrow = book.totalQuoteBorrow();
        // uint256 totalBaseBorrow = book.totalBaseBorrow();
        uint256 buyOrderTimeWeightedRate = book.getTimeWeightedRate(BuyOrder);
        uint256 sellOrderTimeWeightedRate = book.getTimeWeightedRate(SellOrder);
        uint256 buyOrderinstantRate = book.getInstantRate(BuyOrder);
        uint256 sellOrderinstantRate = book.getInstantRate(SellOrder);
        vm.warp(369 * DAY);
        repay(Bob, Bob_Position, 10);
        assertEq(book.getTimeWeightedRate(BuyOrder), buyOrderTimeWeightedRate + 365 * DAY * buyOrderinstantRate);
        assertEq(book.getTimeWeightedRate(SellOrder), sellOrderTimeWeightedRate + 365 * DAY * sellOrderinstantRate);
        assertEq(book.totalQuoteAssets(), totalQuoteAssets);
        assertEq(book.totalBaseAssets(), totalBaseAssets);
        assertEq(book.totalQuoteBorrow(), totalQuoteBorrow);
        // assertEq(book.totalBaseBorrow(), totalBaseBorrow - 10 * WAD);
        assertEq(book.getUtilizationRate(BuyOrder), 0);
        assertEq(book.getUtilizationRate(SellOrder), book.totalBaseBorrow() * WAD / book.totalBaseAssets());
        checkInstantRate(BuyOrder);
        checkInstantRate(SellOrder);
    }
    
    function test_MultipleActionsTrackingIRM() public {
        vm.warp(0); // setting starting timestamp to 0
        checkInstantRate(BuyOrder);
        checkInstantRate(SellOrder);
        vm.warp(DAY);
        depositBuyOrder(Alice, 6000, 100);
        checkInstantRate(BuyOrder);
        checkInstantRate(SellOrder);
        vm.warp(2 * DAY);
        depositSellOrder(Bob, 60, 120);
        checkInstantRate(BuyOrder);
        checkInstantRate(SellOrder);
        vm.warp(3 * DAY);
        withdraw(Alice, Alice_Order, 2000);
        checkInstantRate(BuyOrder);
        checkInstantRate(SellOrder);
        vm.warp(4 * DAY);
        borrow(Bob, Alice_Order, 1500);
        checkInstantRate(BuyOrder);
        checkInstantRate(SellOrder);
        vm.warp(369 * DAY);
        repay(Bob, Bob_Position, 1000);
        checkInstantRate(BuyOrder);
        checkInstantRate(SellOrder);
        vm.warp(370 * DAY);
        take(Carol, Alice_Order, 1000);
    }
}
