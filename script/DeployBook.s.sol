// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {Token} from "../src/Token.sol";
import {Book} from "../src/Book.sol";
import {console} from "forge-std/console.sol";

contract DeployBook is Script {

    uint256 initialPrice = 100;

    function run() external returns (Book, Token, Token, uint256) {
        vm.startBroadcast();
        Token baseToken = new Token("BaseToken", "BTK");
        Token quoteToken = new Token("QuoteToken", "QTK");
        Book book = new Book(address(quoteToken), address(baseToken), initialPrice);
        vm.stopBroadcast();
        return (book, quoteToken, baseToken, initialPrice);
    }
}
