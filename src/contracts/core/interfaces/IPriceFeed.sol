// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

interface IPriceFeed {
    function getMaxPriceOfToken(address _token) external view returns (uint256);
    function getMinPriceOfToken(address _token) external view returns (uint256);
    function getPriceOfToken(address _token) external view returns (uint256);
}
