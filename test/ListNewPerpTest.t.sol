// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "../script/ListNewPerp.s.sol";
import "../src/contracts/core/Vault.sol";
import "../src/contracts/core/PriceFeed.sol";
import "../src/contracts/core/Utils.sol";

contract ListNewPerpTest is Test {
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

    // Perp configuration struct
    struct PerpConfig {
        string perpName;
        address perpAddress;
        uint256 decimals;
        uint256 maxLeverage;
        uint256 maxGlobalLongSize;
        uint256 maxGlobalShortSize;
        uint256 oiImbalanceThreshold;
        uint256 globalLongSizesLimitBps;
        uint256 globalShortSizesLimitBps;
        uint256 slippage;
        uint256 maintenanceMargin;
        int256 premiumPositionFee;
    }

    function setUp() public {
        // Fork the CORE network at the latest block
        vm.createSelectFork(CORE_RPC_URL);

        // Initialize contract interfaces with deployed contract addresses
        vault = Vault(VAULT_ADDRESS);
        utils = Utils(UTILS_ADDRESS);
        priceFeed = PriceFeed(PRICEFEED_ADDRESS);
    }

    function testVerifyPerpConfiguration() public {
        /* // Define expected configurations for DOGE
        PerpConfig memory dogeConfig = PerpConfig({
            perpName: "DOGE",
            perpAddress: vm.envAddress("DOGE"),
            decimals: vm.envUint("DOGE_DECIMAL"),
            maxLeverage: vm.envUint("DOGE_MAX_LEVERAGE"),
            maxGlobalLongSize: 2_000,
            maxGlobalShortSize: 2_000,
            oiImbalanceThreshold: 5_000,
            globalLongSizesLimitBps: 5_000,
            globalShortSizesLimitBps: 5_000,
            slippage: 500,
            maintenanceMargin: 700,
            premiumPositionFee: 0
        });

        // Verify DOGE configuration
        verifyPerpConfiguration(dogeConfig);

        // Define expected configurations for POPCAT
        PerpConfig memory popcatConfig = PerpConfig({
            perpName: "POPCAT",
            perpAddress: vm.envAddress("POPCAT"),
            decimals: vm.envUint("POPCAT_DECIMAL"),
            maxLeverage: vm.envUint("POPCAT_MAX_LEVERAGE"),
            maxGlobalLongSize: 2_000,
            maxGlobalShortSize: 2_000,
            oiImbalanceThreshold: 5_000,
            globalLongSizesLimitBps: 5_000,
            globalShortSizesLimitBps: 5_000,
            slippage: 500,
            maintenanceMargin: 700,
            premiumPositionFee: 0
        });

        // Verify POPCAT configuration
        verifyPerpConfiguration(popcatConfig); */

        PerpConfig memory dogeConfig = PerpConfig({
            perpName: "BTC",
            perpAddress: vm.envAddress("BTC"),
            decimals: vm.envUint("BTC_DECIMAL"),
            maxLeverage: vm.envUint("BTC_MAX_LEVERAGE"),
            maxGlobalLongSize: 10_000,
            maxGlobalShortSize: 10_000,
            oiImbalanceThreshold: 10_000,
            globalLongSizesLimitBps: 100_000,
            globalShortSizesLimitBps: 100_000,
            slippage: 200,
            maintenanceMargin: 150,
            premiumPositionFee: 0
        });

        // Verify DOGE configuration
        verifyPerpConfiguration(dogeConfig);
    }

    function verifyPerpConfiguration(PerpConfig memory config) internal {
        // Fetch values from Vault
        uint256 decimals = vault.tokenDecimals(config.perpAddress);
        bool isStable = vault.stableTokens(config.perpAddress);
        bool canBeCollateralToken = vault.canBeCollateralToken(config.perpAddress);
        bool canBeIndexToken = vault.canBeIndexToken(config.perpAddress);
        uint256 maxLeverage = vault.maxLeverage(config.perpAddress);

        // Assert values
        assertEq(decimals, config.decimals, string(abi.encodePacked(config.perpName, ": Decimals mismatch")));
        assertEq(isStable, false, string(abi.encodePacked(config.perpName, ": isStable mismatch")));
        assertEq(
            canBeCollateralToken, false, string(abi.encodePacked(config.perpName, ": canBeCollateralToken mismatch"))
        );
        assertEq(canBeIndexToken, true, string(abi.encodePacked(config.perpName, ": canBeIndexToken mismatch")));
        assertEq(maxLeverage, config.maxLeverage, string(abi.encodePacked(config.perpName, ": Max Leverage mismatch")));

        // Check Vault global sizes and thresholds
        uint256 maxGlobalLongSize = vault.maxGlobalLongSizesBps(config.perpAddress);
        uint256 maxGlobalShortSize = vault.maxGlobalShortSizesBps(config.perpAddress);
        uint256 oiImbalanceThreshold = vault.oiImbalanceThreshold(config.perpAddress);
        uint256 globalLongSizesLimitBps = vault.globalLongSizesLimitBps(config.perpAddress);
        uint256 globalShortSizesLimitBps = vault.globalShortSizesLimitBps(config.perpAddress);

        assertEq(
            maxGlobalLongSize,
            config.maxGlobalLongSize,
            string(abi.encodePacked(config.perpName, ": Max Global Long Size mismatch"))
        );
        assertEq(
            maxGlobalShortSize,
            config.maxGlobalShortSize,
            string(abi.encodePacked(config.perpName, ": Max Global Short Size mismatch"))
        );
        assertEq(
            oiImbalanceThreshold,
            config.oiImbalanceThreshold,
            string(abi.encodePacked(config.perpName, ": OI Imbalance Threshold mismatch"))
        );
        assertEq(
            globalLongSizesLimitBps,
            config.globalLongSizesLimitBps,
            string(abi.encodePacked(config.perpName, ": Global Long Sizes Limit Bps mismatch"))
        );
        assertEq(
            globalShortSizesLimitBps,
            config.globalShortSizesLimitBps,
            string(abi.encodePacked(config.perpName, ": Global Short Sizes Limit Bps mismatch"))
        );

        // Check PriceFeed configurations
        bytes32 priceId = priceFeed.tokenPriceIdMapping(config.perpAddress);
        bytes32 expectedPriceId = vm.envBytes32(string(abi.encodePacked(config.perpName, "_PYTH_FEED_MAINNET")));
        assertEq(priceId, expectedPriceId, string(abi.encodePacked(config.perpName, ": Price ID mismatch")));

        uint256 slippage = priceFeed.slippage(config.perpAddress);
        assertEq(slippage, config.slippage, string(abi.encodePacked(config.perpName, ": Slippage mismatch")));

        // Check Utils configurations
        uint256 maintenanceMargin = utils.maintanenceMargin(config.perpAddress);
        assertEq(
            maintenanceMargin,
            config.maintenanceMargin,
            string(abi.encodePacked(config.perpName, ": Maintenance Margin mismatch"))
        );

        int256 premiumPositionFee = utils.tokenPremiumPositionFee(config.perpAddress);
        assertEq(
            premiumPositionFee,
            config.premiumPositionFee,
            string(abi.encodePacked(config.perpName, ": Premium Position Fee mismatch"))
        );

        console.log(unicode"✅", config.perpName, ": All configurations verified successfully");
    }
}
