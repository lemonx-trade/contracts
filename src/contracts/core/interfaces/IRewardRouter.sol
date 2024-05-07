// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

interface IRewardRouter {
    function feeLlpTracker() external view returns (address);
    function executeMintRequests(uint256 endIndex, address payable feeReceiver) external returns (uint256);
    function executeBurnRequests(uint256 endIndex, address payable feeReceiver) external returns (uint256);
    function mintAccountIdx(address user) external returns (uint256);
    function burnAccountIdx(address user) external returns (uint256);
}
