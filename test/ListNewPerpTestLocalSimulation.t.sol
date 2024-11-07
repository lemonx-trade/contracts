// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "../script/ListNewPerp.s.sol";
import "../src/contracts/core/Vault.sol";
import "../src/contracts/core/PriceFeed.sol";
import "../src/contracts/core/Utils.sol";

contract ListNewPerpTestLocalSimulation is Test {
    ListNewPerp script;
    Vault vault;
    PriceFeed priceFeed;
    Utils utils;

    // Core DAO network RPC URL and Chain ID
    string CORE_RPC_URL = "https://rpc.coredao.org";
    uint256 CORE_CHAIN_ID = 1116;

    // Contract addresses on Core DAO network
    address VAULT_ADDRESS = 0xC2acC8e5Be6613f53C71AE5E386D39a40a4761aA;
    address UTILS_ADDRESS = 0x3Ec416e3EF8Bfe2E04d6e578677e3cE1655aC6Fb;
    address PRICEFEED_ADDRESS = 0x436F2109719Deee0a444318Fe657A44714986ECc;

    address DOGE_ADDRESS = vm.envAddress("DOGE"); // Replace with actual DOGE token address
    uint256 DOGE_DECIMALS = vm.envUint("DOGE_DECIMAL");
    bytes32 DOGE_PYTH_FEED_MAINNET = vm.envBytes32("DOGE_PYTH_FEED_MAINNET"); // Replace with actual price feed ID
    uint256 DOGE_MAX_LEVERAGE = vm.envUint("DOGE_MAX_LEVERAGE");

    address POPCAT_ADDRESS = vm.envAddress("POPCAT"); // Replace with actual POPCAT token address
    uint256 POPCAT_DECIMALS = vm.envUint("POPCAT_DECIMAL");
    bytes32 POPCAT_PYTH_FEED_MAINNET = vm.envBytes32("POPCAT_PYTH_FEED_MAINNET"); // Replace with actual price feed ID
    uint256 POPCAT_MAX_LEVERAGE = vm.envUint("POPCAT_MAX_LEVERAGE");

    function setUp() public {
        // Fork the CORE network at the latest block
        vm.createSelectFork(CORE_RPC_URL);

        // Initialize contract interfaces with deployed contract addresses
        vault = Vault(VAULT_ADDRESS);
        utils = Utils(UTILS_ADDRESS);
        priceFeed = PriceFeed(PRICEFEED_ADDRESS);

        // Set environment variables for the script
        vm.setEnv("PRIVATE_KEY_ADMIN", vm.toString(vm.envUint("PRIVATE_KEY_ADMIN"))); // Convert uint to string
        vm.setEnv("UTILS", vm.toString(UTILS_ADDRESS));
        vm.setEnv("VAULT", vm.toString(VAULT_ADDRESS));
        vm.setEnv("PRICEFEED", vm.toString(PRICEFEED_ADDRESS));

        // Set environment variables for DOGE
        vm.setEnv("DOGE", vm.toString(DOGE_ADDRESS));
        vm.setEnv("DOGE_DECIMAL", vm.toString(DOGE_DECIMALS));
        vm.setEnv("DOGE_PYTH_FEED_MAINNET", vm.toString(DOGE_PYTH_FEED_MAINNET));
        vm.setEnv("DOGE_MAX_LEVERAGE", vm.toString(DOGE_MAX_LEVERAGE));

        // Set environment variables for POPCAT
        vm.setEnv("POPCAT", vm.toString(POPCAT_ADDRESS));
        vm.setEnv("POPCAT_DECIMAL", vm.toString(POPCAT_DECIMALS));
        vm.setEnv("POPCAT_PYTH_FEED_MAINNET", vm.toString(POPCAT_PYTH_FEED_MAINNET));
        vm.setEnv("POPCAT_MAX_LEVERAGE", vm.toString(POPCAT_MAX_LEVERAGE));

        // Initialize the script
        script = new ListNewPerp();
    }

    function testAddPerp() public {
        // Run the script to add new index tokens
        script.run();

        // Test for DOGE
        verifyPerpConfiguration(
            "DOGE",
            DOGE_ADDRESS,
            DOGE_DECIMALS,
            DOGE_MAX_LEVERAGE,
            2_000, // maxGlobalLongSize
            2_000, // maxGlobalShortSize
            5_000, // oiImbalanceThreshold
            5_000, // globalLongSizesLimitBps
            5_000, // globalShortSizesLimitBps
            500, // slippage
            700, // maintenanceMargin
            5 // premiumPositionFee
        );

        // Test for POPCAT
        verifyPerpConfiguration(
            "POPCAT",
            POPCAT_ADDRESS,
            POPCAT_DECIMALS,
            POPCAT_MAX_LEVERAGE,
            2_000, // maxGlobalLongSize
            2_000, // maxGlobalShortSize
            5_000, // oiImbalanceThreshold
            5_000, // globalLongSizesLimitBps
            5_000, // globalShortSizesLimitBps
            500, // slippage
            700, // maintenanceMargin
            5 // premiumPositionFee
        );
    }

    function verifyPerpConfiguration(
        string memory perpName,
        address perpAddress,
        uint256 expectedDecimals,
        uint256 expectedMaxLeverage,
        uint256 expectedMaxGlobalLongSize,
        uint256 expectedMaxGlobalShortSize,
        uint256 expectedOiImbalanceThreshold,
        uint256 expectedGlobalLongSizesLimitBps,
        uint256 expectedGlobalShortSizesLimitBps,
        uint256 expectedSlippage,
        uint256 expectedMaintenanceMargin,
        int256 expectedPremiumPositionFee
    ) internal {
        // Start of Selection
        bool whitelisted = vault.whitelistedTokens(perpAddress);
        uint256 decimals = vault.tokenDecimals(perpAddress);
        bool isStable = vault.stableTokens(perpAddress);
        bool canBeCollateralToken = vault.canBeCollateralToken(perpAddress);
        bool canBeIndexToken = vault.canBeIndexToken(perpAddress);
        uint256 maxLeverage = vault.maxLeverage(perpAddress);

        assertEq(decimals, expectedDecimals, string(abi.encodePacked(perpName, ": Decimals mismatch")));
        assertEq(isStable, false, string(abi.encodePacked(perpName, ": isStable mismatch")));
        assertEq(canBeCollateralToken, false, string(abi.encodePacked(perpName, ": canBeCollateralToken mismatch")));
        assertEq(canBeIndexToken, true, string(abi.encodePacked(perpName, ": canBeIndexToken mismatch")));
        assertEq(maxLeverage, expectedMaxLeverage, string(abi.encodePacked(perpName, ": Max Leverage mismatch")));

        // Check Vault global sizes and thresholds
        uint256 maxGlobalLongSize = vault.maxGlobalLongSizesBps(perpAddress);
        uint256 maxGlobalShortSize = vault.maxGlobalShortSizesBps(perpAddress);
        uint256 oiImbalanceThreshold = vault.oiImbalanceThreshold(perpAddress);
        uint256 globalLongSizesLimitBps = vault.globalLongSizesLimitBps(perpAddress);
        uint256 globalShortSizesLimitBps = vault.globalShortSizesLimitBps(perpAddress);

        assertEq(
            maxGlobalLongSize,
            expectedMaxGlobalLongSize,
            string(abi.encodePacked(perpName, ": Max Global Long Size mismatch"))
        );
        assertEq(
            maxGlobalShortSize,
            expectedMaxGlobalShortSize,
            string(abi.encodePacked(perpName, ": Max Global Short Size mismatch"))
        );
        assertEq(
            oiImbalanceThreshold,
            expectedOiImbalanceThreshold,
            string(abi.encodePacked(perpName, ": OI Imbalance Threshold mismatch"))
        );
        assertEq(
            globalLongSizesLimitBps,
            expectedGlobalLongSizesLimitBps,
            string(abi.encodePacked(perpName, ": Global Long Sizes Limit Bps mismatch"))
        );
        assertEq(
            globalShortSizesLimitBps,
            expectedGlobalShortSizesLimitBps,
            string(abi.encodePacked(perpName, ": Global Short Sizes Limit Bps mismatch"))
        );

        // Check PriceFeed configurations
        bytes32 priceId = priceFeed.tokenPriceIdMapping(perpAddress);
        bytes32 expectedPriceId = vm.envBytes32(string(abi.encodePacked(perpName, "_PYTH_FEED_MAINNET")));
        assertEq(priceId, expectedPriceId, string(abi.encodePacked(perpName, ": Price ID mismatch")));

        uint256 slippage = priceFeed.slippage(perpAddress);
        assertEq(slippage, expectedSlippage, string(abi.encodePacked(perpName, ": Slippage mismatch")));

        // Check Utils configurations
        uint256 maintenanceMargin = utils.maintanenceMargin(perpAddress);
        assertEq(
            maintenanceMargin,
            expectedMaintenanceMargin,
            string(abi.encodePacked(perpName, ": Maintenance Margin mismatch"))
        );

        int256 premiumPositionFee = utils.tokenPremiumPositionFee(perpAddress);
        assertEq(
            premiumPositionFee,
            expectedPremiumPositionFee,
            string(abi.encodePacked(perpName, ": Premium Position Fee mismatch"))
        );
        console.log(unicode"✅", perpName, ": All configurations verified successfully");
    }
}
