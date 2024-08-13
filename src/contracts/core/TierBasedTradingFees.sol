// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "../access/Governable.sol";
import "./interfaces/ITierBasedTradingFees.sol";

contract TierBasedTradingFees is ITierBasedTradingFees, Governable {
    mapping(address => bool) public tierUpdater;
    mapping(address => uint256) public override tierBasedTradingBasisPoints;

    modifier onlyTierUpdater() {
        require(tierUpdater[msg.sender], "Utils: Not updater");
        _;
    }

    modifier validAddress(address _addr) {
        require(_addr != address(0), "ZERO");
        require(_addr != 0x000000000000000000000000000000000000dEaD, "DEAD");
        _;
    }
    //  L4 zero or dead address check

    function setTierUpdater(address account, bool status) external onlyGov validAddress(account) {
        tierUpdater[account] = status;
    }
    //  L4 zero or dead address check

    function setTierBasedTradingBasisPoints(address trader, uint256 basisPoints)
        external
        onlyTierUpdater
        validAddress(trader)
    {
        tierBasedTradingBasisPoints[trader] = basisPoints;
    }
}
