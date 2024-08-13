// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "../libraries/token/SafeERC20.sol";
import "../libraries/utils/ReentrancyGuard.sol";
import "../libraries/token/IERC20.sol";
import "./BaseOrderManager.sol";
import "./interfaces/IOrderManager.sol";
import "../libraries/utils/EnumerableSet.sol";
import "./../libraries/utils/Structs.sol";
import "../libraries/utils/Structs.sol";

contract OrderManager is BaseOrderManager, IOrderManager, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public minExecutionFeeIncreaseMarketOrder;
    uint256 public minExecutionFeeDecreaseMarketOrder;
    uint256 public minExecutionFeeIncreaseLimitOrder;
    uint256 public minExecutionFeeDecreaseLimitOrder;
    mapping(address => uint256) public increasePositionsIndex;
    mapping(bytes32 => StructsUtils.IncreasePositionRequest) public increasePositionRequests;
    bytes32[] public increasePositionRequestKeys;
    mapping(address => uint256) public decreasePositionsIndex;
    mapping(bytes32 => StructsUtils.DecreasePositionRequest) public decreasePositionRequests;
    //  L3 missing visibility
    bytes32[] internal decreasePositionRequestKeys;
    mapping(address => bool) public isPositionKeeper;
    uint256 public minBlockDelayKeeper;
    uint256 public minTimeDelayPublic;
    uint256 public maxTimeDelay;
    uint256 public increasePositionRequestKeysStart;
    uint256 public decreasePositionRequestKeysStart;

    mapping(bytes32 => StructsUtils.Order) public orders;
    EnumerableSet.Bytes32Set private orderKeys;
    mapping(address => uint256) public ordersIndex;
    mapping(address => bool) public isOrderKeeper;
    mapping(address => bool) public isLiquidator;
    uint256 public maxProfitMultiplier;

    uint256 public minPurchaseUSDAmountMarketOrder; //this will be in 10^18
    uint256 public minPurchaseUSDAmountLimitOrder; // this will be in 10^18

    event CreateIncreasePosition(
        address indexed account,
        address _collateralToken,
        address indexToken,
        uint256 amountIn,
        uint256 sizeDelta,
        bool isLong,
        uint256 acceptablePrice,
        uint256 executionFee,
        uint256 index,
        uint256 queueIndex,
        uint256 blockNumber,
        uint256 blockTime,
        uint256 gasPrice
    );

    event CancelIncreasePosition(
        address indexed account,
        address _collateralToken,
        address indexToken,
        uint256 amountIn,
        uint256 sizeDelta,
        bool isLong,
        uint256 acceptablePrice,
        uint256 executionFee,
        uint256 blockGap,
        uint256 timeGap
    );

    event CreateDecreasePosition(
        address indexed account,
        address _collateralToken,
        address indexToken,
        uint256 sizeDelta,
        bool isLong,
        address receiver,
        uint256 acceptablePrice,
        uint256 executionFee,
        uint256 index,
        uint256 queueIndex,
        uint256 blockNumber,
        uint256 blockTime
    );

    event ExecuteDecreasePosition(
        address indexed account,
        address _collateralToken,
        address indexToken,
        uint256 sizeDelta,
        bool isLong,
        address receiver,
        uint256 acceptablePrice,
        uint256 executionFee,
        uint256 blockGap,
        uint256 timeGap
    );

    event CancelDecreasePosition(
        address indexed account,
        address _collateralToken,
        address indexToken,
        uint256 sizeDelta,
        bool isLong,
        address receiver,
        uint256 acceptablePrice,
        uint256 executionFee,
        uint256 blockGap,
        uint256 timeGap
    );

    event ExecuteIncreasePosition(
        address indexed account,
        address _collateralToken,
        address indexToken,
        uint256 amountIn,
        uint256 sizeDelta,
        bool isLong,
        uint256 acceptablePrice,
        uint256 executionFee,
        uint256 blockGap,
        uint256 timeGap
    );

    event CreateOrder(
        address indexed account,
        address collateralToken,
        address indexToken,
        uint256 orderIndex,
        uint256 collateralDelta,
        uint256 sizeDelta,
        uint256 triggerPrice,
        uint256 executionFee,
        bool isLong,
        bool triggerAboveThreshold,
        bool indexed isIncreaseOrder,
        bool isMaxOrder
    );

    event UpdateOrder(
        address indexed account,
        address collateralToken,
        address indexToken,
        uint256 orderIndex,
        uint256 collateralDelta,
        uint256 sizeDelta,
        uint256 triggerPrice,
        bool isLong,
        bool triggerAboveThreshold,
        bool indexed isIncreaseOrder,
        bool isMaxOrder
    );

    event CancelOrder(
        address indexed account,
        address collateralToken,
        address indexToken,
        uint256 orderIndex,
        uint256 collateralDelta,
        uint256 sizeDelta,
        uint256 triggerPrice,
        uint256 executionFee,
        bool isLong,
        bool triggerAboveThreshold,
        bool indexed isIncreaseOrder,
        bool isMaxOrder
    );
    event ExecuteOrder(
        address indexed account,
        address collateralToken,
        address indexToken,
        uint256 orderIndex,
        uint256 collateralDelta,
        uint256 sizeDelta,
        uint256 triggerPrice,
        uint256 executionFee,
        uint256 executionPrice,
        bool isLong,
        bool triggerAboveThreshold,
        bool indexed isIncreaseOrder
    );

    event SetPositionKeeper(address indexed account, bool isActive);
    event SetOrderKeeper(address indexed account, bool isActive);
    event SetLiquidator(address indexed account, bool isActive);

    event SetDelayValues(uint256 minBlockDelayKeeper, uint256 minTimeDelayPublic, uint256 maxTimeDelay);

    constructor(
        address _vault,
        address _utils,
        address _pricefeed,
        uint256 _minExecutionFeeMarketOrder,
        uint256 _minExecutionFeeLimitOrder,
        uint256 _depositFee,
        uint256 _maxProfitMultiplier,
        uint256 _minPurchaseUSDAmountLimitOrder,
        uint256 _minPurchaseUSDAmountMarketOrder
    ) BaseOrderManager(_vault, _utils, _pricefeed, _depositFee) {
        minExecutionFeeIncreaseMarketOrder = _minExecutionFeeMarketOrder;
        minExecutionFeeDecreaseMarketOrder = _minExecutionFeeMarketOrder;
        minExecutionFeeIncreaseLimitOrder = _minExecutionFeeLimitOrder;
        minExecutionFeeDecreaseLimitOrder = _minExecutionFeeLimitOrder;
        maxProfitMultiplier = _maxProfitMultiplier;
        minPurchaseUSDAmountMarketOrder = _minPurchaseUSDAmountMarketOrder;
        minPurchaseUSDAmountLimitOrder = _minPurchaseUSDAmountLimitOrder;
    }

    modifier onlyPositionKeeper() {
        require(isPositionKeeper[msg.sender], "OM:403");
        _;
    }

    modifier onlyLiquidator() {
        require(isLiquidator[msg.sender], "OM:403");
        _;
    }

    modifier onlyOrderKeeper() {
        require(isOrderKeeper[msg.sender], "OM:403");
        _;
    }

    //  M3 missing for threshold - NOTE: Business logic
    //  L1 missing events

    function setMinPurchaseAmount(uint256 _marketOrder, uint256 _limitOrder) external onlyAdmin {
        uint256 oldValueVariableOne = _marketOrder;
        uint256 oldValueVariableTwo = _limitOrder;
        minPurchaseUSDAmountMarketOrder = _marketOrder;
        minPurchaseUSDAmountLimitOrder = _limitOrder;
        emit ValueChanged(1, oldValueVariableOne, _marketOrder);
        emit ValueChanged(2, oldValueVariableTwo, _limitOrder);
    }

    function setPositionKeeper(address _account, bool _isActive) external onlyAdmin {
        isPositionKeeper[_account] = _isActive;
        emit SetPositionKeeper(_account, _isActive);
    }
    //  M3 missing for threshold
    //  L1 missing events

    function setMaxTPMultiplier(uint256 _maxProfitMultiplier) external onlyAdmin {
        require(_maxProfitMultiplier >= 1, "mpm");
        uint256 oldValue = maxProfitMultiplier;
        maxProfitMultiplier = _maxProfitMultiplier;
        emit ValueChanged(3, oldValue, _maxProfitMultiplier); // 2 for utils
    }
    //  M3 missing for threshold - NOTE: Business logic
    //  L1 missing events

    function setMinExecutionFeeMarketOrder(
        uint256 _minExecutionFeeIncreaseMarketOrder,
        uint256 _minExecutionFeeDecreaseMarketOrder
    ) external onlyAdmin {
        uint256 oldValueVariableOne = _minExecutionFeeIncreaseMarketOrder;
        uint256 oldValueVariableTwo = _minExecutionFeeDecreaseMarketOrder;
        minExecutionFeeIncreaseMarketOrder = _minExecutionFeeIncreaseMarketOrder;
        minExecutionFeeDecreaseMarketOrder = _minExecutionFeeDecreaseMarketOrder;
        emit ValueChanged(4, oldValueVariableOne, _minExecutionFeeIncreaseMarketOrder);
        emit ValueChanged(5, oldValueVariableTwo, _minExecutionFeeDecreaseMarketOrder);
    }
    //  M3 missing for threshold - NOTE: Business logic
    //  L1 missing events

    function setMinExecutionFeeLimitOrder(
        uint256 _minExecutionFeeIncreaseLimitOrder,
        uint256 _minExecutionFeeDecreaseLimitOrder
    ) external onlyAdmin {
        uint256 oldValueVariableOne = _minExecutionFeeIncreaseLimitOrder;
        uint256 oldValueVariableTwo = _minExecutionFeeDecreaseLimitOrder;
        minExecutionFeeIncreaseLimitOrder = _minExecutionFeeIncreaseLimitOrder;
        minExecutionFeeDecreaseLimitOrder = _minExecutionFeeDecreaseLimitOrder;
        emit ValueChanged(6, oldValueVariableOne, _minExecutionFeeIncreaseLimitOrder);
        emit ValueChanged(7, oldValueVariableTwo, _minExecutionFeeDecreaseLimitOrder);
    }

    function setPriceFeed(address _priceFeed) external override onlyAdmin isContract(_priceFeed) {
        address oldValue = pricefeed;
        pricefeed = _priceFeed;
        emit AddressChanged(8, oldValue, _priceFeed); // 8 for pricefeed
    }
    //  M3 missing for threshold - NOTE: Business logic

    function setDelayValues(uint256 _minBlockDelayKeeper, uint256 _minTimeDelayPublic, uint256 _maxTimeDelay)
        external
        onlyAdmin
    {
        minBlockDelayKeeper = _minBlockDelayKeeper;
        minTimeDelayPublic = _minTimeDelayPublic;
        maxTimeDelay = _maxTimeDelay;
        emit SetDelayValues(_minBlockDelayKeeper, _minTimeDelayPublic, _maxTimeDelay);
    }

    function setOrderKeeper(address _account, bool _isActive) external onlyAdmin {
        isOrderKeeper[_account] = _isActive;
        emit SetOrderKeeper(_account, _isActive);
    }

    function setLiquidator(address _account, bool _isActive) external onlyAdmin {
        isLiquidator[_account] = _isActive;
        emit SetLiquidator(_account, _isActive);
    }

    function createIncreasePosition(
        address _collateralToken,
        address _indexToken,
        uint256 _amountIn,
        uint256 _sizeDelta,
        bool _isLong,
        uint256 _acceptablePrice,
        uint256 takeProfitPrice,
        uint256 stopLossPrice,
        uint256 _executionFee
    ) external payable nonReentrant returns (bytes32) {
        require(!IVault(vault).ceaseTradingActivity(), "OM:0");
        require(IVault(vault).canBeIndexToken(_indexToken), "OM:idx");
        require(_executionFee == msg.value, "OM:ef");
        if (takeProfitPrice == 0 && stopLossPrice == 0) {
            require(_executionFee >= minExecutionFeeIncreaseMarketOrder, "OM:ef");
        } else if (takeProfitPrice != 0 && stopLossPrice != 0) {
            require(
                _executionFee >= minExecutionFeeIncreaseMarketOrder + 2 * minExecutionFeeDecreaseLimitOrder, "OM:ef"
            );
        } else {
            require(
                _executionFee >= minExecutionFeeIncreaseMarketOrder + 1 * minExecutionFeeDecreaseLimitOrder, "OM:ef"
            );
        }
        require(_amountIn >= minPurchaseUSDAmountMarketOrder, "OM:c");
        IERC20(_collateralToken).safeTransferFrom(msg.sender, address(this), _amountIn);
        bytes32 positionKey = _createIncreasePosition(
            msg.sender,
            _collateralToken,
            _indexToken,
            _amountIn,
            _sizeDelta,
            _isLong,
            _acceptablePrice,
            minExecutionFeeIncreaseMarketOrder
        );
        if (takeProfitPrice != 0) {
            _createOrder(
                msg.sender,
                0,
                _collateralToken,
                _indexToken,
                _sizeDelta,
                _isLong,
                takeProfitPrice,
                _isLong,
                minExecutionFeeDecreaseLimitOrder,
                false,
                false
            );
        }
        if (stopLossPrice != 0) {
            _createOrder(
                msg.sender,
                0,
                _collateralToken,
                _indexToken,
                _sizeDelta,
                _isLong,
                stopLossPrice,
                !_isLong,
                minExecutionFeeDecreaseLimitOrder,
                false,
                false
            );
        }

        return positionKey;
    }

    function _createIncreasePosition(
        address _account,
        address _collateralToken,
        address _indexToken,
        uint256 _amountIn,
        uint256 _sizeDelta,
        bool _isLong,
        uint256 _acceptablePrice,
        uint256 _executionFee
    ) internal returns (bytes32) {
        StructsUtils.IncreasePositionRequest memory request = StructsUtils.IncreasePositionRequest(
            _account,
            _collateralToken,
            _indexToken,
            _amountIn,
            _sizeDelta,
            _isLong,
            _acceptablePrice,
            _executionFee,
            block.number,
            block.timestamp
        );

        (uint256 index, bytes32 requestKey) = _storeIncreasePositionRequest(request);
        emit CreateIncreasePosition(
            _account,
            _collateralToken,
            _indexToken,
            _amountIn,
            _sizeDelta,
            _isLong,
            _acceptablePrice,
            _executionFee,
            index,
            increasePositionRequestKeys.length - 1,
            block.number,
            block.timestamp,
            tx.gasprice
        );
        return requestKey;
    }

    function cancelIncreasePosition(bytes32 _key, address payable _executionFeeReceiver)
        public
        nonReentrant
        returns (bool)
    {
        StructsUtils.IncreasePositionRequest memory request = increasePositionRequests[_key];
        // if the request was already executed or cancelled, return true so that the executeIncreasePositions loop will continue executing the next request
        if (request.account == address(0)) {
            return true;
        }

        if (!_validateCancellation(request.blockNumber, request.blockTime, request.account)) {
            return false;
        }

        delete increasePositionRequests[_key];
        IERC20(request._collateralToken).safeTransfer(request.account, request.amountIn);
        (bool success,) = _executionFeeReceiver.call{value: request.executionFee}("");
        require(success, "OM:f");

        emit CancelIncreasePosition(
            request.account,
            request._collateralToken,
            request.indexToken,
            request.amountIn,
            request.sizeDelta,
            request.isLong,
            request.acceptablePrice,
            request.executionFee,
            block.number - request.blockNumber,
            block.timestamp - request.blockTime
        );
        return true;
    }

    function executeIncreasePositions(uint256 _endIndex, address payable _executionFeeReceiver)
        external
        override
        onlyPositionKeeper
        returns (uint256)
    {
        uint256 index = increasePositionRequestKeysStart;
        uint256 length = increasePositionRequestKeys.length;

        if (index >= length) {
            return index;
        }

        if (_endIndex > length) {
            _endIndex = length;
        }

        while (index < _endIndex) {
            bytes32 key = increasePositionRequestKeys[index];

            // if the request was executed then delete the key from the array
            // if the request was not executed then break from the loop, this can happen if the
            // minimum number of blocks has not yet passed
            // an error could be thrown if the request is too old or if the slippage is
            // higher than what the user specified, or if there is insufficient liquidity for the position
            // in case an error was thrown, cancel the request
            try this.executeIncreasePosition(key, _executionFeeReceiver) returns (bool _wasExecuted) {
                if (!_wasExecuted) {
                    break;
                }
            } catch {
                // wrap this call in a try catch to prevent invalid cancels from blocking the loop
                try this.cancelIncreasePosition(key, _executionFeeReceiver) returns (bool _wasCancelled) {
                    if (!_wasCancelled) {
                        break;
                    }
                } catch {
                    continue;
                }
            }

            delete increasePositionRequestKeys[index];
            index++;
        }

        increasePositionRequestKeysStart = index;
        return index;
    }

    function executeIncreasePosition(bytes32 _key, address payable _executionFeeReceiver)
        public
        nonReentrant
        returns (bool)
    {
        StructsUtils.IncreasePositionRequest memory request = increasePositionRequests[_key];
        // if the request was already executed or cancelled, return true so that the executeIncreasePositions loop will continue executing the next request
        if (request.account == address(0)) {
            return true;
        }

        if (!_validateExecution(request.blockNumber, request.blockTime, request.account)) {
            return false;
        }

        delete increasePositionRequests[_key];
        IERC20(request._collateralToken).safeTransfer(
            vault,
            _collectFees(
                request.account,
                request._collateralToken,
                request.amountIn,
                request.indexToken,
                request.isLong,
                request.sizeDelta
            )
        );

        _increasePosition(
            request.account,
            request._collateralToken,
            request.indexToken,
            request.sizeDelta,
            request.isLong,
            request.acceptablePrice
        );

        (bool success,) = _executionFeeReceiver.call{value: request.executionFee}("");
        require(success, "OM:f");

        if (request.sizeDelta > 0) {
            uint256 tpPrice = IUtils(utils).getTPPrice(
                request.sizeDelta,
                request.isLong,
                request.acceptablePrice,
                request.amountIn * maxProfitMultiplier,
                request._collateralToken
            );
            _createOrder(
                request.account,
                0,
                request._collateralToken,
                request.indexToken,
                request.sizeDelta,
                request.isLong,
                tpPrice,
                request.isLong,
                minExecutionFeeDecreaseLimitOrder,
                false,
                true
            );
        }

        emit ExecuteIncreasePosition(
            request.account,
            request._collateralToken,
            request.indexToken,
            request.amountIn,
            request.sizeDelta,
            request.isLong,
            request.acceptablePrice,
            request.executionFee,
            block.number - (request.blockNumber),
            block.timestamp - (request.blockTime)
        );

        return true;
    }

    function _storeIncreasePositionRequest(StructsUtils.IncreasePositionRequest memory _request)
        internal
        returns (uint256, bytes32)
    {
        address account = _request.account;
        uint256 index = increasePositionsIndex[account] + 1;
        increasePositionsIndex[account] = index;
        bytes32 key = getRequestKey(account, index);

        increasePositionRequests[key] = _request;
        increasePositionRequestKeys.push(key);

        return (index, key);
    }

    function createDecreasePosition(
        address _collateralToken,
        address _indexToken,
        uint256 _sizeDelta,
        bool _isLong,
        address _receiver,
        uint256 _acceptablePrice,
        uint256 _executionFee
    ) external payable nonReentrant returns (bytes32) {
        require(!IVault(vault).ceaseTradingActivity(), "OM:0");
        require(_executionFee >= minExecutionFeeDecreaseMarketOrder, "OM:f");
        require(_executionFee == msg.value, "OM:ef");
        require(
            checkSufficientPositionExists(msg.sender, _collateralToken, _indexToken, _isLong, _sizeDelta), "OM:size"
        );

        return _createDecreasePosition(
            msg.sender, _collateralToken, _indexToken, _sizeDelta, _isLong, _receiver, _acceptablePrice, _executionFee
        );
    }

    function _createDecreasePosition(
        address _account,
        address _collateralToken,
        address _indexToken,
        uint256 _sizeDelta,
        bool _isLong,
        address _receiver,
        uint256 _acceptablePrice,
        uint256 _executionFee
    ) internal returns (bytes32) {
        StructsUtils.DecreasePositionRequest memory request = StructsUtils.DecreasePositionRequest(
            _account,
            _collateralToken,
            _indexToken,
            _sizeDelta,
            _isLong,
            _receiver,
            _acceptablePrice,
            _executionFee,
            block.number,
            block.timestamp
        );

        (uint256 index, bytes32 requestKey) = _storeDecreasePositionRequest(request);
        emit CreateDecreasePosition(
            request.account,
            request._collateralToken,
            request.indexToken,
            request.sizeDelta,
            request.isLong,
            request.receiver,
            request.acceptablePrice,
            request.executionFee,
            index,
            decreasePositionRequestKeys.length - 1,
            block.number,
            block.timestamp
        );
        return requestKey;
    }

    function _storeDecreasePositionRequest(StructsUtils.DecreasePositionRequest memory _request)
        internal
        returns (uint256, bytes32)
    {
        address account = _request.account;
        uint256 index = decreasePositionsIndex[account] + 1;
        decreasePositionsIndex[account] = index;
        bytes32 key = getRequestKey(account, index);

        decreasePositionRequests[key] = _request;
        decreasePositionRequestKeys.push(key);

        return (index, key);
    }

    function cancelDecreasePosition(bytes32 _key, address payable _executionFeeReceiver)
        public
        nonReentrant
        returns (bool)
    {
        StructsUtils.DecreasePositionRequest memory request = decreasePositionRequests[_key];
        // if the request was already executed or cancelled, return true so that the executeDecreasePositions loop will continue executing the next request
        if (request.account == address(0)) {
            return true;
        }

        if (!_validateCancellation(request.blockNumber, request.blockTime, request.account)) {
            return false;
        }

        delete decreasePositionRequests[_key];

        (bool success,) = _executionFeeReceiver.call{value: request.executionFee}("");
        require(success, "OM:f");

        emit CancelDecreasePosition(
            request.account,
            request._collateralToken,
            request.indexToken,
            request.sizeDelta,
            request.isLong,
            request.receiver,
            request.acceptablePrice,
            request.executionFee,
            block.number - request.blockNumber,
            block.timestamp - request.blockTime
        );

        return true;
    }

    function executeDecreasePositions(uint256 _endIndex, address payable _executionFeeReceiver)
        external
        override
        onlyPositionKeeper
        returns (uint256)
    {
        uint256 index = decreasePositionRequestKeysStart;
        uint256 length = decreasePositionRequestKeys.length;

        if (index >= length) {
            return index;
        }

        if (_endIndex > length) {
            _endIndex = length;
        }

        while (index < _endIndex) {
            bytes32 key = decreasePositionRequestKeys[index];

            // if the request was executed then delete the key from the array
            // if the request was not executed then break from the loop, this can happen if the
            // minimum number of blocks has not yet passed
            // an error could be thrown if the request is too old
            // in case an error was thrown, cancel the request
            try this.executeDecreasePosition(key, _executionFeeReceiver) returns (bool _wasExecuted) {
                if (!_wasExecuted) {
                    break;
                }
            } catch {
                // wrap this call in a try catch to prevent invalid cancels from blocking the loop
                try this.cancelDecreasePosition(key, _executionFeeReceiver) returns (bool _wasCancelled) {
                    if (!_wasCancelled) {
                        break;
                    }
                } catch {
                    continue;
                }
            }

            delete decreasePositionRequestKeys[index];
            index++;
        }

        decreasePositionRequestKeysStart = index;
        return index;
    }

    function executeDecreasePosition(bytes32 _key, address payable _executionFeeReceiver)
        public
        nonReentrant
        returns (bool)
    {
        StructsUtils.DecreasePositionRequest memory request = decreasePositionRequests[_key];
        // if the request was already executed or cancelled, return true so that the executeDecreasePositions loop will continue executing the next request
        if (request.account == address(0)) {
            return true;
        }

        if (!_validateExecution(request.blockNumber, request.blockTime, request.account)) {
            return false;
        }

        delete decreasePositionRequests[_key];

        uint256 amountOut = _decreasePosition(
            request.account,
            request._collateralToken,
            request.indexToken,
            request.sizeDelta,
            request.isLong,
            address(this),
            request.acceptablePrice
        );

        IERC20(request._collateralToken).safeTransfer(request.receiver, amountOut);

        (bool success,) = _executionFeeReceiver.call{value: request.executionFee}("");
        require(success, "OM:f");

        emit ExecuteDecreasePosition(
            request.account,
            request._collateralToken,
            request.indexToken,
            request.sizeDelta,
            request.isLong,
            request.receiver,
            request.acceptablePrice,
            request.executionFee,
            block.number - (request.blockNumber),
            block.timestamp - (request.blockTime)
        );
        return true;
    }

    function _validateExecution(uint256 _positionBlockNumber, uint256 _positionBlockTime, address _account)
        internal
        view
        returns (bool)
    {
        require(block.timestamp < _positionBlockTime + (maxTimeDelay), "OM:exp");

        return _validateExecutionOrCancellation(_positionBlockNumber, _positionBlockTime, _account);
    }

    function _validateCancellation(uint256 _positionBlockNumber, uint256 _positionBlockTime, address _account)
        internal
        view
        returns (bool)
    {
        return _validateExecutionOrCancellation(_positionBlockNumber, _positionBlockTime, _account);
    }

    function _validateExecutionOrCancellation(
        uint256 _positionBlockNumber,
        uint256 _positionBlockTime,
        address _account
    ) internal view returns (bool) {
        if (msg.sender == address(this) || isPositionKeeper[msg.sender]) {
            return _positionBlockNumber + minBlockDelayKeeper <= block.number;
        }
        require(msg.sender == _account, "OM:403");

        require(_positionBlockTime + minTimeDelayPublic <= block.timestamp, "OM:d");

        return true;
    }

    function getRequestKey(address account, uint256 index) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(account, index));
    }

    // If a user by-mistake sends token directly to the OM, we can use this function to refund to the user
    function retrieveStuckFunds(address _token, uint256 _amount) external onlyAdmin {
        require(_amount <= IERC20(_token).balanceOf(address(this)), "OM:amount");
        IERC20(_token).safeTransfer(admin, _amount);
    }

    function validatePositionOrderPrice(
        bool _triggerAboveThreshold,
        uint256 _triggerPrice,
        address _indexToken,
        bool /*_maximizePrice*/
    ) public view returns (uint256, bool) {
        uint256 currentPrice = IPriceFeed(pricefeed).getPriceOfToken(_indexToken);
        bool isPriceValid = _triggerAboveThreshold ? currentPrice > _triggerPrice : currentPrice < _triggerPrice;
        require(isPriceValid, "OM:pr");
        return (currentPrice, isPriceValid);
    }

    function createOrders(
        uint256 collateralDelta,
        address indexToken,
        uint256 sizeDelta,
        address collateralToken,
        bool isLong,
        uint256 _executionFee,
        uint256 limitPrice,
        uint256 tpPrice,
        uint256 slPrice
    ) external payable nonReentrant {
        require(!IVault(vault).ceaseTradingActivity(), "OM:0");
        require(IVault(vault).canBeIndexToken(indexToken), "OM:idx");
        require(msg.value == _executionFee, "OM:ef");

        // to make sure that you can either open a limit order or tp or sl order
        if (tpPrice != 0 || slPrice != 0) {
            require(limitPrice == 0, "OM:fail");
        }
        if (tpPrice != 0 && slPrice != 0) {
            require(_executionFee >= 2 * minExecutionFeeDecreaseLimitOrder, "OM:f");
        } else if (limitPrice != 0) {
            require(_executionFee >= minExecutionFeeIncreaseLimitOrder, "OM:f");
        } else {
            require(_executionFee >= minExecutionFeeDecreaseLimitOrder, "OM:f");
        }

        {
            uint256 _collateralDelta = collateralDelta;
            address _indexToken = indexToken;
            uint256 _sizeDelta = sizeDelta;
            address _collateralToken = collateralToken;
            bool _isLong = isLong;
            uint256 _limitPrice = limitPrice;
            uint256 _tpPrice = tpPrice;
            uint256 _slPrice = slPrice;

            if (limitPrice != 0) {
                IERC20(_collateralToken).safeTransferFrom(msg.sender, address(this), _collateralDelta);
                require(_collateralDelta >= minPurchaseUSDAmountLimitOrder, "OM:c");
                _createOrder(
                    msg.sender,
                    _collateralDelta,
                    _collateralToken,
                    _indexToken,
                    _sizeDelta,
                    _isLong,
                    _limitPrice,
                    !_isLong,
                    minExecutionFeeIncreaseLimitOrder,
                    true,
                    false
                );
            } else {
                if (tpPrice != 0) {
                    _createOrder(
                        msg.sender,
                        0,
                        _collateralToken,
                        _indexToken,
                        _sizeDelta,
                        _isLong,
                        _tpPrice,
                        _isLong,
                        minExecutionFeeDecreaseLimitOrder,
                        false,
                        false
                    );
                }
                if (slPrice != 0) {
                    _createOrder(
                        msg.sender,
                        0,
                        _collateralToken,
                        _indexToken,
                        _sizeDelta,
                        _isLong,
                        _slPrice,
                        !_isLong,
                        minExecutionFeeDecreaseLimitOrder,
                        false,
                        false
                    );
                }
            }
        }
    }

    function _createOrder(
        address _account,
        uint256 _collateralDelta,
        address _collateralToken,
        address _indexToken,
        uint256 _sizeDelta,
        bool _isLong,
        uint256 _triggerPrice,
        bool _triggerAboveThreshold,
        uint256 _executionFee,
        bool _isIncreaseOrder,
        bool _isMaxOrder
    ) private {
        {
            address account = _account;
            uint256 collateralDelta = _collateralDelta;
            address collateralToken = _collateralToken;
            address indexToken = _indexToken;
            uint256 sizeDelta = _sizeDelta;
            bool isLong = _isLong;
            uint256 triggerPrice = _triggerPrice;
            bool triggerAboveThreshold = _triggerAboveThreshold;
            uint256 executionFee = _executionFee;
            bool isIncreaseOrder = _isIncreaseOrder;
            bool isMaxOrder = _isMaxOrder;

            uint256 _orderIndex = ordersIndex[account];
            ordersIndex[account] = _orderIndex + (1);
            bytes32 orderKey = getOrderKey(account, _orderIndex);
            orders[orderKey] = StructsUtils.Order(
                account,
                collateralToken,
                indexToken,
                collateralDelta,
                sizeDelta,
                triggerPrice,
                executionFee,
                isLong,
                triggerAboveThreshold,
                isIncreaseOrder,
                isMaxOrder,
                _orderIndex,
                block.timestamp
            );
            EnumerableSet.add(orderKeys, orderKey);

            emitOrderCreateEvent(account, _orderIndex);
        }
    }

    function emitOrderCreateEvent(address _account, uint256 idx) internal {
        StructsUtils.Order memory order = orders[getOrderKey(_account, idx)];
        emit CreateOrder(
            _account,
            order.collateralToken,
            order.indexToken,
            idx,
            order.collateralDelta,
            order.sizeDelta,
            order.triggerPrice,
            order.executionFee,
            order.isLong,
            order.triggerAboveThreshold,
            order.isIncreaseOrder,
            order.isMaxOrder
        );
        emit UpdateOrder(
            _account,
            order.collateralToken,
            order.indexToken,
            idx,
            order.collateralDelta,
            order.sizeDelta,
            order.triggerPrice,
            order.isLong,
            order.triggerAboveThreshold,
            order.isIncreaseOrder,
            order.isMaxOrder
        );
    }

    function updateOrder(uint256 _orderIndex, uint256 _sizeDelta, uint256 _newCollateralAmount, uint256 _triggerPrice)
        external
        nonReentrant
    {
        StructsUtils.Order storage order = orders[getOrderKey(msg.sender, _orderIndex)];
        require(order.account != address(0), "OM:fail");

        uint256 oldCollateralAmount = order.collateralDelta;
        if (order.isIncreaseOrder) {
            require(_newCollateralAmount >= minPurchaseUSDAmountLimitOrder, "OM:c");
            bool increaseCollateral = _newCollateralAmount > oldCollateralAmount;
            uint256 collateralDelta = increaseCollateral
                ? (_newCollateralAmount - oldCollateralAmount)
                : (oldCollateralAmount - _newCollateralAmount);
            if (increaseCollateral) {
                IERC20(order.collateralToken).safeTransferFrom(msg.sender, address(this), collateralDelta);
            } else {
                IERC20(order.collateralToken).safeTransfer(order.account, collateralDelta);
            }
            order.collateralDelta = _newCollateralAmount;
        }

        order.triggerPrice = _triggerPrice;
        order.sizeDelta = _sizeDelta;

        emit UpdateOrder(
            msg.sender,
            order.collateralToken,
            order.indexToken,
            _orderIndex,
            order.collateralDelta,
            order.sizeDelta,
            order.triggerPrice,
            order.isLong,
            order.triggerAboveThreshold,
            order.isIncreaseOrder,
            order.isMaxOrder
        );
    }

    function cancelOrder(uint256 _orderIndex, address account) public nonReentrant {
        bytes32 orderKey = getOrderKey(account, _orderIndex);
        StructsUtils.Order memory order = orders[orderKey];

        if (order.isMaxOrder) {
            require(isOrderKeeper[msg.sender], "OM:403");
        } else {
            require(msg.sender == account || isOrderKeeper[msg.sender], "OM:403");
        }
        _cancelOrder(orderKey, _orderIndex, order, msg.sender);
    }

    function _cancelOrder(bytes32 orderKey, uint256 _orderIndex, StructsUtils.Order memory order, address feeReceiver)
        internal
    {
        require(order.account != address(0), "OM:fail");
        delete orders[orderKey];
        EnumerableSet.remove(orderKeys, orderKey);
        if (order.isIncreaseOrder) {
            IERC20(order.collateralToken).safeTransfer(order.account, order.collateralDelta);
        }
        if (!(order.isMaxOrder)) {
            (bool success,) = payable(feeReceiver).call{value: order.executionFee}("");
            require(success, "OM:f");
        }

        emit CancelOrder(
            order.account,
            order.collateralToken,
            order.indexToken,
            _orderIndex,
            order.collateralDelta,
            order.sizeDelta,
            order.triggerPrice,
            order.executionFee,
            order.isLong,
            order.triggerAboveThreshold,
            order.isIncreaseOrder,
            order.isMaxOrder
        );

        emit UpdateOrder(
            order.account,
            order.collateralToken,
            order.indexToken,
            _orderIndex,
            0,
            0,
            0,
            false,
            false,
            false,
            order.isMaxOrder
        );
    }

    function executeOrder(address _address, uint256 _orderIndex, address payable _feeReceiver)
        public
        override
        nonReentrant
        onlyOrderKeeper
    {
        bytes32 orderKey = getOrderKey(_address, _orderIndex);
        StructsUtils.Order memory order = orders[orderKey];
        require(order.account != address(0), "OM:fail");

        // increase long should use max pr
        // increase short should use min pr
        (uint256 currentPrice,) =
            validatePositionOrderPrice(order.triggerAboveThreshold, order.triggerPrice, order.indexToken, order.isLong);

        if (order.isIncreaseOrder) {
            IERC20(order.collateralToken).safeTransfer(vault, order.collateralDelta);
            IVault(vault).increasePosition(
                order.account, order.collateralToken, order.indexToken, order.sizeDelta, order.isLong
            );
            if (order.sizeDelta > 0) {
                uint256 tpPrice = IUtils(utils).getTPPrice(
                    order.sizeDelta,
                    order.isLong,
                    order.triggerPrice,
                    order.collateralDelta * maxProfitMultiplier,
                    order.collateralToken
                );
                _createOrder(
                    order.account,
                    0,
                    order.collateralToken,
                    order.indexToken,
                    order.sizeDelta,
                    order.isLong,
                    tpPrice,
                    order.isLong,
                    minExecutionFeeDecreaseLimitOrder,
                    false,
                    true
                );
            }
        } else {
            bool sufficientSizeExists = checkSufficientPositionExists(
                order.account, order.collateralToken, order.indexToken, order.isLong, order.sizeDelta
            );
            if (!sufficientSizeExists) {
                _cancelOrder(orderKey, _orderIndex, order, _feeReceiver);
                return;
            }
            uint256 amountOut = IVault(vault).decreasePosition(
                order.account, order.collateralToken, order.indexToken, order.sizeDelta, order.isLong, address(this)
            );
            IERC20(order.collateralToken).safeTransfer(order.account, amountOut);
        }

        delete orders[orderKey];
        EnumerableSet.remove(orderKeys, orderKey);

        // pay executor
        (bool success,) = _feeReceiver.call{value: order.executionFee}("");
        require(success, "OM:f");

        emit ExecuteOrder(
            order.account,
            order.collateralToken,
            order.indexToken,
            _orderIndex,
            order.collateralDelta,
            order.sizeDelta,
            order.triggerPrice,
            order.executionFee,
            currentPrice,
            order.isLong,
            order.triggerAboveThreshold,
            order.isIncreaseOrder
        );
        emit UpdateOrder(
            order.account,
            order.collateralToken,
            order.indexToken,
            _orderIndex,
            0,
            0,
            0,
            false,
            false,
            false,
            order.isMaxOrder
        );
    }

    function getOrderKey(address _account, uint256 index) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(_account, index));
    }

    function getAllOrders() public view returns (StructsUtils.Order[] memory) {
        uint256 orderLength = EnumerableSet.length(orderKeys);
        StructsUtils.Order[] memory openOrders = new StructsUtils.Order[](orderLength);
        for (uint256 i = 0; i < orderLength; i++) {
            openOrders[i] = (orders[EnumerableSet.at(orderKeys, i)]);
        }
        return openOrders;
    }

    function executeMultipleOrders(
        address[] calldata accountAddresses,
        uint256[] calldata orderIndices,
        address payable _feeReceiver
    ) public onlyOrderKeeper {
        uint256 length = accountAddresses.length;
        for (uint256 i = 0; i < length; i++) {
            try this.executeOrder(accountAddresses[i], orderIndices[i], _feeReceiver) {} catch {}
        }
    }

    function liquidateMultiplePositions(bytes32[] calldata keys, address payable _feeReceiver) public onlyLiquidator {
        uint256 length = keys.length;
        for (uint256 i = 0; i < length; i++) {
            try IVault(vault).liquidatePosition(keys[i], _feeReceiver) {} catch {}
        }
    }

    function checkSufficientPositionExists(
        address account,
        address collateralToken,
        address indexToken,
        bool isLong,
        uint256 sizeDelta
    ) private view returns (bool) {
        StructsUtils.Position memory position = IVault(vault).getPosition(account, collateralToken, indexToken, isLong);
        if (position.size < sizeDelta) {
            return false;
        }
        return true;
    }

    function getIncreasePositionCount() public view returns (uint256) {
        return increasePositionRequestKeys.length;
    }

    function getDecreasePositionCount() public view returns (uint256) {
        return decreasePositionRequestKeys.length;
    }

    function getIncreasePositionRequestFromIndex(uint256 index)
        external
        view
        returns (StructsUtils.IncreasePositionRequest memory)
    {
        require(index < increasePositionRequestKeys.length, "OM:fail");
        require(increasePositionRequestKeys[index] != bytes32(0), "OM:fail");

        return increasePositionRequests[increasePositionRequestKeys[index]];
    }
}
