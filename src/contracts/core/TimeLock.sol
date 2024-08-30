// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "./interfaces/ITimelock.sol";
import "../core/interfaces/IVault.sol";
import "../core/interfaces/IUtils.sol";
import "../core/interfaces/ILlpManager.sol";
import "./interfaces/IRewardRouter.sol";
import "./interfaces/IUSDL.sol";
import "../libraries/token/IERC20.sol";
import "./interfaces/IMintable.sol";
import "./interfaces/IHandler.sol";
import "./interfaces/IAdmin.sol";
import "./interfaces/ITimelockTarget.sol";
import "./interfaces/IYieldToken.sol";
import "../libraries/token/IBaseToken.sol";
import "../core/interfaces/IOrderManager.sol";
import "../libraries/token/SafeERC20.sol";

contract Timelock is ITimelock {
    using SafeERC20 for IERC20;

    uint256 public constant PRICE_PRECISION = 10 ** 30;
    uint256 public constant MAX_BUFFER = 5 days;
    uint256 public constant MAX_BORROWING_RATE_FACTOR = 200; // 0.02%
    uint256 public constant MAX_FUNDING_RATE_FACTOR = 200;
    uint256 public constant MAX_LEVERAGE_VALIDATION = 500000; // 50x

    uint256 public buffer;
    address public admin;

    address public mintReceiver;
    address public llpManager;

    mapping(bytes32 => uint256) public pendingActions;

    mapping(address => bool) public isHandler;
    mapping(address => bool) public isKeeper;

    event SignalPendingLemonXAction(bytes32 action);
    event SignalLemonXApprove(address token, address spender, uint256 amount, bytes32 action);
    event SignalLemonXWithdrawToken(address target, address token, address receiver, uint256 amount, bytes32 action);
    event SignalSetLemonXGov(address target, address gov, bytes32 action);
    event SignalSetLemonXHandler(address target, address handler, bool isActive, bytes32 action);
    event SignalSetLemonXPriceFeed(address vault, address priceFeed, bytes32 action);
    event SignalRedeemLemonXUsdl(address vault, address token, uint256 amount);
    event SignalLemonXVaultSetTokenConfig(
        address vault,
        address token,
        uint256 tokenDecimals,
        uint256 minProfitBps,
        bool isStable,
        bool canBeCollateralToken,
        bool canBeIndexToken,
        uint256 maxLeverage,
        uint256 maxOiImbalance
    );
    event ClearLemonXAction(bytes32 action);

    modifier onlyAdmin() {
        require(msg.sender == admin, "Timelock: admin forbidden");
        _;
    }

    modifier onlyHandlerAndAbove() {
        require(msg.sender == admin || isHandler[msg.sender], "Timelock: handler forbidden");
        _;
    }

    modifier onlyKeeperAndAbove() {
        require(msg.sender == admin || isHandler[msg.sender] || isKeeper[msg.sender], "Timelock: keeper forbidden");
        _;
    }

    modifier validAddress(address _addr) {
        require(_addr != address(0), "ZERO");
        require(_addr != 0x000000000000000000000000000000000000dEaD, "DEAD");
        _;
    }

    constructor(address _admin, uint256 _buffer, address _mintReceiver, address _llpManager) {
        require(_buffer <= MAX_BUFFER, "Timelock: invalid _buffer");
        admin = _admin;
        buffer = _buffer;
        mintReceiver = _mintReceiver;
        llpManager = _llpManager;
    }

    function setAdmin(address _admin) external override onlyAdmin validAddress(_admin) {
        admin = _admin;
    }

    function setExternalAdmin(address _target, address _admin) external onlyAdmin validAddress(_target) {
        require(_target != address(this), "Timelock: invalid _target");
        IAdmin(_target).setAdmin(_admin);
    }

    function setContractHandler(address _handler, bool _isActive) external onlyAdmin validAddress(_handler) {
        isHandler[_handler] = _isActive;
    }

    function setKeeper(address _keeper, bool _isActive) external onlyAdmin validAddress(_keeper) {
        isKeeper[_keeper] = _isActive;
    }

    function setBuffer(uint256 _buffer) external onlyAdmin {
        require(_buffer <= MAX_BUFFER, "Timelock: invalid _buffer");
        require(_buffer > buffer, "Timelock: buffer cannot be decreased");
        buffer = _buffer;
    }

    function setMaxLeverage(address _vault, uint256 _maxLeverage, address _token) external onlyAdmin {
        require(_maxLeverage > MAX_LEVERAGE_VALIDATION, "Timelock: invalid _maxLeverage");
        IVault(_vault).setMaxLeverage(_maxLeverage, _token);
    }

    function setBorrowingRate(
        address _vault,
        address token,
        uint256 _borrowingInterval,
        uint256 _borrowingRateFactor,
        uint256 _borrowingExponent
    ) external onlyKeeperAndAbove {
        require(_borrowingRateFactor < MAX_BORROWING_RATE_FACTOR, "Timelock: invalid _borrowingRateFactor");
        IVault(_vault).setBorrowingRate(token, _borrowingInterval, _borrowingRateFactor, _borrowingExponent);
    }

    function setFundingRate(
        address _vault,
        address token,
        uint256 _fundingInterval,
        uint256 _fundingRateFactor,
        uint256 _fundingExponent
    ) external onlyKeeperAndAbove {
        require(_fundingRateFactor < MAX_FUNDING_RATE_FACTOR, "Timelock: invalid _fundingRateFactor");
        IVault(_vault).setFundingRate(token, _fundingInterval, _fundingRateFactor, _fundingExponent);
    }

    function setTokenConfig(address _vault, address _token, uint256 _minProfitBps, uint256 _maxLeverage)
        external
        onlyKeeperAndAbove
    {
        require(_minProfitBps <= 500, "Timelock: invalid _minProfitBps");

        IVault vault = IVault(_vault);
        require(vault.whitelistedTokens(_token), "Timelock: token not yet whitelisted");

        uint256 tokenDecimals = vault.tokenDecimals(_token);
        bool isStable = vault.stableTokens(_token);
        bool canBeCollateralToken = vault.canBeCollateralToken(_token);
        bool canBeIndexToken = vault.canBeIndexToken(_token);

        IVault(_vault).setTokenConfig(
            _token, tokenDecimals, _minProfitBps, isStable, canBeCollateralToken, canBeIndexToken, _maxLeverage
        );
    }

    function updateUsdlSupply(uint256 usdlAmount) external onlyKeeperAndAbove {
        address usdl = ILlpManager(llpManager).usdl();
        uint256 balance = IERC20(usdl).balanceOf(llpManager);

        IUSDL(usdl).addVault(address(this));

        if (usdlAmount > balance) {
            uint256 mintAmount = usdlAmount - (balance);
            IUSDL(usdl).mint(llpManager, mintAmount);
        } else {
            uint256 burnAmount = balance - (usdlAmount);
            IUSDL(usdl).burn(llpManager, burnAmount);
        }

        IUSDL(usdl).removeVault(address(this));
    }

    function setGlpCooldownDuration(uint256 _cooldownDuration) external onlyAdmin {
        require(_cooldownDuration < 2 hours, "Timelock: invalid _cooldownDuration");
        ILlpManager(llpManager).setCooldownDuration(_cooldownDuration);
    }

    function setMaxGlobalLongSize(address _vault, address _token, uint256 _amount) external onlyAdmin {
        IVault(_vault).setMaxGlobalLongSize(_token, _amount);
    }

    function setMaxGlobalShortSize(address _vault, address _token, uint256 _amount) external onlyAdmin {
        IVault(_vault).setMaxGlobalShortSize(_token, _amount);
    }

    function removeAdmin(address _token, address _account) external onlyAdmin {
        IYieldToken(_token).removeAdmin(_account);
    }

    function setUtils(address _vault, IUtils _utils) external onlyAdmin {
        IVault(_vault).setUtils(address(_utils));
    }

    function setMaxGasPrice(address _vault, uint256 _maxGasPrice) external onlyAdmin {
        require(_maxGasPrice > 5000000000, "Invalid _maxGasPrice");
        IVault(_vault).setMaxGasPrice(_maxGasPrice);
    }

    function withdrawFees(address _vault, address _token, address _receiver) external onlyAdmin {
        IVault(_vault).withdrawFees(_token, _receiver);
    }

    function batchWithdrawFees(address _vault, address[] memory _tokens) external onlyKeeperAndAbove {
        for (uint256 i = 0; i < _tokens.length; i++) {
            IVault(_vault).withdrawFees(_tokens[i], admin);
        }
    }

    function setInPrivateLiquidationMode(address _vault, bool _inPrivateLiquidationMode) external onlyAdmin {
        IVault(_vault).setInPrivateLiquidationMode(_inPrivateLiquidationMode);
    }

    function setLiquidator(address _vault, address _liquidator, bool _isActive) external onlyAdmin {
        IVault(_vault).setLiquidator(_liquidator, _isActive);
    }

    function transferIn(address _sender, address _token, uint256 _amount) external onlyAdmin {
        IERC20(_token).safeTransferFrom(_sender, address(this), _amount);
    }

    function signalApprove(address _token, address _spender, uint256 _amount) external onlyAdmin {
        bytes32 action = keccak256(abi.encodePacked("approve", _token, _spender, _amount));
        _setPendingAction(action);
        emit SignalLemonXApprove(_token, _spender, _amount, action);
    }

    function approve(address _token, address _spender, uint256 _amount) external onlyAdmin {
        bytes32 action = keccak256(abi.encodePacked("approve", _token, _spender, _amount));
        _validateAction(action);
        _clearAction(action);
        IERC20(_token).safeApprove(_spender, _amount);
    }

    function signalWithdrawToken(address _target, address _token, address _receiver, uint256 _amount)
        external
        onlyAdmin
    {
        bytes32 action = keccak256(abi.encodePacked("withdrawToken", _target, _token, _receiver, _amount));
        _setPendingAction(action);
        emit SignalLemonXWithdrawToken(_target, _token, _receiver, _amount, action);
    }

    function withdrawToken(address _target, address _token, address _receiver, uint256 _amount) external onlyAdmin {
        bytes32 action = keccak256(abi.encodePacked("withdrawToken", _target, _token, _receiver, _amount));
        _validateAction(action);
        _clearAction(action);
        IBaseToken(_target).withdrawToken(_token, _receiver, _amount);
    }

    function signalSetGov(address _target, address _gov) external override onlyAdmin {
        bytes32 action = keccak256(abi.encodePacked("setGov", _target, _gov));
        _setPendingAction(action);
        emit SignalSetLemonXGov(_target, _gov, action);
    }

    function setGov(address _target, address _gov) external onlyAdmin {
        bytes32 action = keccak256(abi.encodePacked("setGov", _target, _gov));
        _validateAction(action);
        _clearAction(action);
        ITimelockTarget(_target).setGov(_gov);
    }

    function signalSetHandler(address _target, address _handler, bool _isActive) external onlyAdmin {
        bytes32 action = keccak256(abi.encodePacked("setHandler", _target, _handler, _isActive));
        _setPendingAction(action);
        emit SignalSetLemonXHandler(_target, _handler, _isActive, action);
    }

    function setHandler(address _target, address _handler, bool _isActive) external onlyAdmin {
        bytes32 action = keccak256(abi.encodePacked("setHandler", _target, _handler, _isActive));
        _validateAction(action);
        _clearAction(action);
        IHandlerTarget(_target).setHandler(_handler, _isActive);
    }

    function signalSetPriceFeed(address _vault, address _orderManager, address _utils, address _priceFeed)
        external
        onlyAdmin
    {
        bytes32 action = keccak256(abi.encodePacked("setPriceFeed", _vault, _orderManager, _utils, _priceFeed));
        _setPendingAction(action);
        emit SignalSetLemonXPriceFeed(_vault, _priceFeed, action);
    }

    function setPriceFeed(address _vault, address _orderManager, address _utils, address _priceFeed)
        external
        onlyAdmin
    {
        bytes32 action = keccak256(abi.encodePacked("setPriceFeed", _vault, _orderManager, _utils, _priceFeed));
        _validateAction(action);
        _clearAction(action);
        IVault(_vault).setPriceFeed(_priceFeed);
        IOrderManager(_orderManager).setPriceFeed(_priceFeed);
        IUtils(_utils).setPriceFeed(_priceFeed);
    }

    function signalRedeemUsdl(address _vault, address _token, uint256 _amount) external onlyAdmin {
        bytes32 action = keccak256(abi.encodePacked("redeemUsdl", _vault, _token, _amount));
        _setPendingAction(action);
        emit SignalRedeemLemonXUsdl(_vault, _token, _amount);
    }

    function redeemUsdl(address _vault, address _token, uint256 _amount) external onlyAdmin {
        bytes32 action = keccak256(abi.encodePacked("redeemUsdl", _vault, _token, _amount));
        _validateAction(action);
        _clearAction(action);

        address usdl = IVault(_vault).usdl();
        IVault(_vault).setManager(address(this), true);
        IUSDL(usdl).addVault(address(this));

        IUSDL(usdl).mint(address(this), _amount);
        IERC20(usdl).safeTransfer(address(_vault), _amount);

        IVault(_vault).sellUSDL(_token, mintReceiver);

        IVault(_vault).setManager(address(this), false);
        IUSDL(usdl).removeVault(address(this));
    }

    function signalVaultSetTokenConfig(
        address _vault,
        address _token,
        uint256 _tokenDecimals,
        uint256 _minProfitBps,
        bool _isStable,
        bool _canBeCollateralToken,
        bool _canBeIndexToken,
        uint256 _maxLeverage,
        uint256 _maxOiImbalance
    ) external onlyAdmin {
        bytes32 action = keccak256(
            abi.encodePacked(
                "vaultSetTokenConfig",
                _vault,
                _token,
                _tokenDecimals,
                _minProfitBps,
                _isStable,
                _canBeCollateralToken,
                _canBeIndexToken,
                _maxLeverage,
                _maxOiImbalance
            )
        );

        _setPendingAction(action);

        emit SignalLemonXVaultSetTokenConfig(
            _vault,
            _token,
            _tokenDecimals,
            _minProfitBps,
            _isStable,
            _canBeCollateralToken,
            _canBeIndexToken,
            _maxLeverage,
            _maxOiImbalance
        );
    }

    function vaultSetTokenConfig(
        address _vault,
        address _token,
        uint256 _tokenDecimals,
        uint256 _minProfitBps,
        bool _isStable,
        bool canBeCollateralToken,
        bool canBeIndexToken,
        uint256 _maxLeverage
    ) external onlyAdmin {
        bytes32 action = keccak256(
            abi.encodePacked(
                "vaultSetTokenConfig",
                _vault,
                _token,
                _tokenDecimals,
                _minProfitBps,
                _isStable,
                canBeCollateralToken,
                canBeIndexToken,
                _maxLeverage
            )
        );

        _validateAction(action);
        _clearAction(action);

        IVault(_vault).setTokenConfig(
            _token, _tokenDecimals, _minProfitBps, _isStable, canBeCollateralToken, canBeIndexToken, _maxLeverage
        );
    }

    function setCeaseTradingActivity(address _vault, bool _ceaseTradingActivity) external onlyAdmin {
        IVault(_vault).setCeaseTradingActivity(_ceaseTradingActivity);
    }

    function setCeaseLPActivity(address _vault, bool _ceaseLPActivity) external onlyAdmin {
        IVault(_vault).setCeaseLPActivity(_ceaseLPActivity);
    }

    function cancelAction(bytes32 _action) external onlyAdmin {
        _clearAction(_action);
    }

    function _setPendingAction(bytes32 _action) private {
        require(pendingActions[_action] == 0, "Timelock: action already signalled");
        pendingActions[_action] = block.timestamp + buffer;
        emit SignalPendingLemonXAction(_action);
    }

    function _validateAction(bytes32 _action) private view {
        require(pendingActions[_action] != 0, "Timelock: action not signalled");
        require(pendingActions[_action] < block.timestamp, "Timelock: action time not yet passed");
    }

    function _clearAction(bytes32 _action) private {
        require(pendingActions[_action] != 0, "Timelock: invalid _action");
        delete pendingActions[_action];
        emit ClearLemonXAction(_action);
    }
}
