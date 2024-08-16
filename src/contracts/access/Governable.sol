// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

contract Governable {
    address public gov;

    constructor() {
        gov = msg.sender;
    }

    modifier onlyGov() {
        require(msg.sender == gov, "Governable: forbidden");
        _;
    }

    modifier validAddress(address _addr) {
        require(_addr != address(0), "ZERO");
        require(_addr != 0x000000000000000000000000000000000000dEaD, "DEAD");
        _;
    }

    function setGov(address _gov) external onlyGov {
        gov = _gov;
    }
}
