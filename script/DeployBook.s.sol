// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {Token} from "../src/Token.sol";
import {Book} from "../src/Book.sol";
import {console} from "forge-std/console.sol";

contract DeployBook is Script {

    uint256 wad = 10**18;
    // limit price of the genesis pool, either a buy order or sell order pool, not to be confused with price feed
    uint256 genesisLimitPrice = 4000 * wad;
    // Price step for placing orders: +/- 10%
    uint256 priceStep = 11 * wad / 10;
    // Minimum deposited base tokens : 0.2 ETH
    uint256 public minDepositBase = wad / 5; 
    // Minimum deposited quote tokens : 200 USDC
    uint256 public minDepositQuote = 200 * wad;
    // liquidation LTV = 96%
    uint256 public liquidationLTV = 96 * wad / 100;

    function run() external
        returns (
            Book,
            Token,
            Token,
            uint256,
            uint256,
            uint256,
            uint256
            // uint256
        ) {
        vm.startBroadcast();
        Token baseToken = new Token("BaseToken", "BTK");
        Token quoteToken = new Token("QuoteToken", "QTK");
        Book book = new Book(
            address(quoteToken),
            address(baseToken),
            genesisLimitPrice,
            priceStep,
            minDepositBase,
            minDepositQuote,
            liquidationLTV
        );
        vm.stopBroadcast();
        return (
            book,
            quoteToken,
            baseToken,
            genesisLimitPrice,
            minDepositBase,
            minDepositQuote,
            liquidationLTV
        );
    }
}
