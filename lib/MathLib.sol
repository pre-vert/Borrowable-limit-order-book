// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

library MathLib {
    function distance(
        uint256 _val1,
        uint256 _val2
    ) public pure returns (uint256 gap) {
        gap = _val1 >= _val2 ? _val1 - _val2 : _val2 - _val1;
    }
}
