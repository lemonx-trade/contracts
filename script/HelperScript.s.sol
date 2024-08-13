// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;
import "forge-std/Script.sol";
import '../src/contracts/libraries/token/IERC20.sol';
import '../src/contracts/core/RewardRouter.sol';
import '../src/contracts/core/RewardTracker.sol';
import '../src/contracts/core/Utils.sol';
import '../src/contracts/core/ReaderContract.sol';
import '../src/contracts/core/Vault.sol';
import '../src/contracts/core/interfaces/IVault.sol';


contract HelperScript is Script {


    //util functions
    function addLiquidity() public {
        IERC20 usdc = IERC20(vm.envAddress("LINEA_USDCL"));
        usdc.approve(vm.envAddress("LINEA_LLP_MANAGER"), 10000000*10**18);
        RewardRouter rewardRouter = RewardRouter(vm.envAddress("LINEA_REWARD_ROUTER"));
        rewardRouter.mintLlp(vm.envAddress("LINEA_USDCL"), 100000000000000000000000, 0, 0);
    }

    function distributeRewards() public {
        uint usdcAmount = 568*10**6;
        RewardTracker rewardTracker = RewardTracker(vm.envAddress("REWARD_TRACKER"));
        uint stakedAmount = rewardTracker.totalSupply();
        console.log("staked amount: ", stakedAmount);
        uint rewardPerToken = (usdcAmount* rewardTracker.rewardPrecision())/stakedAmount;
        console.log("reward per token: ", rewardPerToken);
        uint cumRewardPerToken = rewardTracker.cummulativeRewardPerLPToken() + rewardPerToken;
        rewardTracker.setCummulativeRewardRate(cumRewardPerToken);
        uint amount = rewardTracker.claimable(0x818484227ABF04550c6c242B6119B7c94d2E72b3);
        console.log("Amount: ", amount);
    }

    function changeTierBorrowingRates() public {
        Utils utils = Utils(0xB25d0932F2d9FFC4aE602256f123839c23C2785F);
        utils.setTier1Factor(5);
        utils.setTier2Factor(5);
        utils.setTier3Factor(5);
        ReaderContract readerContract = ReaderContract(0x75cC8fEAb5DfcC0B69E5Cf26dae0f9Ebcf31739a);
        readerContract.setTier1Factor(5);
        readerContract.setTier2Factor(5);
        readerContract.setTier3Factor(5);
    }

    // function addNewPerp(Vault vault) public {
    //     vault.setTokenConfig(vm.envAddress("INDEX_TOKEN"), 18, 0, false, false, true, 240000);
    //     vault.setMaxGlobalLongSize(vm.envAddress("INDEX_TOKEN"), maxGlobalLongSizeEth);
    //     vault.setMaxGlobalShortSize(vm.envAddress("INDEX_TOKEN"), maxGlobalShortSizeEth);
    //     vault.setOiImbalanceThreshold(vm.envAddress("INDEX_TOKEN"), oiImbalanceThreshold);
    //     vault.setBorrowingRate(vm.envAddress("INDEX_TOKEN"), borrowingInterval, 0, borrowingExponent);
    //     vault.setFundingRate(vm.envAddress("INDEX_TOKEN"), fundingInterval, fundingRateFactor, fundingExponent);
    // }
}