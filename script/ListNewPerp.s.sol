// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/contracts/core/Vault.sol";
import "../src/contracts/core/PriceFeed.sol";
import "../src/contracts/core/Utils.sol";

contract ListNewPerp is Script {
    struct BorrowingParams {
        uint256 borrowingExponent;
        uint256 borrowingInterval;
        uint256 borrowingRateFactor;
    }

    struct FundingParams {
        uint256 fundingExponent;
        uint256 fundingInterval;
        uint256 fundingRateFactor;
    }

    struct GlobalSizeParams {
        uint256 maxGlobalLongSize;
        uint256 maxGlobalShortSize;
        uint256 oiImbalanceThreshold;
        uint256 globalLongSizesLimitBps;
        uint256 globalShortSizesLimitBps;
    }

    function run() external {
        // Retrieve the deployer's private key from environment variables
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_ADMIN");
        vm.startBroadcast(deployerPrivateKey);
        vm.txGasPrice(50); // in gwei

        // Retrieve contract addresses from environment variables
        address utilsAddress = vm.envAddress("UTILS");
        address vaultAddress = vm.envAddress("VAULT");
        address priceFeedAddress = vm.envAddress("PRICEFEED");
        int256 premiumPositionFeeForMEME = 5;
        /*  
        // Example: Add TON Perp
        addPerp(
            "TON",
            utilsAddress,
            vaultAddress,
            priceFeedAddress,
            GlobalSizeParams({
                maxGlobalLongSize: 4_000,
                maxGlobalShortSize: 4_000,
                oiImbalanceThreshold: 10_000,
                globalLongSizesLimitBps: 10_000,
                globalShortSizesLimitBps: 10_000
            }),
            500, // Slippage
            300, // Maintenance Margin
            BorrowingParams({borrowingExponent: 1, borrowingInterval: 60, borrowingRateFactor: 0}),
            FundingParams({fundingExponent: 1, fundingInterval: 60, fundingRateFactor: 24_353_121})
        ); 
        */

        // Example: Add DOGE Perp
        addPerp(
            "DOGE",
            utilsAddress,
            vaultAddress,
            priceFeedAddress,
            GlobalSizeParams({
                maxGlobalLongSize: 2_000,
                maxGlobalShortSize: 2_000,
                oiImbalanceThreshold: 5_000,
                globalLongSizesLimitBps: 5_000,
                globalShortSizesLimitBps: 5_000
            }),
            1000, // Slippage
            700, // Maintenance Margin
            BorrowingParams({borrowingExponent: 1, borrowingInterval: 60, borrowingRateFactor: 0}),
            FundingParams({fundingExponent: 1, fundingInterval: 60, fundingRateFactor: 24_353_121}),
            premiumPositionFeeForMEME
        );

        // Example: Add POPCAT Perp
        addPerp(
            "POPCAT",
            utilsAddress,
            vaultAddress,
            priceFeedAddress,
            GlobalSizeParams({
                maxGlobalLongSize: 2_000,
                maxGlobalShortSize: 2_000,
                oiImbalanceThreshold: 5_000,
                globalLongSizesLimitBps: 5_000,
                globalShortSizesLimitBps: 5_000
            }),
            1000, // Slippage
            700, // Maintenance Margin
            BorrowingParams({borrowingExponent: 1, borrowingInterval: 60, borrowingRateFactor: 0}),
            FundingParams({fundingExponent: 1, fundingInterval: 60, fundingRateFactor: 24_353_121}),
            premiumPositionFeeForMEME
        );

        vm.stopBroadcast();
    }

    function addPerp(
        string memory perpName,
        address utilsAddress,
        address vaultAddress,
        address priceFeedAddress,
        GlobalSizeParams memory globalSizeParams,
        uint256 slippage,
        uint256 maintenanceMargin,
        BorrowingParams memory borrowingParams,
        FundingParams memory fundingParams,
        int256 premiumPositionFeeForMEME
    ) internal {
        // Construct environment variable names
        string memory envPerpAddress = perpName;
        string memory envPerpDecimals = string(abi.encodePacked(perpName, "_DECIMAL"));
        string memory envPerpPriceId = string(abi.encodePacked(perpName, "_PYTH_FEED_MAINNET"));
        string memory envPerpMaxLeverage = string(abi.encodePacked(perpName, "_MAX_LEVERAGE"));

        // Validate that all environment variables are set
        require(
            vm.envOr(envPerpAddress, address(0)) != address(0),
            string(abi.encodePacked("Environment variable ", envPerpAddress, " is not set"))
        );
        require(
            vm.envOr(envPerpDecimals, uint256(0)) != 0,
            string(abi.encodePacked("Environment variable ", envPerpDecimals, " is not set"))
        );
        require(
            vm.envOr(envPerpPriceId, bytes32(0)) != bytes32(0),
            string(abi.encodePacked("Environment variable ", envPerpPriceId, " is not set"))
        );
        require(
            vm.envOr(envPerpMaxLeverage, uint256(0)) != 0,
            string(abi.encodePacked("Environment variable ", envPerpMaxLeverage, " is not set"))
        );

        address newPerp = vm.envAddress(envPerpAddress);
        uint256 newPerpDecimals = vm.envUint(envPerpDecimals);
        bytes32 newPerpPriceId = vm.envBytes32(envPerpPriceId);
        uint256 maxLeverage = vm.envUint(envPerpMaxLeverage);

        // Instantiate the Vault, PriceFeed, and Utils contracts
        Vault vault = Vault(vaultAddress);
        PriceFeed priceFeed = PriceFeed(priceFeedAddress);
        Utils utils = Utils(utilsAddress);

        // 1. Configure the Vault with the new Perp
        vault.setTokenConfig(
            newPerp, // Token address
            newPerpDecimals, // Decimals
            0, // minProfitBasisPoints
            false, // isStable
            false, // canBeCollateralToken
            true, // canBeIndexToken
            maxLeverage // maxLeverage
        );
        console.log("Vault: Token configuration set for new Perp %s. Address: %s", perpName, newPerp);

        // 2. Set maximum global long and short sizes for the new Perp
        vault.setMaxGlobalLongSize(newPerp, globalSizeParams.maxGlobalLongSize);
        vault.setMaxGlobalShortSize(newPerp, globalSizeParams.maxGlobalShortSize);
        console.log("Vault: Set max global long size for %s: %s", perpName, globalSizeParams.maxGlobalLongSize);
        console.log("Vault: Set max global short size for %s: %s", perpName, globalSizeParams.maxGlobalShortSize);

        vault.setGlobalLongSizesLimitBps(newPerp, globalSizeParams.globalLongSizesLimitBps);
        vault.setGlobalShortSizesLimitBps(newPerp, globalSizeParams.globalShortSizesLimitBps);

        // 3. Define the OI imbalance threshold for the new Perp
        vault.setOiImbalanceThreshold(newPerp, globalSizeParams.oiImbalanceThreshold);
        console.log("Vault: Set OI imbalance threshold for %s: %s", perpName, globalSizeParams.oiImbalanceThreshold);

        // 4. Configure borrowing rates for the new Perp
        vault.setBorrowingRate(
            newPerp,
            borrowingParams.borrowingInterval,
            borrowingParams.borrowingRateFactor,
            borrowingParams.borrowingExponent
        );
        console.log("Vault: Borrowing rate configured for %s.", perpName);
        console.log("Borrowing Interval: %s", borrowingParams.borrowingInterval);
        console.log("Borrowing Rate Factor: %s", borrowingParams.borrowingRateFactor);
        console.log("Borrowing Exponent: %s", borrowingParams.borrowingExponent);

        // 5. Configure funding rates for the new Perp
        vault.setFundingRate(
            newPerp, fundingParams.fundingInterval, fundingParams.fundingRateFactor, fundingParams.fundingExponent
        );
        console.log("Vault: Funding rate configured for %s.", perpName);
        console.log("Funding Interval: %s", fundingParams.fundingInterval);
        console.log("Funding Rate Factor: %s", fundingParams.fundingRateFactor);
        console.log("Funding Exponent: %s", fundingParams.fundingExponent);

        // 6. Update the PriceFeed with the new Perp's price ID mapping
        priceFeed.updateTokenIdMapping(newPerp, newPerpPriceId);
        console.log("PriceFeed: Token ID mapping updated for %s.", perpName);

        // 7. Set slippage parameters for the new Perp in PriceFeed
        priceFeed.setSlippage(newPerp, slippage);
        console.log("PriceFeed: Slippage set for %s: %s", perpName, slippage);

        // 8. Set maintenance margin for the new Perp in the Utils contract
        utils.setMaintanenceMargin(newPerp, maintenanceMargin);
        console.log("Utils: Maintenance margin set for %s: %s", perpName, maintenanceMargin);

        // 9. Set premium position fee for the new Perp in the Utils contract
        int256 premiumPositionFee = premiumPositionFeeForMEME; // Default value, can be parameterized if needed
        utils.setTokenPremiumPositionFee(newPerp, premiumPositionFee);
        // console.log("Utils: Premium position fee set for %s: %s", perpName, premiumPositionFee);
    }
}
