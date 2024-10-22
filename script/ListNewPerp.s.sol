// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/contracts/core/Vault.sol";
import "../src/contracts/core/PriceFeed.sol";
import "../src/contracts/core/Utils.sol";

contract AddNewIndexToken is Script {
    function run() external {
        // Retrieve the deployer's private key from environment variables
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_ADMIN");
        vm.startBroadcast(deployerPrivateKey);
        vm.txGasPrice(50); // in gwei but it doesn't solve the problem "Failed to get EIP 1559 fees" estimate

        // Retrieve contract addresses from environment variables
        address utilsAddress = vm.envAddress("UTILS");
        address vaultAddress = vm.envAddress("VAULT");
        address priceFeedAddress = vm.envAddress("PRICEFEED");

        // Define the new Perp's parameters
        address newPerp = vm.envAddress("TON");
        uint256 newPerpDecimals = vm.envUint("TON_DECIMAL");
        bytes32 newPerpPriceId = vm.envBytes32("TON_PYTH_FEED_MAINNET");
        uint256 maxLeverage = vm.envUint("MAX_LEVERAGE");
        // Instantiate the Vault and PriceFeed contracts
        Vault vault = Vault(vaultAddress);
        PriceFeed priceFeed = PriceFeed(priceFeedAddress);
        uint256 maxGlobalLongSizeNewPerp = 4_000;
        uint256 maxGlobalShortSizeNewPerp = 4_000;
        uint256 oiImbalanceThresholdNewPerp = 10_000;
        uint256 globalLongSizesLimitBpsForNewPerp = 10_000;
        uint256 globalShortSizesLimitBpsForNewPerp = 10_000;

        uint256 borrowingExponent = 1;
        uint256 borrowingInterval = 60;
        uint256 borrowingRateFactor = 0;
        uint256 fundingExponent = 1;
        uint256 fundingInterval = 60;
        uint256 fundingRateFactor = 24353121;

        uint256 slippage = 500;

        uint256 maintanenceMarginForNewPerp = 100;

        // 1. Configure the Vault with the new Perp
        vault.setTokenConfig(
            newPerp, // Token address
            newPerpDecimals, // Decimals
            0, // minProfitBasisPoints
            false, // isStable
            false, // canBeCollateralToken
            true, // canBeIndexToken
            maxLeverage // maxLeverage (adjust as needed)
        );
        console.log("Vault: Token configuration set for new Perp.", newPerp);

        // 2. Set maximum global long and short sizes for the new Perp
        vault.setMaxGlobalLongSize(newPerp, maxGlobalLongSizeNewPerp);
        vault.setMaxGlobalShortSize(newPerp, maxGlobalShortSizeNewPerp);
        console.log("Vault: Set max global long size for new Perp. newPerp => ", newPerp);
        console.log("maxGlobalLongSizeNewPerp => ", maxGlobalLongSizeNewPerp);

        console.log("Vault: Set max global short size for new Perp. newPerp => ", newPerp);
        console.log("maxGlobalShortSizeNewPerp => ", maxGlobalShortSizeNewPerp);

        vault.setGlobalLongSizesLimitBps(newPerp, globalLongSizesLimitBpsForNewPerp);
        vault.setGlobalShortSizesLimitBps(newPerp, globalShortSizesLimitBpsForNewPerp);

        // 3. Define the OI imbalance threshold for the new Perp
        vault.setOiImbalanceThreshold(newPerp, oiImbalanceThresholdNewPerp);
        console.log("Vault: Set OI imbalance threshold for new Perp. newPerp => ", newPerp);
        console.log("oiImbalanceThresholdNewPerp => ", oiImbalanceThresholdNewPerp);

        // 4. Configure borrowing rates for the new Perp
        vault.setBorrowingRate(newPerp, borrowingInterval, borrowingRateFactor, borrowingExponent);
        console.log("Vault: Borrowing rate configured for new Perp. newPerp => ", newPerp);
        console.log("borrowingInterval => ", borrowingInterval);
        console.log("borrowingRateFactor => ", borrowingRateFactor);
        console.log("borrowingExponent => ", borrowingExponent);

        // 5. Configure funding rates for the new Perp
        vault.setFundingRate(newPerp, fundingInterval, fundingRateFactor, fundingExponent);
        console.log("Vault: Funding rate configured for new Perp. newPerp => ", newPerp);
        console.log("fundingInterval => ", fundingInterval);
        console.log("fundingRateFactor => ", fundingRateFactor);
        console.log("fundingExponent => ", fundingExponent);

        // 6. Update the PriceFeed with the new Perp's price ID mapping
        priceFeed.updateTokenIdMapping(newPerp, newPerpPriceId);
        console.log("PriceFeed: Token ID mapping updated for new Perp. newPerp => ", newPerp);
        // console.log("newPerpPriceId => ", newPerpPriceId);

        // 7. Set slippage parameters for the new Perp in PriceFeed
        priceFeed.setSlippage(newPerp, slippage); // Adjust slippage as needed
        console.log("PriceFeed: Slippage set for new Perp. newPerp => ", newPerp);
        console.log("slippage => ", slippage);

        // 8. Set maintanence margin for the new Perp in the utils contract
        Utils utils = Utils(utilsAddress);
        utils.setMaintanenceMargin(newPerp, maintanenceMarginForNewPerp);
        console.log("Utils: Maintanence margin set for new Perp. newPerp => ", newPerp);
        console.log("maintanenceMarginForNewPerp => ", maintanenceMarginForNewPerp);

        // 9. Set premium position fee for the new Perp in the utils contract
        utils.setTokenPremiumPositionFee(newPerp, 10);
        console.log("Utils: Premium position fee set for new Perp. newPerp => ", newPerp);
        console.log("premiumPositionFee => ", 10);

        vm.stopBroadcast();
    }
}
