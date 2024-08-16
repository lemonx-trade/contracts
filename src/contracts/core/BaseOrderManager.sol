// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "../libraries/token/SafeERC20.sol";
import "../libraries/token/IERC20.sol";
import "./interfaces/IVault.sol";
import "./interfaces/IUtils.sol";
import "./interfaces/ITimeLock.sol";
import "../access/Governable.sol";
import "../libraries/utils/ReentrancyGuard.sol";
import "./interfaces/IPriceFeed.sol";
import "../libraries/utils/Structs.sol";

contract BaseOrderManager {
    using SafeERC20 for IERC20;

    address public admin;
    address public vault;
    address public utils;
    address public pricefeed;

    uint256 public constant BASIS_POINTS_DIVISOR = 10000;
    uint256 public increasePositionBufferBps = 100;
    mapping(address => uint256) public feeReserves;
    uint256 public depositFee;

    event LeverageDecreased(uint256 collateralDelta, uint256 prevLeverage, uint256 nextLeverage);
    event WithdrawFees(address token, address receiver, uint256 amount);

    modifier onlyAdmin() {
        require(msg.sender == admin, "BM:403");
        _;
    }

    modifier validAddress(address _addr) {
        require(_addr != address(0), "ZERO");
        require(_addr != 0x000000000000000000000000000000000000dEaD, "DEAD");
        _;
    }

    constructor(address _vault, address _utils, address _pricefeed, uint256 _depositFee) {
        vault = _vault;
        utils = _utils;
        pricefeed = _pricefeed;
        admin = msg.sender;
        depositFee = _depositFee;
    }

    function setAdmin(address _admin) external onlyAdmin validAddress(_admin) {
        admin = _admin;
    }

    function setVault(address _vault) external onlyAdmin validAddress(_vault) {
        vault = _vault;
    }

    function setUtils(address _utils) external onlyAdmin validAddress(_utils) {
        utils = _utils;
    }

    function setDepositFee(uint256 _fee) external onlyAdmin {
        depositFee = _fee;
    }

    function _increasePosition(
        address _account,
        address _collateralToken,
        address _indexToken,
        uint256 _sizeDelta,
        bool _isLong,
        uint256 acceptablePrice
    ) internal {
        uint256 markPrice = _isLong
            ? IPriceFeed(pricefeed).getMaxPriceOfToken(_indexToken)
            : IPriceFeed(pricefeed).getMinPriceOfToken(_indexToken);
        if (_isLong) {
            require(markPrice <= acceptablePrice, "BM:mp");
        } else {
            require(markPrice >= acceptablePrice, "BM:mp");
        }

        IVault(vault).increasePosition(_account, _collateralToken, _indexToken, _sizeDelta, _isLong);
    }

    function _decreasePosition(
        address _account,
        address _collateralToken,
        address _indexToken,
        uint256 _sizeDelta,
        bool _isLong,
        address _receiver,
        uint256 _price
    ) internal returns (uint256) {
        uint256 markPrice = _isLong
            ? IPriceFeed(pricefeed).getMinPriceOfToken(_indexToken)
            : IPriceFeed(pricefeed).getMaxPriceOfToken(_indexToken);
        if (_isLong) {
            require(markPrice >= _price, "BM:mp");
        } else {
            require(markPrice <= _price, "BM:mp");
        }
        return IVault(vault).decreasePosition(_account, _collateralToken, _indexToken, _sizeDelta, _isLong, _receiver);
    }

    function shouldDeductFee(
        address _account,
        address collateralToken,
        uint256 _amountIn,
        address _indexToken,
        bool _isLong,
        uint256 _sizeDelta,
        uint256 _increasePositionBufferBps
    ) private returns (bool) {
        // if the position size is not increasing, this is a collateral deposit
        if (_sizeDelta == 0) {
            return true;
        }

        StructsUtils.Position memory position =
            IVault(vault).getPosition(_account, collateralToken, _indexToken, _isLong);
        uint256 size = position.size;
        uint256 collateral = position.collateral;

        // if there is no existing position, do not charge a fee
        if (size == 0) {
            return false;
        }

        uint256 nextSize = size + (_sizeDelta);
        uint256 collateralDelta = IUtils(utils).tokenToUsdMin(collateralToken, _amountIn);
        uint256 nextCollateral = collateral + (collateralDelta);

        uint256 prevLeverage = (size * (BASIS_POINTS_DIVISOR)) / (collateral);
        // allow for a maximum of a increasePositionBufferBps decrease since there might be some swap fees taken from the collateral
        uint256 nextLeverage = (nextSize * (BASIS_POINTS_DIVISOR + _increasePositionBufferBps)) / (nextCollateral);
        if (nextLeverage < prevLeverage) {
            emit LeverageDecreased(collateralDelta, prevLeverage, nextLeverage);
            return true;
        }

        return false;
    }

    function withdrawFees(address _token, address _receiver) external onlyAdmin {
        uint256 amount = feeReserves[_token];
        if (amount == 0) {
            return;
        }

        feeReserves[_token] = 0;
        IERC20(_token).safeTransfer(_receiver, amount);
        emit WithdrawFees(_token, _receiver, amount);
    }

    function _collectFees(
        address _account,
        address collateralToken,
        uint256 _amountIn,
        address _indexToken,
        bool _isLong,
        uint256 _sizeDelta
    ) internal returns (uint256) {
        if (
            shouldDeductFee(
                _account, collateralToken, _amountIn, _indexToken, _isLong, _sizeDelta, increasePositionBufferBps
            )
        ) {
            uint256 afterFeeAmount = (_amountIn * (BASIS_POINTS_DIVISOR - (depositFee))) / (BASIS_POINTS_DIVISOR);
            uint256 feeAmount = _amountIn - (afterFeeAmount);
            feeReserves[collateralToken] = feeReserves[collateralToken] + (feeAmount);
            return afterFeeAmount;
        }

        return _amountIn;
    }
}
