// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "./interfaces/IPriceFeed.sol";
import "../access/Governable.sol";
import "./interfaces/IOrderManager.sol";
import "./interfaces/IRewardRouter.sol";
import "./interfaces/IPriceEvents.sol";
import "pyth-sdk-solidity/IPyth.sol";
import "pyth-sdk-solidity/PythStructs.sol";

//send 0s if dark oracle prices aren't fetched for specific tokens
//emit events to log that dark oracle price wasn't fetched for certain tokens
contract PythPriceFeed is IPriceFeed, Governable {
    struct PriceArgs {
        uint256 price;
        int32 expo;
        uint256 publishTime;
    }

    struct TokenPrice {
        uint256 maxPrice;
        uint256 minPrice;
        int32 maxPriceExpo;
        int32 minPriceExpo;
        uint256 publishTime;
    }

    uint256 public maxAllowedDelay;
    mapping(address => bool) public updater;
    address public pythContract;
    uint256 public constant PRICE_PRECISION = 30;
    uint256 public constant BASIS_POINTS_DIVISOR = 10000;

    mapping(address => bytes32) public tokenPriceIdMapping;
    mapping(address => TokenPrice) public tokenToPrice;
    address[] public supportedTokens;
    uint256 public maxAllowedDelta;
    IOrderManager public orderManager;
    IRewardRouter public rewardRouter;

    event PriceSet(TokenPrice priceSet);
    event NoDarkOraclePrice(address token, uint256 time);
    event PythPricesDelayed(address token, uint256 currentTime, uint256 priceTime);

    constructor(uint256 _maxAllowedDelay, address _pythContract, address _updater, uint256 _maxAllowedDelta) {
        maxAllowedDelay = _maxAllowedDelay;
        pythContract = _pythContract;
        updater[_updater] = true;
        maxAllowedDelta = _maxAllowedDelta;
    }

    modifier onlyUpdater() {
        require(updater[msg.sender], "PriceFeed: sender does not have entitlements to update price");
        _;
    }
    // TODO: M2 check for isContract
    // TODO: L1 missing events

    function setOrderManager(address _orderManager) external onlyGov {
        orderManager = IOrderManager(_orderManager);
    }
    // TODO: M2 check for isContract
    // TODO: L1 missing events

    function setRewardRouter(address _rewardRouter) external onlyGov {
        rewardRouter = IRewardRouter(_rewardRouter);
    }

    function setUpdater(address _updater) external onlyGov {
        updater[_updater] = true;
    }

    function removeUpdater(address _updater) external onlyGov {
        updater[_updater] = false;
    }
    // TODO: M2 check for isContract
    // TODO: L1 missing events

    function setPythContract(address _pythContract) external onlyGov {
        pythContract = _pythContract;
    }
    // TODO: L1 missing events

    function setMaxAllowedDelay(uint256 _maxAllowedDelay) external onlyGov {
        maxAllowedDelay = _maxAllowedDelay;
    }
    // TODO: L1 missing events

    function setMaxAllowedDelta(uint256 _maxAllowedDelta) external onlyGov {
        maxAllowedDelta = _maxAllowedDelta;
    }

    function updateTokenIdMapping(address _token, bytes32 _priceId) external onlyGov {
        if (tokenPriceIdMapping[_token] != bytes32(0)) {
            tokenPriceIdMapping[_token] = _priceId;
        } else {
            tokenPriceIdMapping[_token] = _priceId;
            supportedTokens.push(_token);
        }
    }

    function validateData(uint256 _publishTime) internal view {
        require(_publishTime + maxAllowedDelay > block.timestamp, "PriceFeed: current price data not available!");
    }

    function setPricesAndExecute(
        bytes[] calldata _priceUpdateData,
        PriceArgs[] calldata _darkOraclePrices,
        uint256 _endIndexForIncreasePositions,
        uint256 _endIndexForDecreasePositions
    ) external payable onlyUpdater returns (uint256, uint256) {
        setPrices(_priceUpdateData, _darkOraclePrices);
        return executePositions(_endIndexForIncreasePositions, _endIndexForDecreasePositions);
    }

    function setPricesAndExecuteOrders(
        bytes[] calldata _priceUpdateData,
        PriceArgs[] calldata _darkOraclePrices,
        address[] calldata _accounts,
        uint256[] calldata _orderIndices,
        address payable _feeReceiver
    ) external payable onlyUpdater {
        setPrices(_priceUpdateData, _darkOraclePrices);
        executeOrders(_accounts, _orderIndices, _feeReceiver);
    }

    function setPricesAndLiqudidate(
        bytes[] calldata _priceUpdateData,
        PriceArgs[] calldata _darkOraclePrices,
        bytes32[] calldata _keys,
        address payable _feeReceiver
    ) external payable onlyUpdater {
        setPrices(_priceUpdateData, _darkOraclePrices);
        liquidatePositions(_keys, _feeReceiver);
    }

    function setPricesAndExecuteLPRequests(
        bytes[] calldata _priceUpdateData,
        PriceArgs[] calldata _darkOraclePrices,
        uint256 _endIndexForMintRequests,
        uint256 _endIndexForBurnRequests
    ) external payable onlyUpdater returns (uint256, uint256) {
        setPrices(_priceUpdateData, _darkOraclePrices);
        return executeLPRequests(_endIndexForMintRequests, _endIndexForBurnRequests);
    }

    function _setPrice(address _tokenAddress, PriceArgs memory _darkOraclePrice) public onlyUpdater {
        validateData(_darkOraclePrice.publishTime);
        TokenPrice memory priceObject = TokenPrice(
            _darkOraclePrice.price,
            _darkOraclePrice.price,
            _darkOraclePrice.expo,
            _darkOraclePrice.expo,
            _darkOraclePrice.publishTime
        );
        tokenToPrice[_tokenAddress] = priceObject;
        emit PriceSet(priceObject);
    }

    function setPrices(bytes[] calldata _priceUpdateData, PriceArgs[] calldata _darkOraclePrices)
        public
        payable
        onlyUpdater
    {
        uint256 numPriceIds = supportedTokens.length;
        // compare with pyth and set
        if (_priceUpdateData.length > 0) {
            uint256 fee = IPyth(pythContract).getUpdateFee(_priceUpdateData);
            IPyth(pythContract).updatePriceFeeds{value: fee}(_priceUpdateData);
        }
        for (uint256 i = 0; i < numPriceIds; i++) {
            address currToken = supportedTokens[i];
            bytes32 currPriceId = tokenPriceIdMapping[currToken];
            PythStructs.Price memory pythPrice = IPyth(pythContract).getPriceNoOlderThan(currPriceId, maxAllowedDelay);
            compareAndSetPrice(currToken, pythPrice, _darkOraclePrices[i]);
        }
    }

    function compareAndSetPrice(
        address _tokenAddress,
        PythStructs.Price memory _pythPrice,
        PriceArgs memory _darkOraclePrice
    ) internal {
        uint256 pythPrice = getFinalPrice(uint64(_pythPrice.price), _pythPrice.expo);
        uint256 darkOraclePrice = getFinalPrice(_darkOraclePrice.price, _darkOraclePrice.expo);

        if (_darkOraclePrice.price == 0) {
            TokenPrice memory tokenPrice = TokenPrice(
                uint64(_pythPrice.price),
                uint64(_pythPrice.price),
                _pythPrice.expo,
                _pythPrice.expo,
                _pythPrice.publishTime
            );
            tokenToPrice[_tokenAddress] = tokenPrice;
            emit PriceSet(tokenPrice);
            emit NoDarkOraclePrice(_tokenAddress, block.timestamp);
        } else if (allowedDelta(pythPrice, darkOraclePrice)) {
            _setPrice(_tokenAddress, _darkOraclePrice);
        } else {
            validateData(_pythPrice.publishTime);
            TokenPrice memory priceObject = TokenPrice(
                pythPrice > darkOraclePrice ? uint64(_pythPrice.price) : _darkOraclePrice.price,
                pythPrice < darkOraclePrice ? uint64(_pythPrice.price) : _darkOraclePrice.price,
                pythPrice > darkOraclePrice ? _pythPrice.expo : _darkOraclePrice.expo,
                pythPrice < darkOraclePrice ? _pythPrice.expo : _darkOraclePrice.expo,
                _darkOraclePrice.publishTime
            );
            tokenToPrice[_tokenAddress] = priceObject;
            emit PriceSet(priceObject);
        }
    }

    function allowedDelta(uint256 _a, uint256 _b) public view returns (bool) {
        uint256 _allowedDelta = (_a * maxAllowedDelta) / BASIS_POINTS_DIVISOR;
        return (_a >= _b) ? (_a - _b <= _allowedDelta) : (_b - _a <= _allowedDelta);
    }

    function executePositions(uint256 _endIndexForIncreasePositions, uint256 _endIndexForDecreasePositions)
        public
        onlyUpdater
        returns (uint256, uint256)
    {
        uint256 increaseNextStart =
            orderManager.executeIncreasePositions(_endIndexForIncreasePositions, payable(msg.sender));
        uint256 decreaseNextStart =
            orderManager.executeDecreasePositions(_endIndexForDecreasePositions, payable(msg.sender));
        return (increaseNextStart, decreaseNextStart);
    }

    function executeOrders(address[] calldata _accounts, uint256[] calldata _orderIndices, address payable _feeReceiver)
        public
        onlyUpdater
    {
        orderManager.executeMultipleOrders(_accounts, _orderIndices, _feeReceiver);
    }

    function liquidatePositions(bytes32[] calldata _keys, address payable _feeReceiver) public onlyUpdater {
        orderManager.liquidateMultiplePositions(_keys, _feeReceiver);
    }

    function executeLPRequests(uint256 _endIndexForMintRequests, uint256 _endIndexForBurnRequests)
        public
        onlyUpdater
        returns (uint256, uint256)
    {
        uint256 mintNextStart = rewardRouter.executeMintRequests(_endIndexForMintRequests, payable(msg.sender));
        uint256 burnNextStart = rewardRouter.executeBurnRequests(_endIndexForBurnRequests, payable(msg.sender));
        return (mintNextStart, burnNextStart);
    }

    function getMaxPriceOfToken(address _token) external view override returns (uint256) {
        TokenPrice memory price = tokenToPrice[_token];
        validateData(price.publishTime);
        return getFinalPrice(price.maxPrice, price.maxPriceExpo);
    }

    function getMinPriceOfToken(address _token) external view override returns (uint256) {
        TokenPrice memory price = tokenToPrice[_token];
        validateData(price.publishTime);
        return getFinalPrice(price.minPrice, price.minPriceExpo);
    }

    function getFinalPrice(uint256 price, int32 exponent) private pure returns (uint256) {
        uint256 adjustment = PRICE_PRECISION - uint32(-1 * exponent);
        return price * (10 ** adjustment);
    }

    function withdrawFunds(uint256 _amount, address payable _receiver) public onlyGov {
        require(address(this).balance >= _amount, "PriceFeed: requested amount exceeds contract balance");
        (bool sent, bytes memory data) = _receiver.call{value: _amount}("");
        require(sent, "PriceFeed: Failed to send Ether");
    }

    function getPriceOfToken(address _token) external view override returns (uint256) {
        TokenPrice memory price = tokenToPrice[_token];
        validateData(price.publishTime);
        return getFinalPrice(price.maxPrice, price.maxPriceExpo);
    }
}
