// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "../libraries/token/IERC20.sol";
import "./interfaces/IVault.sol";
import "./interfaces/IUtils.sol";
import "./interfaces/IPriceFeed.sol";
import "../access/Governable.sol";
import "../libraries/utils/Structs.sol";
import "./interfaces/ITierBasedTradingFees.sol";

contract Utils is IUtils, Governable {
    IVault public vault;
    IPriceFeed public priceFeed;
    ITierBasedTradingFees public tierBasedTradingFees;

    uint256 public constant MAX_INT256 = uint256(type(int256).max);

    uint256 public constant BASIS_POINTS_DIVISOR = 10000;
    uint256 public BORROWING_RATE_PRECISION = 1000000000000;
    uint256 constant POSITION_FEE_SCALING_FACTOR = 1000000;
    int256 public FUNDING_RATE_PRECISION = 1000000000000;
    uint256 public constant USDL_DECIMALS = 18;
    uint256 public constant PRICE_PRECISION = 10 ** 30;
    uint256 public tierBorrowingRateFactor = 166666;
    uint256 public tier1Size = 1000 * 10 ** 30;
    uint256 public tier2Size = 10000 * 10 ** 30;
    uint256 public tier3Size = 100000 * 10 ** 30;
    uint256 public tier1Factor = 25;
    uint256 public tier2Factor = 20;
    uint256 public tier3Factor = 8;
    uint256 public tierBorrowingRateStartTime = 1702988048;
    int256 public fundingFactorForLessOISide = 125;
    int256 public fundingFactorForHighOISide = 1250;
    mapping(address => uint256) public override maintanenceMargin;
    mapping(address => int256) public override tokenPremiumPositionFee;

    event LemonXFees(
        address account,
        address indexToken,
        bool isLong,
        uint256 sizeDelta,
        uint256 entryBorrowingRate,
        int256 entryFundingRate,
        int256 tradingFee,
        int256 borrowingFee,
        int256 fundingfee,
        uint256 timestamp
    );

    constructor(IVault _vault, IPriceFeed _pricefeed, address _tierBasedTradingFees) {
        vault = _vault;
        priceFeed = _pricefeed;
        tierBasedTradingFees = ITierBasedTradingFees(_tierBasedTradingFees);
    }

    function setTier1Size(uint256 _tier1Size) external onlyGov {
        tier1Size = _tier1Size;
    }

    function setTier2Size(uint256 _tier2Size) external onlyGov {
        tier2Size = _tier2Size;
    }

    function setTier3Size(uint256 _tier3Size) external onlyGov {
        tier3Size = _tier3Size;
    }

    function setTier1Factor(uint256 _tier1Factor) external onlyGov {
        tier1Factor = _tier1Factor;
    }

    function setTier2Factor(uint256 _tier2Factor) external onlyGov {
        tier2Factor = _tier2Factor;
    }

    function setTier3Factor(uint256 _tier3Factor) external onlyGov {
        tier3Factor = _tier3Factor;
    }

    function setTierBorrowingRateFactor(uint256 _tierBorrowingRateFactor) external onlyGov {
        tierBorrowingRateFactor = _tierBorrowingRateFactor;
    }

    function setFundingFactorForLessOISide(int256 _fundingFactorForLessOISide) external onlyGov {
        fundingFactorForLessOISide = _fundingFactorForLessOISide;
    }

    function setFundingFactorForHighOISide(int256 _fundingFactorForHighOISide) external onlyGov {
        fundingFactorForHighOISide = _fundingFactorForHighOISide;
    }

    function setTierBasedTradingFees(address _tierBasedTradingFees)
        external
        onlyGov
        validAddress(_tierBasedTradingFees)
    {
        tierBasedTradingFees = ITierBasedTradingFees(_tierBasedTradingFees);
    }

    function setVault(IVault _vault) external onlyGov validAddress(address(_vault)) {
        vault = _vault;
    }

    function setPriceFeed(address _pricefeed) external onlyGov validAddress(_pricefeed) {
        priceFeed = IPriceFeed(_pricefeed);
    }

    function setBorrowingRatePrecision(uint256 _precision) external onlyGov {
        BORROWING_RATE_PRECISION = _precision;
    }

    function setFundingRatePrecision(int256 _precision) external onlyGov {
        FUNDING_RATE_PRECISION = _precision;
    }

    function setTierBorrowingRateStartTime(uint256 _tierBorrowingRateStartTime) external onlyGov {
        tierBorrowingRateStartTime = _tierBorrowingRateStartTime;
    }

    function setMaintanenceMargin(address _indexToken, uint256 _maintanenceMargin) external onlyGov {
        maintanenceMargin[_indexToken] = _maintanenceMargin;
    }

    function setTokenPremiumPositionFee(address _indexToken, int256 _basisPoints) external onlyGov {
        tokenPremiumPositionFee[_indexToken] = _basisPoints;
    }

    function validateIncreasePosition(
        address, /*_account*/
        address, /*_collateralToken*/
        address, /*_indexToken*/
        uint256, /* _sizeDelta*/
        bool /* _isLong*/
    ) external view override {
        // no additional validations
    }
    // Will we be implementing this validation function
    function validateDecreasePosition(
        address, /* _account */
        address, /* _collateralToken */
        address, /* _indexToken */
        uint256, /* _sizeDelta */
        bool, /* _isLong */
        address /* _receiver */
    ) external view override {
        // no additional validations
    }

    function getPosition(address _account, address _collateralToken, address _indexToken, bool _isLong)
        internal
        view
        returns (StructsUtils.Position memory)
    {
        StructsUtils.Position memory position = vault.getPosition(_account, _collateralToken, _indexToken, _isLong);
        return position;
    }

    function validateLiquidation(
        address _account,
        address _collateralToken,
        address _indexToken,
        bool _isLong,
        bool _raise,
        uint256 _markPrice
    ) external override returns (uint256, int256) {
        StructsUtils.Position memory position = getPosition(_account, _collateralToken, _indexToken, _isLong);
        IVault _vault = vault;

        (bool hasProfit, uint256 pnl) =
            getDelta(_indexToken, position.size, position.averagePrice, _markPrice, _isLong, position.lastIncreasedTime);
        int256 borrowingFee = int256(
            getBorrowingFee(
                _account, _collateralToken, _indexToken, _isLong, position.size, position.entryBorrowingRate
            )
        );
        int256 tradingFee =
            int256(getPositionFee(_account, _collateralToken, _indexToken, _isLong, position.size, position.collateral));

        int256 fundingFee =
            getFundingFee(_account, _collateralToken, _indexToken, _isLong, position.size, position.entryFundingRate);
        int256 marginFees = tradingFee + borrowingFee + fundingFee;
        // 1. factor in fees
        int256 delta;
        delta -= marginFees;
        // 2. factor in pnl
        if (hasProfit) {
            delta += int256(pnl);
        } else {
            delta -= int256(pnl);
        }

        if (delta < 0 && position.collateral < uint256(abs(delta))) {
            if (_raise) {
                revert("Utils: losses exceed collateral");
            }
            return (1, marginFees);
        }

        uint256 remainingCollateral = position.collateral;
        if (delta < 0) {
            remainingCollateral = position.collateral - uint256(abs(delta));
        } else {
            remainingCollateral = position.collateral + uint256(abs(delta));
        }

        if (remainingCollateral < calcLiquidationFee(position.size, position.indexToken)) {
            if (_raise) {
                revert("Vault: liquidation fees exceed collateral");
            }
            emit LemonXFees(
                _account,
                _indexToken,
                _isLong,
                position.size,
                position.entryBorrowingRate,
                position.entryFundingRate,
                tradingFee,
                borrowingFee,
                fundingFee,
                block.timestamp
            );
            return (1, marginFees);
        }

        if (remainingCollateral * (BASIS_POINTS_DIVISOR) <= position.size * (maintanenceMargin[position.indexToken])) {
            if (_raise) {
                revert("Vault: maxLeverage exceeded");
            }
            emit LemonXFees(
                _account,
                _indexToken,
                _isLong,
                position.size,
                position.entryBorrowingRate,
                position.entryFundingRate,
                tradingFee,
                borrowingFee,
                fundingFee,
                block.timestamp
            );
            return (1, marginFees);
        }

        return (0, marginFees);
    }

    function getEntryBorrowingRate(address, /*_collateralToken*/ address _indexToken, bool _isLong)
        public
        view
        override
        returns (uint256)
    {
        return _isLong
            ? vault.cumulativeBorrowingRatesForLongs(_indexToken)
            : vault.cumulativeBorrowingRatesForShorts(_indexToken);
    }

    function getEntryFundingRate(address, /*_collateralToken*/ address _indexToken, bool _isLong)
        public
        view
        override
        returns (int256)
    {
        return _isLong
            ? vault.cumulativeFundingRatesForLongs(_indexToken)
            : vault.cumulativeFundingRatesForShorts(_indexToken);
    }

    function getPositionFee(
        address _account,
        address, /* _collateralToken */
        address _indexToken,
        bool, /* _isLong */
        uint256 _sizeDelta,
        uint256 _collateralDeltaUsd
    ) public view override returns (uint256) {
        if (_sizeDelta == 0) {
            return 0;
        }

        uint256 leverage = _sizeDelta / _collateralDeltaUsd;
        uint256 feeBasisPoints = vault.marginFeeBasisPoints();
        if (leverage > 40) {
            feeBasisPoints = 2;
        } else if (leverage > 30) {
            feeBasisPoints = 5;
        } else if (leverage > 20) {
            feeBasisPoints = 8;
        }
        uint256 totalPositionFee;
        if (tokenPremiumPositionFee[_indexToken] > 0) {
            totalPositionFee = feeBasisPoints + uint256(tokenPremiumPositionFee[_indexToken]);
        } else {
            totalPositionFee = feeBasisPoints - uint256(-1 * tokenPremiumPositionFee[_indexToken]);
        }
        uint256 positionFeeAfteDiscount =
            (totalPositionFee * (100 - tierBasedTradingFees.tierBasedTradingBasisPoints(_account))) / 100;

        uint256 afterFeeUsd = (_sizeDelta * (BASIS_POINTS_DIVISOR - positionFeeAfteDiscount)) / (BASIS_POINTS_DIVISOR);
        return _sizeDelta - (afterFeeUsd);
    }

    function getBorrowingFee(
        address _account,
        address _collateralToken,
        address _indexToken,
        bool _isLong,
        uint256 _size,
        uint256 _entryBorrowingRate
    ) public view override returns (uint256) {
        if (_size == 0) {
            return 0;
        }
        StructsUtils.Position memory position = vault.getPosition(_account, _collateralToken, _indexToken, _isLong);

        uint256 currentCumulativeBorrowingRate = _isLong
            ? vault.cumulativeBorrowingRatesForLongs(_indexToken)
            : vault.cumulativeBorrowingRatesForShorts(_indexToken);
        uint256 borrowingRate = currentCumulativeBorrowingRate - (_entryBorrowingRate);
        if (borrowingRate == 0) {
            return 0;
        }
        uint256 amplificationFactor;
        if (position.lastIncreasedTime < tierBorrowingRateStartTime) {
            amplificationFactor = 1;
        } else if (_size <= tier1Size) {
            amplificationFactor = tier1Factor;
        } else if (_size <= tier2Size) {
            amplificationFactor = tier2Factor;
        } else {
            amplificationFactor = tier3Factor;
        }

        return (_size * (borrowingRate) * amplificationFactor) / (BORROWING_RATE_PRECISION);
    }

    function getBuyUsdlFeeBasisPoints(address _token, uint256 _usdlAmount) public view override returns (uint256) {
        return getFeeBasisPoints(_token, _usdlAmount, vault.mintBurnFeeBasisPoints(), true);
    }

    function getSellUsdlFeeBasisPoints(address _token, uint256 _usdlAmount) public view override returns (uint256) {
        return getFeeBasisPoints(_token, _usdlAmount, vault.mintBurnFeeBasisPoints(), false);
    }

    function getFeeBasisPoints(
        address, /*_token*/
        uint256, /*_usdlDelta*/
        uint256 _feeBasisPoints,
        bool /*_increment*/
    ) public view override returns (uint256) {
        if (!vault.hasDynamicFees()) {
            return _feeBasisPoints;
        }
        return _feeBasisPoints;
    }

    function getNextAveragePrice(
        address _indexToken,
        uint256 _size,
        uint256 _averagePrice,
        bool _isLong,
        uint256 _nextPrice,
        uint256 _sizeDelta,
        uint256 _lastIncreasedTime
    ) public view returns (uint256) {
        (bool hasProfit, uint256 delta) =
            getDelta(_indexToken, _size, _averagePrice, _nextPrice, _isLong, _lastIncreasedTime);
        uint256 nextSize = _size + (_sizeDelta);
        uint256 divisor;
        if (_isLong) {
            divisor = hasProfit ? nextSize + (delta) : nextSize - (delta);
        } else {
            divisor = hasProfit ? nextSize - (delta) : nextSize + (delta);
        }
        return (_nextPrice * (nextSize)) / (divisor);
    }

    function getDelta(
        address _indexToken,
        uint256 _size,
        uint256 _averagePrice,
        uint256 _nextPrice,
        bool _isLong,
        uint256 _lastIncreasedTime
    ) public view returns (bool, uint256) {
        _validate(_averagePrice > 0, "Vault: averagePrice should be > 0");
        uint256 price = _nextPrice;
        uint256 priceDelta = _averagePrice > price ? _averagePrice - (price) : price - (_averagePrice);
        uint256 delta = (_size * (priceDelta)) / (_averagePrice);

        bool hasProfit;
        if (_isLong) {
            hasProfit = price > _averagePrice;
        } else {
            hasProfit = _averagePrice > price;
        }

        // if the minProfitTime has passed then there will be no min profit threshold
        // the min profit threshold helps to prevent front-running issues
        uint256 minBps =
            block.timestamp > _lastIncreasedTime + (vault.minProfitTime()) ? 0 : vault.minProfitBasisPoints(_indexToken);
        if (hasProfit && delta * (BASIS_POINTS_DIVISOR) <= _size * (minBps)) {
            delta = 0;
        }

        return (hasProfit, delta);
    }

    function _validate(bool _condition, string memory errorMessage) private pure {
        require(_condition, errorMessage);
    }

    function getNextGlobalAveragePrice(
        address _account,
        address _collateralToken,
        address _indexToken,
        uint256 _nextPrice,
        uint256 _sizeDelta,
        bool _isLong,
        bool _isIncrease
    ) public view returns (uint256) {
        int256 realisedPnl =
            getRealisedPnl(_account, _collateralToken, _indexToken, _sizeDelta, _isIncrease, _isLong, _nextPrice);
        uint256 averagePrice =
            _isLong ? vault.globalLongAveragePrices(_indexToken) : vault.globalShortAveragePrices(_indexToken);
        uint256 priceDelta = averagePrice > _nextPrice ? averagePrice - (_nextPrice) : _nextPrice - (averagePrice);

        uint256 nextSize;
        uint256 delta;
        // avoid stack to deep
        {
            uint256 size = _isLong ? vault.globalLongSizes(_indexToken) : vault.globalShortSizes(_indexToken);
            nextSize = _isIncrease ? size + (_sizeDelta) : size - (_sizeDelta);

            if (nextSize == 0) {
                return 0;
            }

            if (averagePrice == 0) {
                return _nextPrice;
            }
            delta = (size * (priceDelta)) / (averagePrice);
        }

        return _getNextGlobalPositionAveragePrice(averagePrice, _nextPrice, nextSize, delta, realisedPnl, _isLong);
    }

    function getRealisedPnl(
        address _account,
        address _collateralToken,
        address _indexToken,
        uint256 _sizeDelta,
        bool _isIncrease,
        bool _isLong,
        uint256 _nextPrice
    ) public view returns (int256) {
        if (_isIncrease) {
            return 0;
        }
        StructsUtils.Position memory position = vault.getPosition(_account, _collateralToken, _indexToken, _isLong);

        (bool hasProfit, uint256 delta) =
            getDelta(_indexToken, position.size, position.averagePrice, _nextPrice, _isLong, position.lastIncreasedTime);
        // get the proportional change in pnl
        uint256 adjustedDelta = (_sizeDelta * (delta)) / (position.size);
        require(adjustedDelta < MAX_INT256, "Vault: overflow");
        return hasProfit ? int256(adjustedDelta) : -int256(adjustedDelta);
    }

    function _getNextGlobalPositionAveragePrice(
        uint256 _averagePrice,
        uint256 _nextPrice,
        uint256 _nextSize,
        uint256 _delta,
        int256 _realisedPnl,
        bool _isLong
    ) internal pure returns (uint256) {
        bool hasProfit = _isLong ? _nextPrice > _averagePrice : _nextPrice < _averagePrice;
        (uint256 nextDelta, bool _hasProfit) = _getNextDelta(hasProfit, _delta, _realisedPnl);
        uint256 divisor;
        if (_isLong) {
            divisor = _hasProfit ? _nextSize + (nextDelta) : _nextSize - (nextDelta);
        } else {
            divisor = _hasProfit ? _nextSize - (nextDelta) : _nextSize + (nextDelta);
        }

        uint256 nextAveragePrice = (_nextPrice * (_nextSize)) / divisor;

        return nextAveragePrice;
    }

    function _getNextDelta(bool _hasProfit, uint256 _delta, int256 _realisedPnl)
        internal
        pure
        returns (uint256, bool)
    {
        if (_hasProfit) {
            if (_realisedPnl > 0) {
                if (uint256(_realisedPnl) > _delta) {
                    _delta = uint256(_realisedPnl) - (_delta);
                    _hasProfit = false;
                } else {
                    _delta = _delta - (uint256(_realisedPnl));
                }
            } else {
                _delta = _delta + (uint256(-_realisedPnl));
            }
            return (_delta, _hasProfit);
        }

        if (_realisedPnl > 0) {
            _delta = _delta + (uint256(_realisedPnl));
        } else {
            if (uint256(-_realisedPnl) > _delta) {
                _delta = uint256(-_realisedPnl) - (_delta);
                _hasProfit = true;
            } else {
                _delta = _delta - (uint256(-_realisedPnl));
            }
        }
        return (_delta, _hasProfit);
    }

    function adjustForDecimals(uint256 _amount, address _tokenDiv, address _tokenMul) public view returns (uint256) {
        uint256 decimalsDiv = _tokenDiv == vault.usdl() ? USDL_DECIMALS : vault.tokenDecimals(_tokenDiv);
        uint256 decimalsMul = _tokenMul == vault.usdl() ? USDL_DECIMALS : vault.tokenDecimals(_tokenMul);

        return (_amount * (10 ** decimalsMul)) / (10 ** decimalsDiv);
    }

    function getAumInUsdl(bool maximise) public view returns (uint256) {
        uint256 aum = getAum(maximise);
        return (aum * (10 ** USDL_DECIMALS)) / (PRICE_PRECISION);
    }

    function getAum(bool maximise) public view returns (uint256) {
        uint256 length = vault.allWhitelistedTokensLength();
        uint256 aum;
        uint256 profits = 0;
        IVault _vault = vault;

        for (uint256 i = 0; i < length; i++) {
            address token = vault.allWhitelistedTokens(i);
            bool isWhitelisted = vault.whitelistedTokens(token);

            if (!isWhitelisted) {
                continue;
            }

            uint256 price = maximise ? getMaxPrice(token) : getMinPrice(token);
            uint256 poolAmount = _vault.poolAmounts(token);
            uint256 decimals = _vault.tokenDecimals(token);

            if (_vault.canBeCollateralToken(token)) {
                aum = aum + ((poolAmount * (price)) / (10 ** decimals));
            }
            if (_vault.canBeIndexToken(token)) {
                uint256 shortSize = _vault.globalShortSizes(token);

                if (shortSize > 0) {
                    (bool hasProfit, uint256 delta) = getGlobalPositionDelta(token, shortSize, false);
                    if (!hasProfit) {
                        aum = aum + (delta);
                    } else {
                        profits = profits + (delta);
                    }
                }

                uint256 longSize = _vault.globalLongSizes(token);

                if (longSize > 0) {
                    (bool hasProfit, uint256 delta) = getGlobalPositionDelta(token, longSize, true);
                    if (!hasProfit) {
                        aum = aum + (delta);
                    } else {
                        profits = profits + (delta);
                    }
                }
            }
        }

        aum = profits > aum ? 0 : aum - (profits);
        return aum;
    }

    function getGlobalPositionDelta(address _token, uint256 _size, bool _isLong) public view returns (bool, uint256) {
        if (_size == 0) {
            return (false, 0);
        }

        uint256 nextPrice = _isLong ? getMinPrice(_token) : getMaxPrice(_token);
        uint256 averagePrice = _isLong ? vault.globalLongAveragePrices(_token) : vault.globalShortAveragePrices(_token);
        uint256 priceDelta = averagePrice > nextPrice ? averagePrice - (nextPrice) : nextPrice - (averagePrice);
        uint256 delta = (_size * (priceDelta)) / (averagePrice);
        bool hasProfit = _isLong ? nextPrice > averagePrice : nextPrice < averagePrice;
        return (hasProfit, delta);
    }

    function validatePosition(uint256 _size, uint256 _collateral) public pure {
        if (_size == 0) {
            _validate(_collateral == 0, "Utils: collateral should be 0");
            return;
        }
        _validate(_size >= _collateral, "Utils: collateral exceeds size");
    }

    function updateCumulativeBorrowingRate(address _indexToken)
        public
        view
        returns (uint256 borrowingTime, uint256 borrowingRateForLongs, uint256 borrowingRateForShorts)
    {
        uint256 lastBorrowingTime = vault.lastBorrowingTimes(_indexToken);
        (, uint256 borrowingInterval,) = vault.borrowingRateFactor(_indexToken);
        if (lastBorrowingTime == 0) {
            return ((block.timestamp / (borrowingInterval)) * (borrowingInterval), 0, 0);
        }

        if (lastBorrowingTime + borrowingInterval > block.timestamp) {
            return (lastBorrowingTime, 0, 0);
        }

        uint256 intervals = (block.timestamp - lastBorrowingTime) / (borrowingInterval);

        borrowingTime = (block.timestamp / (borrowingInterval)) * (borrowingInterval);
        borrowingRateForLongs = getNextBorrowingRate(_indexToken, true);
        borrowingRateForShorts = getNextBorrowingRate(_indexToken, false);

        borrowingRateForLongs = borrowingRateForLongs * intervals;
        borrowingRateForShorts = borrowingRateForShorts * intervals;
    }

    function getNextBorrowingRate(address _indexToken, bool _isLong) public view returns (uint256) {
        uint256 thresholdFactor =
            _isLong ? vault.maxGlobalLongSizesBps(_indexToken) : vault.maxGlobalShortSizesBps(_indexToken);
        uint256 poolAmount = (getLPAmountInUSD() * thresholdFactor) / BASIS_POINTS_DIVISOR;
        uint256 reservedAmount = getOI(_indexToken, _isLong);
        (uint256 borrowingRateFactor,, uint256 borrowingExponent) = vault.borrowingRateFactor(_indexToken);
        if (poolAmount == 0) {
            return 0;
        }

        poolAmount = poolAmount / PRICE_PRECISION;
        reservedAmount = reservedAmount / PRICE_PRECISION;

        if (reservedAmount <= poolAmount) {
            return tierBorrowingRateFactor;
        } else {
            return (borrowingRateFactor * (reservedAmount ** borrowingExponent)) / (poolAmount ** borrowingExponent);
        }
    }

    function updateCumulativeFundingRate(address _indexToken, uint256 lastFundingTime)
        public
        view
        returns (uint256 lastFundingUpdateTime, int256 fundingRateForLong, int256 fundingRateForShort)
    {
        (, uint256 fundingInterval,) = vault.fundingRateFactor(_indexToken);
        if (lastFundingTime == 0) {
            return ((block.timestamp / (fundingInterval)) * (fundingInterval), 0, 0);
        }

        if (lastFundingTime + fundingInterval > block.timestamp) {
            return (lastFundingTime, 0, 0);
        }

        lastFundingUpdateTime = (block.timestamp / (fundingInterval)) * (fundingInterval);
        uint256 intervals = (lastFundingUpdateTime - lastFundingTime) / fundingInterval;
        (fundingRateForLong, fundingRateForShort) = getNextFundingRate(_indexToken);
        return (lastFundingUpdateTime, fundingRateForLong * int256(intervals), fundingRateForShort * int256(intervals));
    }

    function getNextFundingRate(address _indexToken) public view returns (int256, int256) {
        (uint256 fundingRateFactor,, uint256 fundingExponent) = vault.fundingRateFactor(_indexToken);
        uint256 globalLongSizeVault = getOI(_indexToken, true);
        uint256 globalShortSizeVault = getOI(_indexToken, false);
        uint256 oiImbalance = globalLongSizeVault > globalShortSizeVault
            ? globalLongSizeVault - globalShortSizeVault
            : globalShortSizeVault - globalLongSizeVault;
        if (globalLongSizeVault + globalShortSizeVault == 0) {
            return (0, 0);
        }
        uint256 oiImbalanceThreshold = IVault(vault).oiImbalanceThreshold(_indexToken);
        uint256 oiImbalanceInBps = (oiImbalance * BASIS_POINTS_DIVISOR) / (globalLongSizeVault + globalShortSizeVault);
        uint256 nextFundingRateForLong =
            (fundingRateFactor * (oiImbalance)) / (globalLongSizeVault + globalShortSizeVault);
        if (oiImbalanceInBps > oiImbalanceThreshold) {
            nextFundingRateForLong = (nextFundingRateForLong * (oiImbalanceInBps ** fundingExponent))
                / (oiImbalanceThreshold ** fundingExponent);
        }

        if (globalShortSizeVault == 0) {
            return (int256(nextFundingRateForLong), 0);
        }
        if (globalLongSizeVault == 0) {
            return (0, int256(nextFundingRateForLong));
        }
        uint256 nextFundingRateForShort = (nextFundingRateForLong * globalLongSizeVault) / globalShortSizeVault;
        if (globalLongSizeVault > globalShortSizeVault) {
            return (int256(nextFundingRateForLong), -1 * int256(nextFundingRateForShort)); // chance of overflow, revisit
                //to prevent overflow can set a maxThreshold of nextFundingRate.
        } else {
            return (-1 * int256(nextFundingRateForLong), int256(nextFundingRateForShort));
        }
    }

    function usdToTokenMax(address _token, uint256 _usdAmount) public view returns (uint256) {
        if (_usdAmount == 0) {
            return 0;
        }
        return usdToToken(_token, _usdAmount, getMinPrice(_token));
    }

    function usdToTokenMin(address _token, uint256 _usdAmount) public view returns (uint256) {
        if (_usdAmount == 0) {
            return 0;
        }
        return usdToToken(_token, _usdAmount, getMaxPrice(_token));
    }

    function tokenToUsdMin(address _token, uint256 _tokenAmount) public view returns (uint256) {
        if (_tokenAmount == 0) {
            return 0;
        }
        uint256 price = getMinPrice(_token);
        uint256 decimals = vault.tokenDecimals(_token);
        return (_tokenAmount * (price)) / (10 ** decimals);
    }

    function usdToToken(address _token, uint256 _usdAmount, uint256 _price) public view returns (uint256) {
        if (_usdAmount == 0) {
            return 0;
        }
        uint256 decimals = vault.tokenDecimals(_token);
        return (_usdAmount * (10 ** decimals)) / (_price);
    }

    function getMinPrice(address _token) public view returns (uint256) {
        return priceFeed.getMinPriceOfToken(_token);
    }

    function getMaxPrice(address _token) public view returns (uint256) {
        return priceFeed.getMaxPriceOfToken(_token);
    }

    function getRedemptionAmount(address _token, uint256 _usdlAmount) public view override returns (uint256) {
        uint256 price = getMaxPrice(_token);
        uint256 redemptionAmount = (_usdlAmount * (PRICE_PRECISION)) / (price);
        return adjustForDecimals(redemptionAmount, vault.usdl(), _token);
    }

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
    ) external returns (int256 feeUsd) {
        int256 tradingFee =
            int256(getPositionFee(_account, _collateralToken, _indexToken, _isLong, _sizeDelta, _collateralDeltaUsd));
        int256 borrowingFee =
            int256(getBorrowingFee(_account, _collateralToken, _indexToken, _isLong, _size, _entryBorrowingRate));
        int256 fundingFee = getFundingFee(_account, _collateralToken, _indexToken, _isLong, _size, _entryFundingRate);
        feeUsd = tradingFee + borrowingFee + fundingFee;
        if (msg.sender == address(vault)) {
            emit LemonXFees(
                _account,
                _indexToken,
                _isLong,
                _sizeDelta,
                _entryBorrowingRate,
                _entryFundingRate,
                tradingFee,
                borrowingFee,
                fundingFee,
                block.timestamp
            );
        }
        return feeUsd;
    }

    function abs(int256 value) public pure returns (int256) {
        return value < 0 ? -value : value;
    }

    function getFundingFee(
        address, /*account*/
        address, /*collateralToken*/
        address indexToken,
        bool isLong,
        uint256 size,
        int256 entryFundingRate
    ) public view returns (int256) {
        if (size == 0) {
            return 0;
        }
        int256 differenceInFundingRate;
        if (isLong) {
            differenceInFundingRate = vault.cumulativeFundingRatesForLongs(indexToken) - entryFundingRate;
        } else {
            differenceInFundingRate = vault.cumulativeFundingRatesForShorts(indexToken) - entryFundingRate;
        }

        int256 fundingfactor;

        if (differenceInFundingRate < 0) {
            fundingfactor = fundingFactorForLessOISide;
        } else {
            fundingfactor = fundingFactorForHighOISide;
        }

        return (fundingfactor * differenceInFundingRate * int256(size))
            / (FUNDING_RATE_PRECISION * int256(BASIS_POINTS_DIVISOR));
    }

    function getTPPrice(
        uint256 sizeDelta,
        bool isLong,
        uint256 markPrice,
        uint256 _maxTPAmount,
        address collateralToken
    ) public view returns (uint256) {
        uint256 maxProfitInUsd =
            (_maxTPAmount * getMinPrice(collateralToken)) / (10 ** vault.tokenDecimals(collateralToken));
        uint256 profitDelta = (maxProfitInUsd * markPrice) / sizeDelta;
        if (isLong) {
            return markPrice + profitDelta;
        } else if (markPrice > profitDelta) {
            return markPrice - profitDelta;
        }
        return 0;
    }

    function calcLiquidationFee(uint256 size, address indexToken) public view returns (uint256) {
        uint256 liqFeeBasedOnSize = (size * vault.liquidationFactor()) / BASIS_POINTS_DIVISOR;
        if (liqFeeBasedOnSize > vault.liquidationFeeUsd()) {
            return liqFeeBasedOnSize;
        } else {
            return vault.liquidationFeeUsd();
        }
    }

    function getOI(address _token, bool _isLong) public view override returns (uint256 finalOI) {
        uint256 globalSize = _isLong ? IVault(vault).globalLongSizes(_token) : IVault(vault).globalShortSizes(_token);
        (bool hasProfit, uint256 delta) = getGlobalPositionDelta(_token, globalSize, _isLong);
        finalOI = hasProfit ? globalSize + delta : globalSize - delta;
    }

    function getLPAmountInUSD() public view returns (uint256 lpAmountInUSD) {
        uint256 length = vault.allWhitelistedTokensLength();
        for (uint256 i = 0; i < length; i++) {
            address token = vault.allWhitelistedTokens(i);
            if (vault.canBeCollateralToken(token)) {
                lpAmountInUSD = lpAmountInUSD + tokenToUsdMin(token, vault.poolAmounts(token));
            }
        }
    }

    function getTotalOI() public view returns (uint256 totalOI) {
        uint256 length = vault.allWhitelistedTokensLength();
        for (uint256 i = 0; i < length; i++) {
            address token = vault.allWhitelistedTokens(i);
            if (vault.canBeIndexToken(token)) {
                totalOI = totalOI + getOI(token, true) + getOI(token, false);
            }
        }
    }

    function getFreeLlpAmount(address llp) external view returns (uint256) {
        uint256 aumInusdl = getAumInUsdl(true);
        uint256 llpSupply = IERC20(llp).totalSupply();

        uint256 totalOI = getTotalOI();
        uint256 poolAmountUSD = getLPAmountInUSD();
        if (totalOI >= poolAmountUSD) {
            return 0;
        } else {
            uint256 freeAmountInUsdl = ((poolAmountUSD - totalOI) * (10 ** USDL_DECIMALS)) / PRICE_PRECISION;
            return (freeAmountInUsdl * llpSupply) / aumInusdl;
        }
    }
}
