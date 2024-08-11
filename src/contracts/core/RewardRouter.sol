// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.19;

import "../libraries/token/IERC20.sol";
import "../libraries/utils/ReentrancyGuard.sol";
import "../libraries/token/Address.sol";
import "./interfaces/IRewardTracker.sol";
import "./interfaces/IRewardRouter.sol";
import "../core/interfaces/ILlpManager.sol";
import "../access/Governable.sol";
import "../libraries/token/SafeERC20.sol";
import "../libraries/utils/Structs.sol";

contract RewardRouter is IRewardRouter, ReentrancyGuard, Governable {
    using SafeERC20 for IERC20;
    using Address for address payable;

    bool public isInitialized;

    address public llp; // LemonX Liquidity Provider token

    address public llpManager;
    uint256 public minExecutionFee;
    mapping(address => bool) public isKeeper;

    mapping(address => uint256) public mintAccountIdx;
    mapping(address => uint256) public burnAccountIdx;
    mapping(bytes32 => StructsUtils.MintLLPRequest) public mintRequests;
    mapping(bytes32 => StructsUtils.BurnLLPRequest) public burnReqeusts;

    address public override feeLlpTracker;
    bytes32[] public arrayOfMintRequests;
    bytes32[] public arrayOfBurnRequests;
    uint256 public mintRequestExecuteStart;
    uint256 public burnRequestExecuteStart;

    event CreateMintRequest(address indexed account, uint256 amount);
    event CreateBurnRequest(address indexed account, uint256 amount);
    event CancelMintRequest(address indexed account, uint256 amount);
    event CancelBurnRequest(address indexed account, uint256 amount);
    event Mintllp(address indexed account, uint256 amount);
    event Burnllp(address indexed account, uint256 amount);

    function initialize(address _llp, address _llpManager, address _feeLlpTracker) external onlyGov {
        require(!isInitialized, "RewardRouter: already initialized");
        isInitialized = true;
        llp = _llp;
        llpManager = _llpManager;
        feeLlpTracker = _feeLlpTracker;
    }

    modifier isContract(address account) {
        require(account != address(0), "nulladd");
        uint256 size;
        assembly {
            size := extcodesize(account)
        }
        require(size > 0, "eoa");
        _;
    }

    modifier onlyKeeper() {
        require(isKeeper[msg.sender] || (msg.sender == address(this)), "RewardRouter: Not keeper");
        _;
    }
    //  M2 check for isContract
    //  L1 missing events

    function setFeeLlpTracker(address _feeLlpTracker) external onlyGov isContract(_feeLlpTracker) {
        feeLlpTracker = _feeLlpTracker;
    }
    //  M2 check for isContract
    // TODO: L1 missing events

    function setLlpManager(address _llpManager) external onlyGov isContract(_llpManager) {
        llpManager = _llpManager;
    }
    //  M2 check for isContract
    // TODO: L1 missing events

    function setLlp(address _llp) external onlyGov isContract(_llp) {
        llp = _llp;
    }
    // TODO: M1 ensure less than 25% update
    // TODO: M3 missing for threshold

    function setMinExecutionFee(uint256 _minExecutionFee) external onlyGov {
        minExecutionFee = _minExecutionFee;
    }
    // TODO: L4 zero or dead address check

    function setKeeperStatus(address newKeeper, bool status) external onlyGov {
        isKeeper[newKeeper] = status;
    }

    // to help users who accidentally send their tokens to this contract
    function withdrawToken(address _token, address _account, uint256 _amount) external onlyGov {
        IERC20(_token).safeTransfer(_account, _amount);
    }

    function mintLlp(address _token, uint256 _amount, uint256 _minUsdl, uint256 _minLlp)
        external
        nonReentrant
        returns (uint256)
    {
        require(_amount > 0, "RewardRouter: invalid _amount");

        address account = msg.sender;
        uint256 llpAmount =
            ILlpManager(llpManager).addLiquidityForAccount(account, account, _token, _amount, _minUsdl, _minLlp);
        emit Mintllp(account, llpAmount);
        return llpAmount;
    }

    function burnLlp(uint256 _llpAmount, uint256 _minOut, address tokenOut) external nonReentrant returns (uint256) {
        require(_llpAmount > 0, "RewardRouter: invalid _llpAmount");

        address account = msg.sender;
        uint256 amountOut =
            ILlpManager(llpManager).removeLiquidityForAccount(account, tokenOut, _llpAmount, _minOut, account);
        emit Burnllp(account, _llpAmount);

        return amountOut;
    }

    function stakeLlp(uint256 llpAmount) external nonReentrant {
        require(llpAmount > 0, "RewardRouter: llpAmount too low");
        address account = msg.sender;
        IRewardTracker(feeLlpTracker).stakeForAccount(account, account, llp, llpAmount);
    }

    function unstakeLlp(uint256 amount) external nonReentrant {
        address account = msg.sender;
        IRewardTracker(feeLlpTracker).unstakeForAccount(account, llp, amount, account);
    }

    function claimStakeRewards() external nonReentrant returns (uint256) {
        address account = msg.sender;
        return IRewardTracker(feeLlpTracker).claimForAccount(account, account);
    }

    function createMintRequest(
        address account,
        uint256 executionFee,
        address token,
        uint256 amount,
        uint256 minUsdl,
        uint256 minLLP
    ) external payable {
        require(executionFee >= minExecutionFee, "RewardRouter: Not enough execution fee");
        require(executionFee == msg.value, "RewardRouter: execution fee doesn't match");
        require(ILlpManager(llpManager).whiteListedTokens(token), "RewardRouter: not suported LP token");
        IERC20(token).safeTransferFrom(account, address(this), amount);
        _createMintRequest(account, executionFee, token, amount, minUsdl, minLLP);
    }

    function _createMintRequest(
        address account,
        uint256 executionFee,
        address token,
        uint256 amount,
        uint256 minUsdl,
        uint256 minLLP
    ) internal {
        uint256 requestIdx = mintAccountIdx[account];
        bytes32 requestKey = getRequestKey(account, requestIdx);
        mintAccountIdx[account] = requestIdx + 1;
        StructsUtils.MintLLPRequest memory mintRequest =
            StructsUtils.MintLLPRequest(account, amount, token, executionFee, minUsdl, minLLP);
        mintRequests[requestKey] = mintRequest;
        arrayOfMintRequests.push(requestKey);
        emit CreateMintRequest(account, amount);
    }

    function createBurnRequest(
        address account,
        uint256 executionFee,
        address token,
        uint256 amount,
        uint256 minOut,
        address receiver
    ) external payable {
        require(executionFee >= minExecutionFee, "RewardRouter: Not enough execution fee");
        require(executionFee == msg.value, "RewardRouter: execution fee doesn't match");
        require(msg.sender == account, "RewardRouter: account should be same as msg.sender");
        require(IERC20(llp).balanceOf(account) >= amount, "RewardRouter: insuff LLP");
        uint256 requestIdx = burnAccountIdx[account];
        bytes32 requestKey = getRequestKey(account, requestIdx);
        burnAccountIdx[account] = requestIdx + 1;
        StructsUtils.BurnLLPRequest memory burnRequest =
            StructsUtils.BurnLLPRequest(account, amount, token, minOut, receiver, executionFee);
        burnReqeusts[requestKey] = burnRequest;
        arrayOfBurnRequests.push(requestKey);
        emit CreateBurnRequest(account, amount);
    }

    function getRequestKey(address account, uint256 index) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(account, index));
    }

    function executeMintRequests(uint256 endIndex, address payable feeReceiver) external onlyKeeper returns (uint256) {
        uint256 lastIdx = arrayOfMintRequests.length;
        uint256 index = mintRequestExecuteStart;
        if (index >= lastIdx) {
            return index;
        }

        if (endIndex > lastIdx) {
            endIndex = lastIdx;
        }
        while (index < endIndex) {
            bytes32 requestKey = arrayOfMintRequests[index];
            try this._executeMintRequest(requestKey, feeReceiver) returns (bool _wasExecuted) {
                if (!_wasExecuted) {
                    break;
                }
            } catch {
                try this._cancelMintRequest(requestKey, feeReceiver) returns (bool _wasCancelled) {
                    if (!_wasCancelled) {}
                } catch {
                    continue;
                }
            }
            index++;
            delete mintRequests[requestKey];
        }
        mintRequestExecuteStart = index;
        return index;
    }

    function executeBurnRequests(uint256 endIndex, address payable feeReceiver) external onlyKeeper returns (uint256) {
        uint256 lastIdx = arrayOfBurnRequests.length;
        uint256 index = burnRequestExecuteStart;
        if (index >= lastIdx) {
            return index;
        }

        if (endIndex > lastIdx) {
            endIndex = lastIdx;
        }
        while (index < endIndex) {
            bytes32 requestKey = arrayOfBurnRequests[index];
            try this._executeBurnRequest(requestKey, feeReceiver) returns (bool _wasExecuted) {
                if (!_wasExecuted) {
                    break;
                }
            } catch {
                try this._cancelBurnRequest(requestKey, feeReceiver) returns (bool _wasCancelled) {
                    if (!_wasCancelled) {}
                } catch {
                    continue;
                }
            }
            index++;
            delete burnReqeusts[requestKey];
        }
        burnRequestExecuteStart = index;
        return index;
    }

    function _executeMintRequest(bytes32 requestKey, address payable feeReceiver) public onlyKeeper returns (bool) {
        StructsUtils.MintLLPRequest memory mintRequest = mintRequests[requestKey];
        if (mintRequest.account == address(0)) {
            return true;
        }
        IERC20(mintRequest.collateralToken).approve(llpManager, mintRequest.amount);
        uint256 llpAmount = ILlpManager(llpManager).addLiquidityForAccount(
            address(this),
            mintRequest.account,
            mintRequest.collateralToken,
            mintRequest.amount,
            mintRequest.minUsdl,
            mintRequest.minUsdl
        );
        emit Mintllp(mintRequest.account, llpAmount);
        (bool success,) = feeReceiver.call{value: mintRequest.executionFee}("");
        require(success, "Failed to send mint execution fee to keeper");
        return true;
    }

    function _cancelMintRequest(bytes32 requestKey, address payable feeReceiver) public onlyKeeper returns (bool) {
        StructsUtils.MintLLPRequest memory mintRequest = mintRequests[requestKey];
        if (mintRequest.account == address(0)) {
            return true;
        }
        IERC20(mintRequest.collateralToken).transfer(mintRequest.account, mintRequest.amount);
        (bool success,) = feeReceiver.call{value: mintRequest.executionFee}("");
        require(success, "Failed to send mint execution fee to keeper");
        emit CancelMintRequest(mintRequest.account, mintRequest.amount);
        return true;
    }

    function _executeBurnRequest(bytes32 requestKey, address payable feeReceiver) public onlyKeeper returns (bool) {
        StructsUtils.BurnLLPRequest memory burnRequest = burnReqeusts[requestKey];
        if (burnRequest.account == address(0)) {
            return true;
        }
        uint256 llpAmount = ILlpManager(llpManager).removeLiquidityForAccount(
            burnRequest.account,
            burnRequest.collateralToken,
            burnRequest.amount,
            burnRequest.minOut,
            burnRequest.receiver
        );
        emit Burnllp(burnRequest.account, llpAmount);
        (bool success,) = feeReceiver.call{value: burnRequest.executionFee}("");
        require(success, "Failed to send mint execution fee to keeper");
        return true;
    }

    function _cancelBurnRequest(bytes32 requestKey, address payable feeReceiver) public onlyKeeper returns (bool) {
        StructsUtils.BurnLLPRequest memory burnRequest = burnReqeusts[requestKey];
        if (burnRequest.account == address(0)) {
            return true;
        }
        emit CancelBurnRequest(burnRequest.account, burnRequest.amount);
        return true;
    }

    function getMintRequestsCount() public view returns (uint256) {
        return arrayOfMintRequests.length;
    }

    function getBurnRequestsCount() public view returns (uint256) {
        return arrayOfBurnRequests.length;
    }
}
