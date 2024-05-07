// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "../libraries/token/MintableBaseToken.sol";

contract LLP is MintableBaseToken {
    constructor() MintableBaseToken("LemonX LP", "LemonLP", 0) {}

    function id() external pure returns (string memory _name) {
        return "LemonLP";
    }
}
