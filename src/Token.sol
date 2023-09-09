// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract Token is ERC20 {
    uint256 public constant INITIAL_SUPPLY = 1000000 * 10 ** 18;

    constructor(
        string memory _name,
        string memory _symbol
    ) ERC20(_name, _symbol) {
        _mint(msg.sender, INITIAL_SUPPLY);
    }

    function getInitialSupply() public pure returns (uint256) {
        return (INITIAL_SUPPLY);
    }
}
