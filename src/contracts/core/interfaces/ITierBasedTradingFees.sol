// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

interface ITierBasedTradingFees {
    function tierBasedTradingBasisPoints(address account) external view returns (uint256);
}
