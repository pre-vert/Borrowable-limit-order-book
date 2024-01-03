// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.20;

uint256 constant WAD = 1e18;

/// @title MathLib
/// @notice Library to manage fixed-point arithmetic

library MathLib {

    /// @dev (x * y) / WAD rounded up.
    function wMulUp(uint256 x, uint256 y) internal pure returns (uint256) {
        return mulDivUp(x, y, WAD);
    }

    /// @dev (x * y) / WAD rounded down.
    function wMulDown(uint256 x, uint256 y) internal pure returns (uint256) {
        return mulDivDown(x, y, WAD);
    }

    /// @dev (x * WAD) / y rounded down.
    function wDivDown(uint256 x, uint256 y) internal pure returns (uint256) {
        return mulDivDown(x, WAD, y);
    }

    /// @dev (x * WAD) / y rounded up.
    function wDivUp(uint256 x, uint256 y) internal pure returns (uint256) {
        return mulDivUp(x, WAD, y);
    }

    /// @dev (x * y) / d rounded down.
    function mulDivDown(uint256 x, uint256 y, uint256 d) internal pure returns (uint256) {
        return (x * y) / d;
    }

    /// @dev (x * y) / d rounded up.
    function mulDivUp(uint256 x, uint256 y, uint256 d) internal pure returns (uint256) {
        return (x * y + (d - 1)) / d;
    }

    /// @dev The sum of the first three non-zero terms of a Taylor expansion of e^(nx) - 1,
    /// to approximate a continuous compound interest rate.
    
    function wTaylorCompoundedDown(uint256 timeWeightedRateDiff) internal pure returns (uint256) {
        uint256 firstTerm = timeWeightedRateDiff;
        uint256 secondTerm = mulDivDown(firstTerm, firstTerm, 2 * WAD);
        uint256 thirdTerm = mulDivDown(secondTerm, firstTerm, 3 * WAD);
        return firstTerm + secondTerm + thirdTerm;
    }

    function wTaylorCompoundedUp(uint256 timeWeightedRateDiff) internal pure returns (uint256) {
        uint256 firstTerm = timeWeightedRateDiff;
        uint256 secondTerm = mulDivUp(firstTerm, firstTerm, 2 * WAD);
        uint256 thirdTerm = mulDivUp(secondTerm, firstTerm, 3 * WAD);
        return firstTerm + secondTerm + thirdTerm;
    }

    function minimum(uint256 _a, uint256 _b) internal pure returns (uint256) {
        return _a < _b ? _a : _b;
    }

    function maximum(uint256 _a, uint256 _b) internal pure returns (uint256) {
        return _a < _b ? _b : _a;
    }
}
