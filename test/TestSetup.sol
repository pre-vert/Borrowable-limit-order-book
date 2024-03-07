// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import {console} from "../lib/forge-std/src/Test.sol";
import {Setup} from "./Setup.sol";
import {StdCheats} from "forge-std/StdCheats.sol";

contract testSetup is Setup {
    
    function testTransferTokenUSER() public {
        assertEq(ReceivedQuoteToken, quoteToken.balanceOf(Alice));
        assertEq(ReceivedBaseToken, baseToken.balanceOf(Alice));
    }

}
