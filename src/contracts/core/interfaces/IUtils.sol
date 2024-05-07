// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

interface IUtils {
    function validateIncreasePosition(
        address _account,
        address _collateralToken,
        address _indexToken,
        uint256 _sizeDelta,
        bool _isLong
    ) external view;
    function validateDecreasePosition(
        address _account,
        address _collateralToken,
        address _indexToken,
        uint256 _sizeDelta,
        bool _isLong,
        address _receiver
    ) external view;
    function validateLiquidation(
        address _account,
        address _collateralToken,
        address _indexToken,
        bool _isLong,
        bool _raise,
        uint256 _markPrice
    ) external returns (uint256, int256);
    function getEntryBorrowingRate(address _collateralToken, address _indexToken, bool _isLong)
        external
        view
        returns (uint256);
    function getEntryFundingRate(address _collateralToken, address _indexToken, bool _isLong)
        external
        view
        returns (int256);
    function getPositionFee(
        address _account,
        address _collateralToken,
        address _indexToken,
        bool _isLong,
        uint256 _sizeDelta,
        uint256 _collateralDeltaUsd
    ) external view returns (uint256);
    function getBorrowingFee(
        address _account,
        address _collateralToken,
        address _indexToken,
        bool _isLong,
        uint256 _size,
        uint256 _entryBorrowingRate
    ) external view returns (uint256);
    function getBuyUsdlFeeBasisPoints(address _token, uint256 _usdgAmount) external view returns (uint256);
    function getSellUsdlFeeBasisPoints(address _token, uint256 _usdgAmount) external view returns (uint256);
    function getFeeBasisPoints(address _token, uint256 _usdgDelta, uint256 _feeBasisPoints, bool _increment)
        external
        view
        returns (uint256);
    function getDelta(
        address _indexToken,
        uint256 _size,
        uint256 _averagePrice,
        uint256 _nextPrice,
        bool _isLong,
        uint256 _lastIncreasedTime
    ) external view returns (bool, uint256);
    function getNextGlobalAveragePrice(
        address _account,
        address _collateralToken,
        address _indexToken,
        uint256 _nextPrice,
        uint256 _sizeDelta,
        bool _isLong,
        bool _isIncrease
    ) external view returns (uint256);
    function getNextAveragePrice(
        address _indexToken,
        uint256 _size,
        uint256 _averagePrice,
        bool _isLong,
        uint256 _nextPrice,
        uint256 _sizeDelta,
        uint256 _lastIncreasedTime
    ) external view returns (uint256);
    function adjustForDecimals(uint256 _amount, address _tokenDiv, address _tokenMul) external view returns (uint256);
    function getGlobalPositionDelta(address _token, uint256 size, bool _isLong) external view returns (bool, uint256);
    function getAum(bool maximise) external view returns (uint256);
    function getAumInUsdl(bool maximise) external view returns (uint256);
    function validatePosition(uint256 _size, uint256 _collateral) external view;

    function getNextBorrowingRate(address _indexToken, bool _isLong) external view returns (uint256);
    function getMinPrice(address _token) external view returns (uint256);
    function tokenToUsdMin(address _token, uint256 _tokenAmount) external view returns (uint256);
    function getMaxPrice(address _token) external view returns (uint256);
    function usdToTokenMin(address _token, uint256 _usdAmount) external view returns (uint256);
    function usdToTokenMax(address _token, uint256 _usdAmount) external view returns (uint256);
    function updateCumulativeBorrowingRate(address _indexToken)
        external
        view
        returns (uint256 borrowingTime, uint256 borrowingRateForLongs, uint256 borrowingRateForShorts);
    function updateCumulativeFundingRate(address _indexToken, uint256 lastFundingTime)
        external
        returns (uint256 lastFundingUpdateTime, int256 fundingRateForLong, int256 fundingRateForShort);
    function getRedemptionAmount(address _token, uint256 _usdlAmount) external view returns (uint256);
    function collectMarginFees(
        address _account,
        address _collateralToken,
        address _indexToken,
        bool _isLong,
        uint256 _sizeDelta,
        uint256 _size,
        uint256 _entryBorrowingRate,
        int256 _entryFundingRate,
        uint256 _collateralDeltaUsd
    ) external returns (int256 feeUsd);
    function getTPPrice(
        uint256 sizeDelta,
        bool isLong,
        uint256 markPrice,
        uint256 _maxTPAmount,
        address collateralToken
    ) external returns (uint256);
    function calcLiquidationFee(uint256 size, address indexToken) external returns (uint256);
    function setPriceFeed(address _pricefeed) external;
    function getOI(address _token, bool _isLong) external view returns (uint256);
    function getLPAmountInUSD() external view returns (uint256 lpAmountInUSD);
    function getTotalOI() external view returns (uint256 totalOI);
    function maintanenceMargin(address token) external view returns (uint256);
    function tokenPremiumPositionFee(address token) external view returns (int256);
}
