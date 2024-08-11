// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "../access/Governable.sol";
import "./interfaces/IVault.sol";
import "./interfaces/IReaderContract.sol";
import "./interfaces/ILLP.sol";
import "./interfaces/IOrderManager.sol";
import "../libraries/utils/Structs.sol";

contract ReaderCache is Governable {
    IVault public vault;
    IUtils public utils;
    IReaderContract public readerContract;
    ILLP public llp;
    ILLP public fLLP;

    modifier isContract(address account) {
        require(account != address(0), "nulladd");
        uint256 size;
        assembly {
            size := extcodesize(account)
        }
        require(size > 0, "eoa");
        _;
    }

    constructor(address _vault, address _utils, address _readerContract, address _llp, address _fLLP) {
        vault = IVault(_vault);
        utils = IUtils(_utils);
        readerContract = IReaderContract(_readerContract);
        llp = ILLP(_llp);
        fLLP = ILLP(_fLLP);
    }
    //  M2 check for isContract
    // TODO: L1 missing events

    function setVault(address _vault) external onlyGov isContract(_vault) {
        vault = IVault(_vault);
    }
    //  M2 check for isContract
    // TODO: L1 missing events

    function setUtils(address _utils) external onlyGov isContract(_utils) {
        utils = IUtils(_utils);
    }
    //  M2 check for isContract
    // TODO: L1 missing events

    function setReaderContract(address _readerContract) external onlyGov isContract(_readerContract) {
        readerContract = IReaderContract(_readerContract);
    }
    //  M2 check for isContract
    // TODO: L1 missing events

    function setLLP(address _llp) external onlyGov isContract(_llp) {
        llp = ILLP(_llp);
    }
    //  M2 check for isContract
    // TODO: L1 missing events

    function setFLLP(address _fLLP) external onlyGov isContract(_fLLP) {
        fLLP = ILLP(_fLLP);
    }

    function getLiquidatorCache(
        address[] calldata indexTokens,
        uint256[] calldata indexTokenPrices,
        uint256 collateralPrice
    ) external view returns (StructsUtils.LiquidatorCacheReturn memory) {
        //Get vault details
        StructsUtils.VaultDetails memory vaultDetails = StructsUtils.VaultDetails(
            vault.minProfitTime(), vault.liquidationFactor(), vault.liquidationFeeUsd(), vault.marginFeeBasisPoints()
        );

        StructsUtils.IndexTokenDetails[] memory indexTokenDetailsArray =
            new StructsUtils.IndexTokenDetails[](indexTokens.length);

        for (uint256 i = 0; i < indexTokens.length; i++) {
            StructsUtils.CumulativeBorrowingRate memory cumulativeBorrowingRate;
            StructsUtils.CumulativeFundingRate memory cumulativeFundingRate;
            {
                //Index token details
                (uint256 borrowingTime, uint256 currentBorrowingRateLongs, uint256 currentBorrowingRateShorts) =
                    readerContract.cumulativeBorrowingRate(indexTokens[i], indexTokenPrices[i], collateralPrice);

                cumulativeBorrowingRate = StructsUtils.CumulativeBorrowingRate(
                    borrowingTime, currentBorrowingRateLongs, currentBorrowingRateShorts
                );
            }

            {
                (uint256 lastFundingTime, int256 currentFundingRateLongs, int256 currentFundingRateShorts) =
                    readerContract.cumulativeFundingRate(indexTokens[i], indexTokenPrices[i]);

                cumulativeFundingRate = StructsUtils.CumulativeFundingRate(
                    lastFundingTime, currentFundingRateLongs, currentFundingRateShorts
                );
            }

            StructsUtils.IndexTokenDetails memory indexTokenDetails = StructsUtils.IndexTokenDetails(
                indexTokens[i],
                vault.minProfitBasisPoints(indexTokens[i]),
                utils.maintanenceMargin(indexTokens[i]),
                cumulativeBorrowingRate,
                cumulativeFundingRate
            );

            indexTokenDetailsArray[i] = indexTokenDetails;
        }

        return StructsUtils.LiquidatorCacheReturn(indexTokenDetailsArray, vaultDetails);
    }

    //In order - ETH and BTC -- important!
    function getFECache(
        address[] calldata indexTokens,
        uint256[] calldata indexTokenPrices,
        address collateralToken,
        uint256 collateralPrice
    ) external view returns (StructsUtils.FECacheReturn memory) {
        //Get pool details

        //Get index token details
        StructsUtils.IndexTokenDetailsFE[] memory indexTokenDetailsArray =
            new StructsUtils.IndexTokenDetailsFE[](indexTokens.length);

        for (uint256 i = 0; i < indexTokens.length; i++) {
            //Index token details
            address currIndexToken = indexTokens[i];
            uint256 currIndexTokenPrice = indexTokenPrices[i];

            (int256 fundingRateLong, int256 fundingRateShort) =
                readerContract.getNextFundingRate(indexTokens[i], indexTokenPrices[i]);

            StructsUtils.IndexTokenDetailsFE memory indexTokenDetails = StructsUtils.IndexTokenDetailsFE(
                indexTokens[i],
                readerContract.getNextBorrowingRate(currIndexToken, true, currIndexTokenPrice, collateralPrice),
                readerContract.getNextBorrowingRate(currIndexToken, false, currIndexTokenPrice, collateralPrice),
                fundingRateLong,
                fundingRateShort,
                readerContract.getOI(currIndexTokenPrice, currIndexToken, true),
                readerContract.getOI(currIndexTokenPrice, currIndexToken, false),
                vault.globalLongSizesLimitBps(currIndexToken),
                vault.globalShortSizesLimitBps(currIndexToken)
            );

            indexTokenDetailsArray[i] = indexTokenDetails;
        }
        StructsUtils.PoolDetailsFE memory poolDetails;
        {
            uint256[] memory poolValueParams = new uint256[](indexTokens.length + 1);
            poolValueParams[0] = collateralPrice;
            for (uint256 i = 1; i <= indexTokens.length; i++) {
                poolValueParams[i] = indexTokenPrices[i - 1];
            }

            poolDetails = StructsUtils.PoolDetailsFE(
                llp.totalSupply(),
                fLLP.totalSupply(),
                readerContract.getAumInUSDL(poolValueParams),
                vault.poolAmounts(collateralToken)
            );
        }

        return StructsUtils.FECacheReturn(indexTokenDetailsArray, poolDetails);
    }

    //Order Manager Reader
    function getCurrentQueueRequestSize(address orderManagerAddr) public view returns (uint256, uint256) {
        IOrderManager orderManager = IOrderManager(orderManagerAddr);
        return (orderManager.getIncreasePositionCount(), orderManager.getDecreasePositionCount());
    }

    function getCurrentStartIdx(address orderManagerAddr) public view returns (uint256, uint256) {
        IOrderManager orderManager = IOrderManager(orderManagerAddr);
        return (orderManager.increasePositionRequestKeysStart(), orderManager.decreasePositionRequestKeysStart());
    }

    function getAllPositionsOfUser(address user) public view returns (StructsUtils.Position[] memory) {
        address collateralToken = vault.allWhitelistedTokens(0);
        uint256 numTokens = vault.allWhitelistedTokensLength();
        StructsUtils.Position[] memory _positions = new StructsUtils.Position[]((numTokens - 1) * 2);
        uint256 posIdx = 0;
        for (uint256 i = 1; i < vault.allWhitelistedTokensLength(); i++) {
            address indexToken = vault.allWhitelistedTokens(i);
            StructsUtils.Position memory position = vault.getPosition(user, collateralToken, indexToken, true);
            if (position.size != 0) {
                _positions[posIdx] = position;
                posIdx++;
            }
            position = vault.getPosition(user, collateralToken, indexToken, false);
            if (position.size != 0) {
                _positions[posIdx] = position;
                posIdx++;
            }
        }
        return _positions;
    }
}
