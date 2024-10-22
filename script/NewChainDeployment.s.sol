// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "forge-std/Script.sol";
import "../src/contracts/core/PriceFeed.sol";
import "../src/contracts/core/PriceFeed.sol";
import "../src/contracts/core/Vault.sol";
import "../src/contracts/core/OrderManager.sol";
import "../src/contracts/core/USDL.sol";
import "../src/contracts/core/LlpManager.sol";
import "../src/contracts/core/RewardRouter.sol";
import "../src/contracts/core/RewardTracker.sol";
import "../src/contracts/core/Utils.sol";
import "../src/contracts/libraries/token/IERC20.sol";
import "../src/contracts/libraries/token/IBaseToken.sol";
import "../src/contracts/core/interfaces/IVault.sol";
import "../src/contracts/core/ReaderContract.sol";
import "../src/contracts/core/TierBasedTradingFees.sol";
import "../src/contracts/core/ReaderCache.sol";

contract NewChainDeployment is Script {
    uint256 constant maxAllowedDelayPriceFeed = 300;
    uint256 constant maxAllowedDelta = 150;
    uint256 constant llpCooldownDuration = 3600;
    uint256 constant maxPoolVaule = 10 ** 36; //1 million
    uint256 constant minExecutionFeeMarketOrder = 50_000_000_000_000_000;
    uint256 constant minExecutionFeeLimitOrder = 0;
    uint256 constant depositFee = 10;
    uint256 constant maxProfitMultiplier = 5;
    uint256 constant minBlockDelayKeeper = 0;
    uint256 constant minTimeDelayPublic = 300;
    uint256 constant maxTimeDelay = 180;
    uint256 constant liquidationFeeUsd = 4 * 10 ** 30;
    uint256 constant liquidationFactor = 70;
    uint256 constant maxGlobalLongSizeEth = 4_000;
    uint256 constant maxGlobalShortSizeEth = 4_000;
    uint256 constant maxGlobalLongSizeBtc = 4_000;
    uint256 constant maxGlobalShortSizeBtc = 4_000;
    uint256 constant oiImbalanceThreshold = 10_000;
    address[] rewardTrackerDepositToken;
    uint256 constant borrowingExponent = 1;
    uint256 constant borrowingInterval = 60;
    uint256 constant borrowingRateFactor = 0;
    uint256 constant fundingExponent = 1;
    uint256 constant fundingInterval = 60;
    uint256 constant fundingRateFactor = 24353121;
    uint256 constant poolSafetyFactorInBps = 10_000;
    uint256 constant minPurchaseUsdMarketOrder = 95 * 10 ** 5;
    uint256 constant minPurchaseUsdLimitOrder = 95 * 10 ** 5;
    uint256 constant minProfitTime = 60;
    bool public hasDynamicFees = false;
    uint256 public mintBurnFeeBasisPoints = 30; // 0.3%
    uint256 public marginFeeBasisPoints = 10; // 0.1%
    uint256 public maxLeverage = vm.envUint("MAX_LEVERAGE");
    uint256 public maintanenceMarginForBTC = 100;
    uint256 public maintanenceMarginForETH = 100;
    uint256 public slippageForBTC = 350;
    uint256 public slippageForETH = 350;
    uint256 public globalLongSizesLimitBpsForBTC = 10_000;
    uint256 public globalShortSizesLimitBpsForBTC = 10_000;
    uint256 public globalLongSizesLimitBpsForETH = 10_000;
    uint256 public globalShortSizesLimitBpsForETH = 10_000;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_ADMIN");
        vm.startBroadcast(deployerPrivateKey);
        allContractDeployments();
        vm.stopBroadcast();
    }

    function allContractDeployments() public {
        Vault vault = deployVault();
        PriceFeed fusePriceFeed = deployAndInitializePriceFeed();
        USDL usdl = deployUSDL(vault);
        RewardRouter rewardRouter = deployRewardRouter(fusePriceFeed);
        ITierBasedTradingFees tierBasedTradingFees = new TierBasedTradingFees();
        console.log("Deployed tierBasedTradingFees at: ", address(tierBasedTradingFees));
        Utils utils = deployUtils(vault, fusePriceFeed, address(tierBasedTradingFees));
        LlpManager llpManager = deployLlpManager(vault, utils, usdl, rewardRouter);
        RewardTracker rewardTracker = deployRewardTracker();
        initializeLLP(llpManager, address(rewardTracker));
        OrderManager orderManager = deployOrderManager(vault, fusePriceFeed, utils);
        initializeVault(vault, address(orderManager), fusePriceFeed, usdl, utils, llpManager);
        initlializeRewardTracker(rewardTracker);
        initializeRewardRouter(
            rewardRouter, vm.envAddress("LLP"), address(llpManager), address(rewardTracker), fusePriceFeed
        );
        ReaderContract readerContract = deployReaderContract(vault, utils);
        deployReaderCache(vault, utils, readerContract, rewardTracker);
    }

    function deployReaderContract(Vault _vault, Utils _utils) public returns (ReaderContract) {
        ReaderContract readerContract = new ReaderContract(address(_vault), vm.envAddress("USDC"), address(_utils));
        console.log("READER CONTRACT: ", address(readerContract));
        return readerContract;
    }

    function deployReaderCache(Vault _vault, Utils _utils, ReaderContract _readerContract, RewardTracker _rewardTracker)
        public
    {
        ReaderCache readerCache = new ReaderCache(
            address(_vault), address(_utils), address(_readerContract), vm.envAddress("LLP"), address(_rewardTracker)
        );
        console.log("Reader Cache deployed at: ", address(readerCache));
    }

    function deployOrderManager(Vault vault, PriceFeed priceFeed, Utils utils) public returns (OrderManager) {
        OrderManager orderManager = new OrderManager(
            address(vault),
            address(utils),
            address(priceFeed),
            minExecutionFeeMarketOrder,
            minExecutionFeeLimitOrder,
            depositFee,
            maxProfitMultiplier,
            minPurchaseUsdMarketOrder,
            minPurchaseUsdLimitOrder
        );
        console.log("OrderManager deployed at address: ", address(orderManager));
        orderManager.setPositionKeeper(address(priceFeed), true); // pricefeed executes orders
        orderManager.setPositionKeeper(address(orderManager), true); // to handle this.executeOrder
        orderManager.setMinExecutionFeeLimitOrder(minExecutionFeeLimitOrder, minExecutionFeeLimitOrder);
        orderManager.setMinExecutionFeeMarketOrder(minExecutionFeeMarketOrder, minExecutionFeeMarketOrder);
        orderManager.setLiquidator(vm.envAddress("LIQUIDATOR_MAINNET"), true);
        orderManager.setLiquidator(address(priceFeed), true);
        orderManager.setOrderKeeper(vm.envAddress("ORDER_KEEPER_MAINNET"), true);
        orderManager.setDelayValues(minBlockDelayKeeper, minTimeDelayPublic, maxTimeDelay);
        priceFeed.setOrderManager(address(orderManager));
        return orderManager;
    }

    function initializeRewardRouter(
        RewardRouter rewardRouter,
        address llp,
        address llpManager,
        address rewardTracker,
        PriceFeed _priceFeed
    ) public {
        rewardRouter.initialize(llp, llpManager, rewardTracker);
        rewardRouter.setKeeperStatus(address(_priceFeed), true);
        rewardRouter.setKeeperStatus(address(rewardRouter), true);
        RewardTracker(rewardTracker).setHandler(address(rewardRouter), true);
    }

    function deployRewardTracker() public returns (RewardTracker) {
        RewardTracker rewardTracker = new RewardTracker("fee LLP", "fLlp");
        console.log("RewardTracker deployed at address: ", address(rewardTracker));
        return rewardTracker;
    }

    function initlializeRewardTracker(RewardTracker rewardTracker) public {
        rewardTrackerDepositToken.push(vm.envAddress("LLP"));
        address[] memory _depositTokens = rewardTrackerDepositToken;
        rewardTracker.initialize(_depositTokens, vm.envAddress("USDC"), vm.envAddress("ADMIN"));
    }

    function deployUtils(Vault vault, PriceFeed pricefeed, address tierBasedTradingFees) public returns (Utils) {
        Utils utils = new Utils(vault, pricefeed, tierBasedTradingFees);
        utils.setMaintanenceMargin(vm.envAddress("BTC"), maintanenceMarginForBTC);
        utils.setMaintanenceMargin(vm.envAddress("ETH"), maintanenceMarginForETH);
        // utils.setMaintanenceMargin(vm.envAddress("MERL"), 200);
        // utils.setTokenPremiumPositionFee(vm.envAddress("MERL"), 10);
        console.log("Utils deployed at address: ", address(utils));
        return utils;
    }

    function deployUSDL(Vault vault) public returns (USDL) {
        USDL usdl = new USDL(address(vault));
        console.log("USDL deployed at address: ", address(usdl));
        return usdl;
    }

    function deployRewardRouter(PriceFeed _priceFeed) public returns (RewardRouter) {
        RewardRouter rewardRouter = new RewardRouter();
        _priceFeed.setRewardRouter(address(rewardRouter));
        console.log("RewardRouter deployed at address: ", address(rewardRouter));
        return rewardRouter;
    }

    function initializeLLP(LlpManager llpManager, address _rewardTracker) public {
        IMintable(vm.envAddress("LLP")).setMinter(address(llpManager), true);
        IBaseToken(vm.envAddress("LLP")).setInPrivateTransferMode(true);
        IMintable(vm.envAddress("LLP")).setHandler(_rewardTracker, true);
    }

    function deployLlpManager(Vault vault, Utils utils, USDL usdl, RewardRouter rewardRouter)
        public
        returns (LlpManager)
    {
        LlpManager llpManager = new LlpManager(
            address(vault), address(utils), address(usdl), vm.envAddress("LLP"), llpCooldownDuration, maxPoolVaule
        );
        llpManager.setHandler(address(rewardRouter), true);
        llpManager.whiteListToken(vm.envAddress("USDC"));
        console.log("LlpManager deployed at address: ", address(llpManager));
        usdl.addVault(address(llpManager)); // also add llpmanager as vault in usdl(this is needed when llpManager mints usdl)
        return llpManager;
    }

    function deployAndInitializePriceFeed() public returns (PriceFeed) {
        PriceFeed priceFeed =
            new PriceFeed(maxAllowedDelayPriceFeed, vm.envAddress("MARKETORDER_UPDATER"), maxAllowedDelta);
        console.log("PriceFeed deployed at address: ", address(priceFeed));
        // be mindfull of the token to id mappign order in pricefeed
        priceFeed.updateTokenIdMapping(vm.envAddress("USDC"), vm.envBytes32("USDC_PYTH_FEED_MAINNET")); // using same priceId because unused
        priceFeed.updateTokenIdMapping(vm.envAddress("ETH"), vm.envBytes32("ETH_PYTH_FEED_MAINNET")); // order change here
        priceFeed.updateTokenIdMapping(vm.envAddress("BTC"), vm.envBytes32("BTC_PYTH_FEED_MAINNET"));
        // priceFeed.updateTokenIdMapping(vm.envAddress("MERL"), vm.envBytes32("MERL_PYTH_PRICE_ID")); // priceId does not matter
        // set lp market order as updater as well
        priceFeed.setUpdater(vm.envAddress("LP_ORDER_UPDATER"));

        // priceFeed.setSlippage(vm.envAddress("MERL"), 500);
        priceFeed.setSlippage(vm.envAddress("BTC"), slippageForBTC);
        priceFeed.setSlippage(vm.envAddress("ETH"), slippageForETH);
        console.log("PriceFeed initialized");
        return priceFeed;
    }

    function deployVault() public returns (Vault) {
        Vault vault = new Vault();
        console.log("Vault deployed at address: ", address(vault));
        return vault;
    }

    function initializeVault(
        Vault vault,
        address orderManager,
        PriceFeed priceFeed,
        USDL usdl,
        Utils utils,
        LlpManager llpManager
    ) public {
        usdl.addVault(address(vault));
        vault.initialize(orderManager, address(usdl), address(priceFeed), liquidationFeeUsd, liquidationFactor);
        vault.setUtils(address(utils));
        vault.setInManagerMode(true);
        vault.setManager(address(llpManager), true);
        //set tokenConfig
        vault.setTokenConfig(vm.envAddress("USDC"), vm.envUint("USDC_DECIMAL"), 0, true, true, false, maxLeverage);
        vault.setTokenConfig(vm.envAddress("BTC"), vm.envUint("BTC_DECIMAL"), 0, false, false, true, maxLeverage);
        vault.setTokenConfig(vm.envAddress("ETH"), vm.envUint("ETH_DECIMAL"), 0, false, false, true, maxLeverage); //order change
        // vault.setTokenConfig(vm.envAddress("BTC"), vm.envUint("BTC_DECIMAL"), 0, false, false, true, maxLeverage);
        // vault.setTokenConfig(vm.envAddress("MERL"), vm.envUint("MERL_DECIMAL"), 0, false, false, true, maxLeverage);

        //set maxGlobalLongSize and maxGlobalShortSize
        vault.setMaxGlobalLongSize(vm.envAddress("ETH"), maxGlobalLongSizeEth);
        vault.setMaxGlobalShortSize(vm.envAddress("ETH"), maxGlobalShortSizeEth);

        vault.setMaxGlobalLongSize(vm.envAddress("BTC"), maxGlobalLongSizeBtc);
        vault.setMaxGlobalShortSize(vm.envAddress("BTC"), maxGlobalShortSizeBtc);

        // vault.setMaxGlobalLongSize(vm.envAddress("MERL"), maxGlobalLongSizeBtc);
        // vault.setMaxGlobalShortSize(vm.envAddress("MERL"), maxGlobalShortSizeBtc);

        vault.setOiImbalanceThreshold(vm.envAddress("ETH"), oiImbalanceThreshold);
        vault.setOiImbalanceThreshold(vm.envAddress("BTC"), oiImbalanceThreshold);
        // vault.setOiImbalanceThreshold(vm.envAddress("MERL"), oiImbalanceThreshold);

        //set borrowingFeeDetails for all index tokens.
        vault.setBorrowingRate(vm.envAddress("ETH"), borrowingInterval, borrowingRateFactor, borrowingExponent);
        vault.setBorrowingRate(vm.envAddress("BTC"), borrowingInterval, borrowingRateFactor, borrowingExponent);
        // vault.setBorrowingRate(vm.envAddress("MERL"), borrowingInterval, borrowingRateFactor, borrowingExponent);

        //set fundingFeeDetails for all index tokens.
        vault.setFundingRate(vm.envAddress("ETH"), fundingInterval, fundingRateFactor, fundingExponent);
        vault.setFundingRate(vm.envAddress("BTC"), fundingInterval, fundingRateFactor, fundingExponent);
        // vault.setFundingRate(vm.envAddress("MERL"), fundingInterval, fundingRateFactor, fundingExponent);

        vault.setPoolSafetyFactorInBps(poolSafetyFactorInBps);
        vault.setFees(
            mintBurnFeeBasisPoints,
            marginFeeBasisPoints,
            liquidationFeeUsd,
            liquidationFactor,
            minProfitTime,
            hasDynamicFees
        );
        // set setGlobalLongSizesLimitBps & setGlobalShortSizesLimitBps
        vault.setGlobalLongSizesLimitBps(vm.envAddress("ETH"), globalLongSizesLimitBpsForETH);
        vault.setGlobalLongSizesLimitBps(vm.envAddress("BTC"), globalLongSizesLimitBpsForBTC);
        vault.setGlobalShortSizesLimitBps(vm.envAddress("ETH"), globalShortSizesLimitBpsForETH);
        vault.setGlobalShortSizesLimitBps(vm.envAddress("BTC"), globalShortSizesLimitBpsForBTC);
    }
}
