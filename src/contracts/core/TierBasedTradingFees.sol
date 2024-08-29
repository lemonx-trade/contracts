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

    function setTierUpdater(address account, bool status) external onlyGov validAddress(account) {
        tierUpdater[account] = status;
    }

    function setTierBasedTradingBasisPoints(address trader, uint256 basisPoints)
        external
        validAddress(trader)
        onlyTierUpdater
    {
        tierBasedTradingBasisPoints[trader] = basisPoints;
    }
}
