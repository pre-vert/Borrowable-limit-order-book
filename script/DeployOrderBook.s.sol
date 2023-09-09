// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {Token} from "../src/Token.sol";
import {OrderBook} from "../src/OrderBook.sol";
import {console} from "forge-std/console.sol";

contract DeployOrderBook is Script {
    function run() external returns (OrderBook, Token, Token) {
        vm.startBroadcast();
        Token baseToken = new Token("BaseToken", "BTK");
        Token quoteToken = new Token("QuoteToken", "QTK");
        OrderBook orderBook = new OrderBook(
            address(quoteToken),
            address(baseToken)
        );
        vm.stopBroadcast();
        return (orderBook, quoteToken, baseToken);
    }
}
