// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

library StructsUtils {
    struct IncreasePositionRequest {
        address account;
        address _collateralToken;
        address indexToken;
        uint256 amountIn;
        uint256 sizeDelta;
        bool isLong;
        uint256 acceptablePrice;
        uint256 executionFee;
        uint256 blockNumber;
        uint256 blockTime;
    }

    struct DecreasePositionRequest {
        address account;
        address _collateralToken;
        address indexToken;
        uint256 sizeDelta;
        bool isLong;
        address receiver;
        uint256 acceptablePrice;
        uint256 executionFee;
        uint256 blockNumber;
        uint256 blockTime;
    }

    struct Order {
        address account;
        address collateralToken;
        address indexToken;
        uint256 collateralDelta;
        uint256 sizeDelta;
        uint256 triggerPrice;
        uint256 executionFee;
        bool isLong;
        bool triggerAboveThreshold;
        bool isIncreaseOrder;
        bool isMaxOrder;
        uint256 orderIndex;
        uint256 creationTime;
    }

    struct Position {
        address account;
        address collateralToken;
        address indexToken;
        bool isLong;
        uint256 size;
        uint256 collateral;
        uint256 averagePrice;
        uint256 entryBorrowingRate;
        int256 entryFundingRate;
        int256 realisedPnl;
        uint256 lastIncreasedTime;
    }

    struct MintLLPRequest {
        address account;
        uint256 amount;
        address collateralToken;
        uint256 executionFee;
        uint256 minUsdl;
        uint256 minLLP;
    }

    struct BurnLLPRequest {
        address account;
        uint256 amount;
        address collateralToken;
        uint256 minOut;
        address receiver;
        uint256 executionFee;
    }

    struct LiquidatorCacheReturn {
        IndexTokenDetails[] indexTokenDetailsArray;
        VaultDetails vaultDetails;
    }

    struct IndexTokenDetails {
        address indexToken;
        uint256 minProfitBasisPoints;
        uint256 maintanenceMargin;
        CumulativeBorrowingRate cumulativeBorrowingRate;
        CumulativeFundingRate cumulativeFundingRate;
    }

    struct CumulativeBorrowingRate {
        uint256 borrowingTime;
        uint256 currentBorrowingRateLongs;
        uint256 currentBorrowingRateShorts;
    }

    struct CumulativeFundingRate {
        uint256 lastFundingTime;
        int256 currentFundingRateLongs;
        int256 currentFundingRateShorts;
    }

    struct VaultDetails {
        uint256 minProfitTime;
        uint256 liquidationFactor;
        uint256 liquidationFeeUsd;
        uint256 marginFeeBasisPoints;
    }

    struct FECacheReturn {
        IndexTokenDetailsFE[] indexTokenDetailsArray;
        PoolDetailsFE poolDetails;
    }

    struct IndexTokenDetailsFE {
        address indexToken;
        uint256 borrowingRateLong;
        uint256 borrowingRateShort;
        int256 fundingRateLong;
        int256 fundingRateShort;
        uint256 longOpenInterest;
        uint256 shortOpenInterest;
        uint256 globalLongSizesLimitBps;
        uint256 globalShortSizesLimitBps;
    }

    struct PoolDetailsFE {
        uint256 totalSupply;
        uint256 totalStaked;
        uint256 poolValue;
        uint256 poolAmounts;
    }
}
