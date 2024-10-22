// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "forge-std/Script.sol";
import "../src/contracts/core/Vault.sol";
import "../src/contracts/core/PriceFeed.sol";
import "../src/contracts/core/Utils.sol";

contract AddNewIndexToken is Script {
    function run() external {
        // Retrieve the deployer's private key from environment variables
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_ADMIN");
        vm.startBroadcast(deployerPrivateKey);

        // Retrieve contract addresses from environment variables
        address utilsAddress = vm.envAddress("UTILS_ADDRESS");
        address vaultAddress = vm.envAddress("VAULT_ADDRESS");
        address priceFeedAddress = vm.envAddress("PRICE_FEED_ADDRESS");

        // Define the new token's parameters
        address newToken = vm.envAddress("NEW_INDEX_TOKEN");
        uint256 newTokenDecimals = vm.envUint("NEW_INDEX_TOKEN_DECIMALS");
        bytes32 newTokenPriceId = vm.envBytes32("NEW_INDEX_TOKEN_PRICE_ID");

        // Instantiate the Vault and PriceFeed contracts
        Vault vault = Vault(vaultAddress);
        PriceFeed priceFeed = PriceFeed(priceFeedAddress);

        // 1. Configure the Vault with the new token
        vault.setTokenConfig(
            newToken, // Token address
            newTokenDecimals, // Decimals
            0, // minProfitBasisPoints
            false, // isStable
            false, // canBeCollateralToken
            true, // canBeIndexToken
            10000 // maxLeverage (adjust as needed)
        );
        console.log("Vault: Token configuration set for new token.", newToken);

        // 2. Set maximum global long and short sizes for the new token
        vault.setMaxGlobalLongSize(newToken, 10000);
        vault.setMaxGlobalShortSize(newToken, 10000);
        console.log("Vault: Set max global long and short sizes for new token.", newToken);

        // 3. Define the OI imbalance threshold for the new token
        vault.setOiImbalanceThreshold(newToken, 10000);
        console.log("Vault: Set OI imbalance threshold for new token.", newToken);

        // 4. Configure borrowing rates for the new token
        vault.setBorrowingRate(newToken, 60, 0, 1);
        console.log("Vault: Borrowing rate configured for new token.", newToken);

        // 5. Configure funding rates for the new token
        vault.setFundingRate(newToken, 60, 24353121, 1);
        console.log("Vault: Funding rate configured for new token.", newToken);

        // 6. Update the PriceFeed with the new token's price ID mapping
        priceFeed.updateTokenIdMapping(newToken, newTokenPriceId);
        console.log("PriceFeed: Token ID mapping updated for new token.", newToken);

        // 7. Set slippage parameters for the new token in PriceFeed
        priceFeed.setSlippage(newToken, 350); // Adjust slippage as needed
        console.log("PriceFeed: Slippage set for new token.", newToken);

        // 8. Set maintanence margin for the new token in the utils contract
        Utils utils = Utils(utilsAddress);
        utils.setMaintanenceMargin(newToken, 200);
        console.log("Utils: Maintanence margin set for new token.", newToken);

        // 9. Set premium position fee for the new token in the utils contract
        utils.setTokenPremiumPositionFee(newToken, 10);
        console.log("Utils: Premium position fee set for new token.", newToken);

        vm.stopBroadcast();
    }
}
