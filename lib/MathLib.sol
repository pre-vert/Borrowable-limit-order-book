// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

library MathLib {
    function absolu(
        uint256 val1,
        uint256 val2
    ) public pure returns (uint256 absoluteValue) {
        if (val1 >= val2) {
            absoluteValue = val1 - val2;
        } else {
            absoluteValue = val2 - val1;
        }
    }
}
