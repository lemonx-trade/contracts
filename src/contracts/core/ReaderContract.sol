// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "../access/Governable.sol";
import "./interfaces/IVault.sol";
import "../libraries/token/IERC20.sol";

contract ReaderContract is Governable {
    IVault public vault;
    IUtils public utils;
    IERC20 public usdc;
    uint256 public constant PRICE_PRECISION = 10 ** 30;
    uint256 public constant BASIS_POINTS_DIVISOR = 10000;
    uint256 public BORROWING_RATE_PRECISION = 1000000000000;
    int256 public FUNDING_RATE_PRECISION = 1000000000000;
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
    uint256 constant POSITION_FEE_SCALING_FACTOR = 1000000;

    event AddressChanged(uint256 configCode, address oldAddress, address newAddress);
    event ValueChanged(uint256 configCode, uint256 oldValue, uint256 newValue);
    event ValueChangedInt(uint256 configCode, int256 oldValue, int256 newValue);

    modifier isContract(address account) {
        require(account != address(0), "ZERO");
        require(account != 0x000000000000000000000000000000000000dEaD, "DEAD");
        uint256 size;
        assembly {
            size := extcodesize(account)
        }
        require(size > 0, "eoa");
        _;
    }

    constructor(address _vault, address _usdc, address _utils) {
        vault = IVault(_vault);
        usdc = IERC20(_usdc);
        utils = IUtils(_utils);
    }
    //  M3 missing for threshold - NOTE: Business logic
    //  L1 missing events

    function setTier1Size(uint256 _tier1Size) external onlyGov {
        uint256 oldValue = tier1Size;
        tier1Size = _tier1Size;
        emit ValueChanged(1, oldValue, _tier1Size);
    }
    //  M3 missing for threshold - NOTE: Business logic
    //  L1 missing events

    function setTier2Size(uint256 _tier2Size) external onlyGov {
        uint256 oldValue = tier2Size;
        tier2Size = _tier2Size;
        emit ValueChanged(2, oldValue, _tier2Size);
    }
    //  M3 missing for threshold - NOTE: Business logic
    //  L1 missing events

    function setTier3Size(uint256 _tier3Size) external onlyGov {
        uint256 oldValue = tier3Size;
        tier3Size = _tier3Size;
        emit ValueChanged(3, oldValue, _tier3Size);
    }
    //  M3 missing for threshold - NOTE: Business logic
    //  L1 missing events

    function setTier1Factor(uint256 _tier1Factor) external onlyGov {
        uint256 oldValue = tier1Factor;
        tier1Factor = _tier1Factor;
        emit ValueChanged(4, oldValue, _tier1Factor);
    }
    //  M3 missing for threshold - NOTE: Business logic
    //  L1 missing events

    function setTier2Factor(uint256 _tier2Factor) external onlyGov {
        uint256 oldValue = tier2Factor;
        tier2Factor = _tier2Factor;
        emit ValueChanged(5, oldValue, _tier2Factor);
    }
    //  M3 missing for threshold - NOTE: Business logic
    //  L1 missing events

    function setTier3Factor(uint256 _tier3Factor) external onlyGov {
        uint256 oldValue = tier3Factor;
        tier3Factor = _tier3Factor;
        emit ValueChanged(6, oldValue, _tier3Factor);
    }
    //  M3 missing for threshold - NOTE: Business logic
    //  L1 missing events

    function setTierBorrowingRateFactor(uint256 _tierBorrowingRateFactor) external onlyGov {
        uint256 oldValue = tierBorrowingRateFactor;
        tierBorrowingRateFactor = _tierBorrowingRateFactor;
        emit ValueChanged(7, oldValue, _tierBorrowingRateFactor);
    }
    //  M3 missing for threshold
    //  L1 missing events

    function setFundingFactorForLessOISide(int256 _fundingFactorForLessOISide) external onlyGov {
        require(_fundingFactorForLessOISide > -1 * FUNDING_RATE_PRECISION, "nffloi");
        require(_fundingFactorForLessOISide < 1 * FUNDING_RATE_PRECISION, "pffloi");
        int256 oldValue = fundingFactorForLessOISide;
        fundingFactorForLessOISide = _fundingFactorForLessOISide;
        emit ValueChangedInt(1, oldValue, _fundingFactorForLessOISide);
    }
    //  M3 missing for threshold
    //  L1 missing events

    function setFundingFactorForHighOISide(int256 _fundingFactorForHighOISide) external onlyGov {
        require(_fundingFactorForHighOISide > -1 * FUNDING_RATE_PRECISION, "nffloi");
        require(_fundingFactorForHighOISide < 1 * FUNDING_RATE_PRECISION, "pffloi");
        int256 oldValue = fundingFactorForHighOISide;
        fundingFactorForHighOISide = _fundingFactorForHighOISide;
        emit ValueChangedInt(2, oldValue, _fundingFactorForHighOISide);
    }
    //  L1 missing events

    function setTierBorrowingRateStartTime(uint256 _tierBorrowingRateStartTime) external onlyGov {
        uint256 oldValue = tierBorrowingRateStartTime;
        tierBorrowingRateStartTime = _tierBorrowingRateStartTime;
        emit ValueChanged(8, oldValue, _tierBorrowingRateStartTime);
    }
    // M2 check for isContract

    function setVault(address _vault) public onlyGov isContract(_vault) {
        address oldAddress = address(vault);
        vault = IVault(_vault);
        emit AddressChanged(1, oldAddress, _vault);
    }
    //  M2 check for isContract

    function setUtils(address _utils) public onlyGov isContract(_utils) {
        address oldAddress = address(utils);
        utils = IUtils(_utils);
        emit AddressChanged(2, oldAddress, _utils);
    }
    //  M2 check for isContract

    function setUsdc(address _usdc) public onlyGov isContract(_usdc) {
        address oldAddress = address(usdc);
        usdc = IERC20(_usdc);
        emit AddressChanged(3, oldAddress, _usdc);
    }

    function getOI(uint256 price, address _token, bool _isLong) public view returns (uint256 finalOI) {
        uint256 globalSize = _isLong ? IVault(vault).globalLongSizes(_token) : IVault(vault).globalShortSizes(_token);
        (bool hasProfit, uint256 delta) = getGlobalPositionDelta(_token, globalSize, _isLong, price);
        finalOI = hasProfit ? globalSize + delta : globalSize - delta;
    }

    function cumulativeBorrowingRate(address _indexToken, uint256 price, uint256 usdcPrice)
        public
        view
        returns (uint256, uint256, uint256)
    {
        (uint256 borrowingTime, uint256 borrowingRateForLongs, uint256 borrowingRateForShorts) =
            updateCumulativeBorrowingRate(_indexToken, price, usdcPrice);
        uint256 currentBorrowingRateLongs =
            IVault(vault).cumulativeBorrowingRatesForLongs(_indexToken) + borrowingRateForLongs;
        uint256 currentBorrowingRateShorts =
            IVault(vault).cumulativeBorrowingRatesForShorts(_indexToken) + borrowingRateForShorts;
        return (borrowingTime, currentBorrowingRateLongs, currentBorrowingRateShorts);
    }

    function updateCumulativeBorrowingRate(address _indexToken, uint256 price, uint256 usdcPrice)
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
        borrowingRateForLongs = getNextBorrowingRate(_indexToken, true, price, usdcPrice);
        borrowingRateForShorts = getNextBorrowingRate(_indexToken, false, price, usdcPrice);

        borrowingRateForLongs = borrowingRateForLongs * intervals;
        borrowingRateForShorts = borrowingRateForShorts * intervals;
    }

    function getNextBorrowingRate(address _indexToken, bool _isLong, uint256 price, uint256 usdcPrice)
        public
        view
        returns (uint256)
    {
        uint256 thresholdFactor =
            _isLong ? vault.maxGlobalLongSizesBps(_indexToken) : vault.maxGlobalShortSizesBps(_indexToken);
        uint256 poolAmount = (getLPAmountInUSD(usdcPrice) * thresholdFactor) / BASIS_POINTS_DIVISOR;
        uint256 reservedAmount = getOI(price, _indexToken, _isLong);
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

    function getLPAmountInUSD(uint256 price) public view returns (uint256 lpAmountInUSD) {
        uint256 _tokenAmount = vault.poolAmounts(address(usdc));
        if (_tokenAmount == 0) {
            return 0;
        }
        uint256 decimals = vault.tokenDecimals(address(usdc));
        return (_tokenAmount * (price)) / (10 ** decimals);
    }

    function cumulativeFundingRate(address _indexToken, uint256 price) public view returns (uint256, int256, int256) {
        uint256 lastFundingTime = vault.lastFundingTimes(_indexToken);
        (uint256 lastFundingUpdateTime, int256 updateFundingRateLongs, int256 updateFundingRateShorts) =
            updateCumulativeFundingRate(_indexToken, lastFundingTime, price);
        int256 currentFundingRateLongs = vault.cumulativeFundingRatesForLongs(_indexToken) + updateFundingRateLongs;
        int256 currentFundingRateShorts = vault.cumulativeFundingRatesForShorts(_indexToken) + updateFundingRateShorts;
        return (lastFundingTime, currentFundingRateLongs, currentFundingRateShorts);
    }

    function updateCumulativeFundingRate(address _indexToken, uint256 lastFundingTime, uint256 price)
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
        (fundingRateForLong, fundingRateForShort) = getNextFundingRate(_indexToken, price);
        return (lastFundingUpdateTime, fundingRateForLong * int256(intervals), fundingRateForShort * int256(intervals));
    }

    function getNextFundingRate(address _indexToken, uint256 price) public view returns (int256, int256) {
        (uint256 fundingRateFactor,, uint256 fundingExponent) = vault.fundingRateFactor(_indexToken);
        uint256 globalLongSizeVault = getOI(price, _indexToken, true);
        uint256 globalShortSizeVault = getOI(price, _indexToken, false);
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

    function getDelta(
        address _indexToken,
        uint256 _size,
        uint256 _averagePrice,
        uint256 _nextPrice,
        bool _isLong,
        uint256 _lastIncreasedTime
    ) public view returns (bool, uint256) {
        require(_averagePrice > 0, "Vault: averagePrice should be > 0");
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

    function validateLiquidation(
        address _account,
        address _collateralToken,
        address _indexToken,
        bool _isLong,
        bool _raise,
        uint256 _markPrice,
        uint256 usdcPrice
    ) public view returns (uint256, int256) {
        StructsUtils.Position memory position = vault.getPosition(_account, _collateralToken, _indexToken, _isLong);

        (bool hasProfit, uint256 pnl) =
            getDelta(_indexToken, position.size, position.averagePrice, _markPrice, _isLong, position.lastIncreasedTime);
        int256 marginFees = int256(
            getBorrowingFee(
                _account,
                _collateralToken,
                _indexToken,
                _isLong,
                position.size,
                position.entryBorrowingRate,
                _markPrice,
                usdcPrice
            )
        );
        marginFees = marginFees
            + int256(getPositionFee(_account, _collateralToken, _indexToken, _isLong, position.size, position.collateral));

        marginFees = marginFees
            + getFundingFee(
                _account, _collateralToken, _indexToken, _isLong, position.size, position.entryFundingRate, _markPrice
            );

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

        if (remainingCollateral < calcLiquidationFee(position.size, _indexToken)) {
            if (_raise) {
                revert("Vault: liquidation fees exceed collateral");
            }
            return (1, marginFees);
        }

        if (
            remainingCollateral * (BASIS_POINTS_DIVISOR)
                <= position.size * (utils.maintanenceMargin(position.indexToken))
        ) {
            if (_raise) {
                revert("Vault: maxLeverage exceeded");
            }
            return (1, marginFees);
        }

        return (0, marginFees);
    }

    function calcLiquidationFee(uint256 size, address indexToken) public view returns (uint256) {
        uint256 liqFeeBasedOnSize = (size * vault.liquidationFactor()) / BASIS_POINTS_DIVISOR;
        if (liqFeeBasedOnSize > vault.liquidationFeeUsd()) {
            return liqFeeBasedOnSize;
        } else {
            return vault.liquidationFeeUsd();
        }
    }

    function abs(int256 value) public pure returns (int256) {
        return value < 0 ? -value : value;
    }

    function getPositionFee(
        address _account,
        address _collateralToken,
        address _indexToken,
        bool _isLong,
        uint256 _sizeDelta,
        uint256 _collateralDeltaUsd
    ) public view returns (uint256) {
        return utils.getPositionFee(_account, _collateralToken, _indexToken, _isLong, _sizeDelta, _collateralDeltaUsd);
    }

    function getBorrowingFee(
        address _account,
        address _collateralToken,
        address _indexToken,
        bool _isLong,
        uint256 _size,
        uint256 _entryBorrowingRate,
        uint256 price,
        uint256 usdcPrice
    ) public view returns (uint256) {
        if (_size == 0) {
            return 0;
        }
        StructsUtils.Position memory position = vault.getPosition(_account, _collateralToken, _indexToken, _isLong);
        (, uint256 longsBorrowingRate, uint256 shortsBorrowingRate) =
            cumulativeBorrowingRate(_indexToken, price, usdcPrice);
        uint256 currentBorrowingRate = _isLong ? longsBorrowingRate : shortsBorrowingRate;
        uint256 borrowingRate = currentBorrowingRate - (_entryBorrowingRate);
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

    function getFundingFee(
        address, /*account*/
        address, /*collateralToken*/
        address indexToken,
        bool isLong,
        uint256 size,
        int256 entryFundingRate,
        uint256 price
    ) public view returns (int256) {
        if (size == 0) {
            return 0;
        }
        int256 differenceInFundingRate;
        (, int256 longsFundingRate, int256 shortsFundingRate) = cumulativeFundingRate(indexToken, price);
        if (isLong) {
            differenceInFundingRate = longsFundingRate - entryFundingRate;
        } else {
            differenceInFundingRate = shortsFundingRate - entryFundingRate;
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

    function getAumInUSDL(uint256[] memory markPrice) public view returns (uint256) {
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

            uint256 price = markPrice[i];
            uint256 poolAmount = _vault.poolAmounts(token);
            uint256 decimals = _vault.tokenDecimals(token);

            if (_vault.canBeCollateralToken(token)) {
                aum = aum + ((poolAmount * (price)) / (10 ** decimals));
            }
            if (_vault.canBeIndexToken(token)) {
                uint256 shortSize = _vault.globalShortSizes(token);

                if (shortSize > 0) {
                    (bool hasProfit, uint256 delta) = getGlobalPositionDelta(token, shortSize, false, price);
                    if (!hasProfit) {
                        aum = aum + (delta);
                    } else {
                        profits = profits + (delta);
                    }
                }

                uint256 longSize = _vault.globalLongSizes(token);

                if (longSize > 0) {
                    (bool hasProfit, uint256 delta) = getGlobalPositionDelta(token, longSize, true, price);
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

    function getGlobalPositionDelta(address _token, uint256 _size, bool _isLong, uint256 nextPrice)
        public
        view
        returns (bool, uint256)
    {
        if (_size == 0) {
            return (false, 0);
        }

        uint256 averagePrice = _isLong ? vault.globalLongAveragePrices(_token) : vault.globalShortAveragePrices(_token);
        uint256 priceDelta = averagePrice > nextPrice ? averagePrice - (nextPrice) : nextPrice - (averagePrice);
        uint256 delta = (_size * (priceDelta)) / (averagePrice);
        bool hasProfit = _isLong ? nextPrice > averagePrice : nextPrice < averagePrice;
        return (hasProfit, delta);
    }
}
