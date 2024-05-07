// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

interface IReaderContract {
    function cumulativeBorrowingRate(address _indexToken, uint256 price, uint256 usdcPrice)
        external
        view
        returns (uint256, uint256, uint256);

    function cumulativeFundingRate(address _indexToken, uint256 price)
        external
        view
        returns (uint256, int256, int256);

    function getAumInUSDL(uint256[] memory markPrice) external view returns (uint256);

    function getNextBorrowingRate(address _indexToken, bool _isLong, uint256 price, uint256 usdcPrice)
        external
        view
        returns (uint256);

    function getNextFundingRate(address _indexToken, uint256 price) external view returns (int256, int256);

    function getOI(uint256 price, address _token, bool _isLong) external view returns (uint256 finalOI);
}
