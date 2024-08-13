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

    event SignalPendingAction(bytes32 action);
    event SignalApprove(address token, address spender, uint256 amount, bytes32 action);
    event SignalWithdrawToken(address target, address token, address receiver, uint256 amount, bytes32 action);
    event SignalSetGov(address target, address gov, bytes32 action);
    event SignalSetHandler(address target, address handler, bool isActive, bytes32 action);
    event SignalSetPriceFeed(address vault, address priceFeed, bytes32 action);
    event SignalRedeemUsdl(address vault, address token, uint256 amount);
    event SignalVaultSetTokenConfig(
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
    event ClearAction(bytes32 action);
    event AddressChanged(uint256 configCode, address oldAddress, address newAddress);
    event ValueChanged(uint256 configCode, uint256 oldValue, uint256 newValue);
    event MapValueChanged(uint256 configCode, bytes32 encodedKey, bytes32 encodedValue);

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

    modifier isContract(address account) {
        require(account != address(0), "ZERO");
        require(account != 0x000000000000000000000000000000000000dEaD, "DEAD");
        uint256 size;
        assembly {
            size := extcodesize(account)
        }
        require(size > 0, "eoa");
        _;
    }

    constructor(address _admin, uint256 _buffer, address _mintReceiver, address _llpManager) {
        require(_buffer <= MAX_BUFFER, "Timelock: invalid _buffer");
        admin = _admin;
        buffer = _buffer;
        mintReceiver = _mintReceiver;
        llpManager = _llpManager;
    }
    //  L1 missing events
    //  L4 zero or dead address check

    function setAdmin(address _admin) external override onlyAdmin validAddress(_admin) {
        address oldAddress = admin;
        admin = _admin;
        emit AddressChanged(1, oldAddress, _admin); // 1 for admin
    }
    //  L4 zero or dead address check

    function setExternalAdmin(address _target, address _admin) external onlyAdmin validAddress(_admin) {
        require(_target != address(this), "Timelock: invalid _target");
        IAdmin(_target).setAdmin(_admin);
    }
    //  L1 missing events
    //  L4 zero or dead address check

    function setContractHandler(address _handler, bool _isActive) external onlyAdmin validAddress(_handler) {
        bool oldValue = isHandler[_handler];
        isHandler[_handler] = _isActive;
        emit MapValueChanged(1, bytes32(abi.encodePacked(oldValue)), bytes32(abi.encodePacked(_isActive))); // 3 for contract handler
    }
    //  L1 missing events
    //  L4 zero or dead address check

    function setKeeper(address _keeper, bool _isActive) external onlyAdmin validAddress(_keeper) {
        bool oldValue = isKeeper[_keeper];
        isKeeper[_keeper] = _isActive;
        emit MapValueChanged(2, bytes32(abi.encodePacked(oldValue)), bytes32(abi.encodePacked(_isActive))); // 1 for keeper
    }
    //  L1 missing events

    function setBuffer(uint256 _buffer) external onlyAdmin {
        require(_buffer <= MAX_BUFFER, "Timelock: invalid _buffer");
        require(_buffer > buffer, "Timelock: buffer cannot be decreased");
        uint256 oldValue = buffer;
        buffer = _buffer;
        emit ValueChanged(1, oldValue, _buffer); //1 for buffer
    }
    //  L1 missing events

    function setMaxLeverage(address _vault, uint256 _maxLeverage, address _token) external onlyAdmin {
        require(_maxLeverage > MAX_LEVERAGE_VALIDATION, "Timelock: invalid _maxLeverage");
        IVault(_vault).setMaxLeverage(_maxLeverage, _token);
        emit MapValueChanged(3, bytes32(abi.encodePacked(_token)), bytes32(abi.encodePacked(_maxLeverage))); // 3 for max leverage
    }
    //  L1 missing events

    function setBorrowingRate(
        address _vault,
        address token,
        uint256 _borrowingInterval,
        uint256 _borrowingRateFactor,
        uint256 _borrowingExponent
    ) external onlyKeeperAndAbove {
        require(_borrowingRateFactor < MAX_BORROWING_RATE_FACTOR, "Timelock: invalid _borrowingRateFactor");
        (uint256 oldBorrowingInterval, uint256 oldBorrowingRateFactor, uint256 oldBorrowingExponent) =
            IVault(_vault).borrowingRateFactor(token);
        IVault(_vault).setBorrowingRate(token, _borrowingInterval, _borrowingRateFactor, _borrowingExponent);
        emit ValueChanged(2, oldBorrowingInterval, _borrowingInterval); // 2 for borrowing interval
        emit ValueChanged(3, oldBorrowingRateFactor, _borrowingRateFactor); // 3 for borrowing rate factor
        emit ValueChanged(4, oldBorrowingExponent, _borrowingExponent); // 4 for borrowing exponent
    }
    //  L1 missing events

    function setFundingRate(
        address _vault,
        address token,
        uint256 _fundingInterval,
        uint256 _fundingRateFactor,
        uint256 _fundingExponent
    ) external onlyKeeperAndAbove {
        require(_fundingRateFactor < MAX_FUNDING_RATE_FACTOR, "Timelock: invalid _fundingRateFactor");
        (uint256 oldFundingInterval, uint256 oldFundingRateFactor, uint256 oldFundingExponent) =
            IVault(_vault).fundingRateFactor(token);
        IVault(_vault).setFundingRate(token, _fundingInterval, _fundingRateFactor, _fundingExponent);
        emit ValueChanged(5, oldFundingInterval, _fundingInterval); // 5 for funding interval
        emit ValueChanged(6, oldFundingRateFactor, _fundingRateFactor); // 6 for funding rate factor
        emit ValueChanged(7, oldFundingExponent, _fundingExponent); // 7 for funding exponent
    }
    //  L1 missing events

    function setTokenConfig(address _vault, address _token, uint256 _minProfitBps, uint256 _maxLeverage)
        external
        onlyKeeperAndAbove
    {
        require(_minProfitBps <= 500, "Timelock: invalid _minProfitBps");

        IVault vault = IVault(_vault);
        require(vault.whitelistedTokens(_token), "Timelock: token not yet whitelisted");

        uint256 oldTokenDecimals = vault.tokenDecimals(_token);
        bool oldIsStable = vault.stableTokens(_token);
        bool oldCanBeCollateralToken = vault.canBeCollateralToken(_token);
        bool oldCanBeIndexToken = vault.canBeIndexToken(_token);
        uint256 oldMaxLeverage = IVault(_vault).maxLeverage(_token);
        uint256 oldMinProfitBasisPoints = IVault(_vault).minProfitBasisPoints(_token);

        /* (
            uint256 oldTokenDecimals,
            uint256 oldMinProfitBps,
            bool oldIsStable,
            bool oldCanBeCollateralToken,
            bool oldCanBeIndexToken,
            uint256 oldMaxLeverage
        ) = vault.tokenConfig(_token); */

        IVault(_vault).setTokenConfig(
            _token,
            oldTokenDecimals,
            _minProfitBps,
            oldIsStable,
            oldCanBeCollateralToken,
            oldCanBeIndexToken,
            _maxLeverage
        );

        emit ValueChanged(8, oldMinProfitBasisPoints, _minProfitBps); // 8 for min profit bps
        emit ValueChanged(9, oldMaxLeverage, _maxLeverage); // 9 for max leverage
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
    //  L1 missing events

    function setMaxGlobalLongSize(address _vault, address _token, uint256 _amount) external onlyAdmin {
        IVault(_vault).setMaxGlobalLongSize(_token, _amount);
        emit MapValueChanged(4, bytes32(abi.encodePacked(_token)), bytes32(abi.encodePacked(_amount)));
    }
    //  L1 missing events

    function setMaxGlobalShortSize(address _vault, address _token, uint256 _amount) external onlyAdmin {
        IVault(_vault).setMaxGlobalShortSize(_token, _amount);
        emit MapValueChanged(5, bytes32(abi.encodePacked(_token)), bytes32(bytes32(abi.encodePacked(_amount))));
    }
    //  L1 missing events

    function removeAdmin(address _token, address _account) external onlyAdmin validAddress(_account) {
        IYieldToken(_token).removeAdmin(_account);
        emit MapValueChanged(6, bytes32(abi.encodePacked(_account)), bytes32(abi.encodePacked(false)));
    }
    //  L1 missing events

    function setUtils(address _vault, IUtils _utils) external onlyAdmin {
        address oldAddress = address(IVault(_vault).getUtilsAddress());
        IVault(_vault).setUtils(address(_utils));
        emit AddressChanged(2, oldAddress, address(_utils));
    }
    //  L1 missing events
    //  L4 zero or dead address check

    function setMaxGasPrice(address _vault, uint256 _maxGasPrice) external onlyAdmin isContract(_vault) {
        require(_maxGasPrice > 5000000000, "Invalid _maxGasPrice");
        uint256 oldValue = IVault(_vault).maxGasPrice();
        IVault(_vault).setMaxGasPrice(_maxGasPrice);
        emit ValueChanged(10, oldValue, _maxGasPrice);
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
    //  L4 zero or dead address check

    function setLiquidator(address _vault, address _liquidator, bool _isActive)
        external
        onlyAdmin
        validAddress(_liquidator)
    {
        IVault(_vault).setLiquidator(_liquidator, _isActive);
    }

    function transferIn(address _sender, address _token, uint256 _amount) external onlyAdmin {
        IERC20(_token).safeTransferFrom(_sender, address(this), _amount);
    }

    function signalApprove(address _token, address _spender, uint256 _amount) external onlyAdmin {
        bytes32 action = keccak256(abi.encodePacked("approve", _token, _spender, _amount));
        _setPendingAction(action);
        emit SignalApprove(_token, _spender, _amount, action);
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
        emit SignalWithdrawToken(_target, _token, _receiver, _amount, action);
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
        emit SignalSetGov(_target, _gov, action);
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
        emit SignalSetHandler(_target, _handler, _isActive, action);
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
        emit SignalSetPriceFeed(_vault, _priceFeed, action);
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
        emit SignalRedeemUsdl(_vault, _token, _amount);
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

        emit SignalVaultSetTokenConfig(
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
        emit SignalPendingAction(_action);
    }

    function _validateAction(bytes32 _action) private view {
        require(pendingActions[_action] != 0, "Timelock: action not signalled");
        require(pendingActions[_action] < block.timestamp, "Timelock: action time not yet passed");
    }

    function _clearAction(bytes32 _action) private {
        require(pendingActions[_action] != 0, "Timelock: invalid _action");
        delete pendingActions[_action];
        emit ClearAction(_action);
    }
}
