// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "./IUtils.sol";
import "./../../libraries/utils/Structs.sol";

interface IVault {
    struct FundingFeeData {
        uint256 fundingRateFactor;
        uint256 fundingInterval;
        uint256 fundingExponent;
    }

    struct BorrowingFeeData {
        uint256 borrowingRateFactor;
        uint256 borrowingInterval;
        uint256 borrowingExponent;
    }

    function isInitialized() external view returns (bool);

    function setUtils(address _utils) external;

    function usdl() external view returns (address);

    function maxLeverage(address _token) external view returns (uint256);

    function oiImbalanceThreshold(address _token) external view returns (uint256);

    function gov() external view returns (address);

    function ceaseTradingActivity() external view returns (bool);

    function ceaseLPActivity() external view returns (bool);

    function minProfitTime() external view returns (uint256);

    function hasDynamicFees() external view returns (bool);

    function inManagerMode() external view returns (bool);

    function inPrivateLiquidationMode() external view returns (bool);

    function maxGasPrice() external view returns (uint256);

    function isLiquidator(address _account) external view returns (bool);

    function isManager(address _account) external view returns (bool);

    function minProfitBasisPoints(address _token) external view returns (uint256);

    function tokenBalances(address _token) external view returns (uint256);

    function lastBorrowingTimes(address _token) external view returns (uint256);

    function lastFundingTimes(address _token) external view returns (uint256);

    function setMaxLeverage(uint256 _maxLeverage, address _token) external;

    function setInManagerMode(bool _inManagerMode) external;

    function setManager(address _manager, bool _isManager) external;

    function setMaxGasPrice(uint256 _maxGasPrice) external;

    function setMaxGlobalShortSize(address _token, uint256 _amount) external;

    function setMaxGlobalLongSize(address _token, uint256 _amount) external;

    function setInPrivateLiquidationMode(bool _inPrivateLiquidationMode) external;

    function setLiquidator(address _liquidator, bool _isActive) external;

    function setBorrowingRate(
        address token,
        uint256 _borrowingInterval,
        uint256 _borrowingRateFactor,
        uint256 borrowingExponent
    ) external;

    function setFundingRate(
        address token,
        uint256 _fundingInterval,
        uint256 _fundingRateFactor,
        uint256 fundingExponent
    ) external;

    function setFees(
        uint256 _mintBurnFeeBasisPoints,
        uint256 _marginFeeBasisPoints,
        uint256 _liquidationFeeUsd,
        uint256 liquidationFactor,
        uint256 _minProfitTime,
        bool _hasDynamicFees
    ) external;

    function setTokenConfig(
        address _token,
        uint256 _tokenDecimals,
        uint256 _minProfitBps,
        bool _isStable,
        bool _canBeCollateralToken,
        bool _canBeIndexToken,
        uint256 _maxLeverage
    ) external;

    function setCeaseLPActivity(bool _cease) external;

    function setCeaseTradingActivity(bool _cease) external;

    function setPriceFeed(address _priceFeed) external;

    function withdrawFees(address _token, address _receiver) external returns (uint256);

    function setGov(address _gov) external;

    function directPoolDeposit(address _token) external;

    function buyUSDL(address _token, address _receiver) external returns (uint256);

    function sellUSDL(address _token, address _receiver) external returns (uint256);

    function increasePosition(
        address _account,
        address _collateralToken,
        address _indexToken,
        uint256 _sizeDelta,
        bool _isLong
    ) external;

    function decreasePosition(
        address _account,
        address _collateralToken,
        address _indexToken,
        uint256 _sizeDelta,
        bool _isLong,
        address _receiver
    ) external returns (uint256);

    function liquidatePosition(
        address _account,
        address _collateralToken,
        address _indexToken,
        bool _isLong,
        address _feeReceiver
    ) external;

    function liquidatePosition(bytes32 key, address feeReceiver) external;

    function priceFeed() external view returns (address);

    function fundingRateFactor(address) external view returns (uint256, uint256, uint256);

    function borrowingRateFactor(address) external view returns (uint256, uint256, uint256);

    function cumulativeBorrowingRatesForLongs(address _token) external view returns (uint256);

    function cumulativeBorrowingRatesForShorts(address _token) external view returns (uint256);

    function cumulativeFundingRatesForLongs(address _token) external view returns (int256);

    function cumulativeFundingRatesForShorts(address _token) external view returns (int256);

    function liquidationFeeUsd() external view returns (uint256);

    function liquidationFactor() external view returns (uint256);

    function mintBurnFeeBasisPoints() external view returns (uint256);

    function marginFeeBasisPoints() external view returns (uint256);

    function allWhitelistedTokensLength() external view returns (uint256);

    function allWhitelistedTokens(uint256) external view returns (address);

    function whitelistedTokens(address _token) external view returns (bool);

    function stableTokens(address _token) external view returns (bool);

    function feeReserves(address _token) external view returns (uint256);

    function globalShortSizes(address _token) external view returns (uint256);

    function globalLongSizes(address _token) external view returns (uint256);

    function globalShortAveragePrices(address _token) external view returns (uint256);

    function globalLongAveragePrices(address _token) external view returns (uint256);

    function maxGlobalShortSizesBps(address _token) external view returns (uint256);

    function maxGlobalLongSizesBps(address _token) external view returns (uint256);

    function tokenDecimals(address _token) external view returns (uint256);

    function canBeIndexToken(address _token) external view returns (bool);

    function canBeCollateralToken(address _token) external view returns (bool);

    function poolAmounts(address _token) external view returns (uint256);

    function setGlobalLongSizesLimitBps(address token, uint256 amount) external;

    function setGlobalShortSizesLimitBps(address token, uint256 amount) external;

    function setPoolSafetyFactorInBps(uint256 _poolSafetyFactorInBps) external;

    function getPosition(address _account, address _collateralToken, address _indexToken, bool _isLong)
        external
        view
        returns (StructsUtils.Position memory);

    function globalShortSizesLimitBps(address _token) external view returns (uint256);

    function globalLongSizesLimitBps(address _token) external view returns (uint256);
}
