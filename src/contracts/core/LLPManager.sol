// SPDX-License-Identifier: MIT

import "../libraries/token/IERC20.sol";
import "../libraries/utils/ReentrancyGuard.sol";
import "./interfaces/IMintable.sol";
import "./interfaces/IUSDL.sol";
import "./interfaces/IVault.sol";
import "./interfaces/ILlpManager.sol";
import "../access/Governable.sol";
import "../libraries/token/SafeERC20.sol";

pragma solidity 0.8.19;

contract LlpManager is ReentrancyGuard, Governable, ILlpManager {
    using SafeERC20 for IERC20;

    uint256 public constant PRICE_PRECISION = 10 ** 30;
    uint256 public constant USDL_DECIMALS = 18;
    uint256 public constant llp_PRECISION = 10 ** 18;
    uint256 public constant MAX_COOLDOWN_DURATION = 48 hours;
    uint256 public constant BASIS_POINTS_DIVISOR = 10000;

    IVault public override vault;
    IUtils public utils;
    address public override usdl;
    address public override llp;
    uint256 public maxPoolValue;

    uint256 public override cooldownDuration;
    mapping(address => uint256) public override lastAddedAt;
    mapping(address => bool) public whiteListedTokens;

    mapping(address => bool) public isHandler;

    event AddLiquidity(
        address account,
        address token,
        uint256 amount,
        uint256 aumInusdl,
        uint256 llpSupply,
        uint256 usdlAmount,
        uint256 mintAmount
    );

    event RemoveLiquidity(
        address account,
        address token,
        uint256 llpAmount,
        uint256 aumInusdl,
        uint256 llpSupply,
        uint256 usdlAmount,
        uint256 amountOut
    );

    event AddressChanged(bytes indexed funcSignature, address oldAddress, address newAddress);
    event ValueChanged(bytes indexed funcSignature, uint256 oldValue, uint256 newValue);
    event MapValueChanged(bytes indexed funcSignature, bytes32 encodedKey, bytes32 encodedValue);

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

    constructor(
        address _vault,
        address _utils,
        address _usdl,
        address _llp,
        uint256 _cooldownDuration,
        uint256 _maxPoolValue
    ) {
        gov = msg.sender;
        vault = IVault(_vault);
        utils = IUtils(_utils);
        usdl = _usdl;
        llp = _llp;
        cooldownDuration = _cooldownDuration;
        maxPoolValue = _maxPoolValue;
    }
    //  M2 check for isContract
    //  L1 missing events

    function setUtils(address _utils) external onlyGov isContract(_utils) {
        address old_address = address(utils);
        utils = IUtils(_utils);
        emit AddressChanged(abi.encodeWithSignature("setUtils(address)"), old_address, _utils);
    }
    //  L1 missing events

    function setHandler(address _handler, bool _isActive) external onlyGov {
        isHandler[_handler] = _isActive;
        emit MapValueChanged(
            abi.encodeWithSignature("setHandler(address)"),
            bytes32(abi.encodePacked(_handler)),
            bytes32(abi.encodePacked(_isActive))
        );
    }
    //  L1 missing events

    function whiteListToken(address token) public onlyGov {
        whiteListedTokens[token] = true;
        emit MapValueChanged(
            abi.encodeWithSignature("whiteListToken(address)"),
            bytes32(abi.encodePacked(token)),
            bytes32(abi.encodePacked(true))
        );
    }
    //  L1 missing events

    function removeFromWhiteListToken(address token) public onlyGov {
        whiteListedTokens[token] = false;
        emit MapValueChanged(
            abi.encodeWithSignature("removeFromWhiteListToken(address)"),
            bytes32(abi.encodePacked(token)),
            bytes32(abi.encodePacked(false))
        );
    }
    //  L1 missing events
    //  M3 Missing threshold - NOTE: Business logic  Can't be a predetermined threshold

    function setMaxPoolValue(uint256 _maxPoolValue) public onlyGov {
        uint256 oldValue = maxPoolValue;
        maxPoolValue = _maxPoolValue;
        emit ValueChanged(abi.encodeWithSignature("setMaxPoolValue(uint256)"), oldValue, _maxPoolValue);
    }
    //  L1 missing events

    function setCooldownDuration(uint256 _cooldownDuration) external override onlyGov {
        require(_cooldownDuration <= MAX_COOLDOWN_DURATION, "LlpManager: invalid _cooldownDuration");
        uint256 oldValue = cooldownDuration;
        cooldownDuration = _cooldownDuration;
        emit ValueChanged(abi.encodeWithSignature("setCooldownDuration(uint256)"), oldValue, _cooldownDuration);
    }
    //  M2 check for isContract
    //  L1 missing events

    function setVault(address _vault) external onlyGov isContract(_vault) {
        address oldValue = address(vault);
        vault = IVault(_vault);
        emit AddressChanged(abi.encodeWithSignature("setVault(address)"), oldValue, _vault);
    }
    //  M2 check for isContract
    //  L1 missing events

    function setUsdl(address _usdl) external onlyGov isContract(_usdl) {
        address oldValue = usdl;
        usdl = _usdl;
        emit AddressChanged(abi.encodeWithSignature("setUsdl(address)"), oldValue, _usdl);
    }
    //  M2 check for isContract
    //  L1 missing events

    function setLlp(address _llp) external onlyGov isContract(_llp) {
        address oldAddress = _llp;
        llp = _llp;
        emit AddressChanged(abi.encodeWithSignature("setLlp(address)"), oldAddress, _llp);
    }

    function addLiquidityForAccount(
        address _fundingAccount,
        address _account,
        address _token,
        uint256 _amount,
        uint256 _minusdl,
        uint256 _minllp
    ) external override nonReentrant returns (uint256) {
        _validateLPActivity();
        _validateHandler();
        _validateToken(_token);
        return _addLiquidity(_fundingAccount, _account, _token, _amount, _minusdl, _minllp);
    }

    function _validateLPActivity() internal view {
        require(!vault.ceaseLPActivity(), "LLPManager: LP activity ceased!");
    }

    function removeLiquidityForAccount(
        address _account,
        address _tokenOut,
        uint256 _llpAmount,
        uint256 _minOut,
        address _receiver
    ) external override nonReentrant returns (uint256) {
        _validateLPActivity();
        _validateHandler();
        _validateToken(_tokenOut);
        return _removeLiquidity(_account, _tokenOut, _llpAmount, _minOut, _receiver);
    }

    function getPrice(bool _maximise) external view returns (uint256) {
        uint256 aum = utils.getAum(_maximise);
        uint256 supply = IERC20(llp).totalSupply();
        return (aum * llp_PRECISION) / supply;
    }

    function getAums() public view returns (uint256[] memory) {
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = utils.getAum(true);
        amounts[1] = utils.getAum(false);
        return amounts;
    }

    function _addLiquidity(
        address _fundingAccount,
        address _account,
        address _token,
        uint256 _amount,
        uint256 _minusdl, //amount in usdl token order of 18
        uint256 _minllp //amount in llp token order of 18
    ) private returns (uint256) {
        require(_amount > 0, "LlpManager: invalid _amount");

        // calculate aum before buyusdl
        uint256 aumInusdl = utils.getAumInUsdl(true);
        uint256 llpSupply = IERC20(llp).totalSupply();

        IERC20(_token).safeTransferFrom(_fundingAccount, address(vault), _amount);
        uint256 usdlAmount = vault.buyUSDL(_token, address(this));
        require(usdlAmount >= _minusdl, "LlpManager: insufficient usdl output");

        uint256 mintAmount = aumInusdl == 0 ? usdlAmount : (usdlAmount * (llpSupply)) / (aumInusdl);
        require(mintAmount >= _minllp, "LlpManager: insufficient llp output");
        require(aumInusdl + usdlAmount < maxPoolValue, "LLPManager: Max Pool value exceeded");
        IMintable(llp).mint(_account, mintAmount);

        lastAddedAt[_account] = block.timestamp;

        emit AddLiquidity(_account, _token, _amount, aumInusdl, llpSupply, usdlAmount, mintAmount);
        return mintAmount;
    }

    function _removeLiquidity(
        address _account,
        address _tokenOut,
        uint256 _llpAmount,
        uint256 _minOut,
        address _receiver
    ) private returns (uint256) {
        require(_llpAmount > 0, "LlpManager: invalid _llpAmount");
        require(
            lastAddedAt[_account] + (cooldownDuration) <= block.timestamp,
            "LlpManager: cooldown duration not yet passed"
        );

        // calculate aum before sellusdl
        uint256 aumInusdl = utils.getAumInUsdl(false);
        require(aumInusdl > 0, "LM: Cannot remove liquidity");
        uint256 llpSupply = IERC20(llp).totalSupply();

        uint256 usdlAmount = (_llpAmount * (aumInusdl)) / (llpSupply);
        uint256 usdlBalance = IERC20(usdl).balanceOf(address(this));
        if (usdlAmount > usdlBalance) {
            IUSDL(usdl).mint(address(this), usdlAmount - (usdlBalance));
        }

        IMintable(llp).burn(_account, _llpAmount);

        IERC20(usdl).safeTransfer(address(vault), usdlAmount);
        uint256 amountOut = vault.sellUSDL(_tokenOut, _receiver);
        require(amountOut >= _minOut, "LlpManager: insufficient output");

        emit RemoveLiquidity(_account, _tokenOut, _llpAmount, aumInusdl, llpSupply, usdlAmount, amountOut);

        return amountOut;
    }

    function _validateHandler() private view {
        require(isHandler[msg.sender], "LlpManager: forbidden");
    }

    function _validateToken(address token) private view {
        require(whiteListedTokens[token], "LlpManager: Token not whiteListed.");
    }
}
