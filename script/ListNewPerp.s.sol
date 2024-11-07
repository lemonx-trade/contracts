// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/contracts/core/Vault.sol";
import "../src/contracts/core/PriceFeed.sol";
import "../src/contracts/core/Utils.sol";

contract AddNewIndexToken is Script {
    function addNewIndexToken(
        string memory perpName,
        address utilsAddress,
        address vaultAddress,
        address priceFeedAddress,
        uint256 maxGlobalLongSizeNewPerp,
        uint256 maxGlobalShortSizeNewPerp,
        uint256 oiImbalanceThresholdNewPerp,
        uint256 globalLongSizesLimitBpsForNewPerp,
        uint256 globalShortSizesLimitBpsForNewPerp,
        uint256 slippage,
        uint256 maintanenceMarginForNewPerp,
        uint256 borrowingExponent,
        uint256 borrowingInterval,
        uint256 borrowingRateFactor,
        uint256 fundingExponent,
        uint256 fundingInterval,
        uint256 fundingRateFactor
    ) internal {
        // Construct environment variable names
        string memory envPerpAddress = perpName;
        string memory envPerpDecimals = string(abi.encodePacked(perpName, "_DECIMAL"));
        string memory envPerpPriceId = string(abi.encodePacked(perpName, "_PYTH_FEED_MAINNET"));
        string memory envPerpMaxLeverage = string(abi.encodePacked(perpName, "_MAX_LEVERAGE"));

        // Validate that all environment variables are set
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
        vault.setMaxGlobalLongSize(newPerp, maxGlobalLongSizeNewPerp);
        vault.setMaxGlobalShortSize(newPerp, maxGlobalShortSizeNewPerp);
        console.log("Vault: Set max global long size for %s: %s", perpName, maxGlobalLongSizeNewPerp);
        console.log("Vault: Set max global short size for %s: %s", perpName, maxGlobalShortSizeNewPerp);

        vault.setGlobalLongSizesLimitBps(newPerp, globalLongSizesLimitBpsForNewPerp);
        vault.setGlobalShortSizesLimitBps(newPerp, globalShortSizesLimitBpsForNewPerp);

        // 3. Define the OI imbalance threshold for the new Perp
        vault.setOiImbalanceThreshold(newPerp, oiImbalanceThresholdNewPerp);
        console.log("Vault: Set OI imbalance threshold for %s: %s", perpName, oiImbalanceThresholdNewPerp);

        // 4. Configure borrowing rates for the new Perp
        vault.setBorrowingRate(newPerp, borrowingInterval, borrowingRateFactor, borrowingExponent);
        console.log("Vault: Borrowing rate configured for %s.", perpName);
        console.log("Borrowing Interval: %s", borrowingInterval);
        console.log("Borrowing Rate Factor: %s", borrowingRateFactor);
        console.log("Borrowing Exponent: %s", borrowingExponent);

        // 5. Configure funding rates for the new Perp
        vault.setFundingRate(newPerp, fundingInterval, fundingRateFactor, fundingExponent);
        console.log("Vault: Funding rate configured for %s.", perpName);
        console.log("Funding Interval: %s", fundingInterval);
        console.log("Funding Rate Factor: %s", fundingRateFactor);
        console.log("Funding Exponent: %s", fundingExponent);

        // 6. Update the PriceFeed with the new Perp's price ID mapping
        priceFeed.updateTokenIdMapping(newPerp, newPerpPriceId);
        console.log("PriceFeed: Token ID mapping updated for %s.", perpName);

        // 7. Set slippage parameters for the new Perp in PriceFeed
        priceFeed.setSlippage(newPerp, slippage);
        console.log("PriceFeed: Slippage set for %s: %s", perpName, slippage);

        // 8. Set maintenance margin for the new Perp in the utils contract
        utils.setMaintanenceMargin(newPerp, maintanenceMarginForNewPerp);
        console.log("Utils: Maintenance margin set for %s: %s", perpName, maintanenceMarginForNewPerp);

        // 9. Set premium position fee for the new Perp in the utils contract
        int256 premiumPositionFee = 10; // Default value
        utils.setTokenPremiumPositionFee(newPerp, premiumPositionFee);
        // console.log("Utils: Premium position fee set for %s: %s", perpName, premiumPositionFee);
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

        // Example: Add DOGE Perp
        addDOGE(utilsAddress, vaultAddress, priceFeedAddress);

        vm.stopBroadcast();
    }

    function addTON(address utilsAddress, address vaultAddress, address priceFeedAddress) internal {
        // Parameters specific to TON
        string memory perpName = "TON";
        uint256 maxGlobalLongSizeNewPerp = 4_000;
        uint256 maxGlobalShortSizeNewPerp = 4_000;
        uint256 oiImbalanceThresholdNewPerp = 10_000;
        uint256 globalLongSizesLimitBpsForNewPerp = 10_000;
        uint256 globalShortSizesLimitBpsForNewPerp = 10_000;
        uint256 slippage = 500;
        uint256 maintanenceMarginForNewPerp = 300;

        // Optional parameters (can be overridden)
        uint256 borrowingExponent = 1;
        uint256 borrowingInterval = 60;
        uint256 borrowingRateFactor = 0;
        uint256 fundingExponent = 1;
        uint256 fundingInterval = 60;
        uint256 fundingRateFactor = 24353121;

        // Call the main function with these parameters
        addNewIndexToken(
            perpName,
            utilsAddress,
            vaultAddress,
            priceFeedAddress,
            maxGlobalLongSizeNewPerp,
            maxGlobalShortSizeNewPerp,
            oiImbalanceThresholdNewPerp,
            globalLongSizesLimitBpsForNewPerp,
            globalShortSizesLimitBpsForNewPerp,
            slippage,
            maintanenceMarginForNewPerp,
            borrowingExponent,
            borrowingInterval,
            borrowingRateFactor,
            fundingExponent,
            fundingInterval,
            fundingRateFactor
        );
    }

    function addDOGE(address utilsAddress, address vaultAddress, address priceFeedAddress) internal {
        // Parameters specific to TON
        string memory perpName = "DOGE";
        uint256 maxGlobalLongSizeDOGE = 2_000;
        uint256 maxGlobalShortSizeDOGE = 2_000;
        uint256 oiImbalanceThresholdDOGE = 5_000;
        uint256 globalLongSizesLimitBpsForDOGE = 5_000;
        uint256 globalShortSizesLimitBpsForDOGE = 5_000;
        uint256 slippage = 500;
        uint256 maintanenceMarginForDOGE = 700;

        // Optional parameters (can be overridden)
        uint256 borrowingExponent = 1;
        uint256 borrowingInterval = 60;
        uint256 borrowingRateFactor = 0;
        uint256 fundingExponent = 1;
        uint256 fundingInterval = 60;
        uint256 fundingRateFactor = 24353121;

        // Call the main function with these parameters
        addNewIndexToken(
            perpName,
            utilsAddress,
            vaultAddress,
            priceFeedAddress,
            maxGlobalLongSizeDOGE,
            maxGlobalShortSizeDOGE,
            oiImbalanceThresholdDOGE,
            globalLongSizesLimitBpsForDOGE,
            globalShortSizesLimitBpsForDOGE,
            slippage,
            maintanenceMarginForDOGE,
            borrowingExponent,
            borrowingInterval,
            borrowingRateFactor,
            fundingExponent,
            fundingInterval,
            fundingRateFactor
        );
    }
}
