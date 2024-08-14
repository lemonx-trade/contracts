// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "./interfaces/IPriceFeed.sol";
import "../access/Governable.sol";
import "./interfaces/IOrderManager.sol";
import "./interfaces/IPriceEvents.sol";
import "pyth-sdk-solidity/IPyth.sol";
import "pyth-sdk-solidity/PythStructs.sol";
import "./interfaces/IRewardRouter.sol";

contract PriceFeed is IPriceFeed, Governable {
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
    uint256 public constant PRICE_PRECISION = 30;
    uint256 public constant SLIPPAGE_PRECISION = 1000000;

    mapping(address => bytes32) public tokenPriceIdMapping;
    mapping(address => TokenPrice) public tokenToPrice;
    address[] public supportedTokens;
    uint256 public maxAllowedDelta;
    IOrderManager public orderManager;
    IRewardRouter public rewardRouter;
    mapping(address => uint256) public slippage;

    event PriceSet(TokenPrice priceSet);
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

    modifier validAddress(address _addr) {
        require(_addr != address(0), "ZERO");
        require(_addr != 0x000000000000000000000000000000000000dEaD, "DEAD");
        _;
    }

    constructor(uint256 _maxAllowedDelay, address _updater, uint256 _maxAllowedDelta) {
        maxAllowedDelay = _maxAllowedDelay;
        updater[_updater] = true;
        maxAllowedDelta = _maxAllowedDelta;
    }

    modifier onlyUpdater() {
        require(updater[msg.sender], "PriceFeed: sender does not have entitlements to update price");
        _;
    }
    //  M2 check for isContract
    //  L1 missing events
    //  L4 zero or dead address check

    function setOrderManager(address _orderManager) external onlyGov isContract(_orderManager) {
        address oldAddress = address(orderManager);
        orderManager = IOrderManager(_orderManager);
        emit AddressChanged(abi.encodeWithSignature("setOrderManager(address)"), oldAddress, _orderManager);
    }
    // M2 check for isContract
    //  L1 missing events
    //  L4 zero or dead address check

    function setRewardRouter(address _rewardRouter) external onlyGov isContract(_rewardRouter) {
        address oldAddress = address(rewardRouter);
        rewardRouter = IRewardRouter(_rewardRouter);
        emit AddressChanged(abi.encodeWithSignature("setRewardRouter(address)"), oldAddress, _rewardRouter);
    }
    //  L1 missing events
    //  L4 zero or dead address check

    function setUpdater(address _updater) external onlyGov validAddress(_updater) {
        updater[_updater] = true;
        emit MapValueChanged(
            abi.encodeWithSignature("setUpdater(address)"),
            bytes32(abi.encodePacked(_updater)),
            bytes32(abi.encodePacked(true))
        );
    }
    //  L1 missing events
    //  L4 zero or dead address check

    function removeUpdater(address _updater) external onlyGov validAddress(_updater) {
        updater[_updater] = false;
        emit MapValueChanged(
            abi.encodeWithSignature("removeUpdater(address)"),
            bytes32(abi.encodePacked(_updater)),
            bytes32(abi.encodePacked(false))
        );
    }
    //  M3 missing for threshold - NOTE: Business logic
    //  L1 missing events

    function setMaxAllowedDelay(uint256 _maxAllowedDelay) external onlyGov {
        uint256 oldValue = maxAllowedDelay;
        maxAllowedDelay = _maxAllowedDelay;
        emit ValueChanged(abi.encodeWithSignature("setMaxAllowedDelay(uint256)"), oldValue, _maxAllowedDelay);
    }
    //  M3 missing for threshold - NOTE: Business logic
    //  L1 missing events

    function setMaxAllowedDelta(uint256 _maxAllowedDelta) external onlyGov {
        uint256 oldValue = maxAllowedDelta;
        maxAllowedDelta = _maxAllowedDelta;
        emit ValueChanged(abi.encodeWithSignature("setMaxAllowedDelta(uint256)"), oldValue, _maxAllowedDelta);
    }
    //  M3 missing for threshold

    function setSlippage(address _indexToken, uint256 _slippage) external onlyGov validAddress(_indexToken) {
        require(_slippage <= SLIPPAGE_PRECISION, "highSlip");
        slippage[_indexToken] = _slippage;
        emit MapValueChanged(
            abi.encodeWithSignature("setSlippage(address,uint256)"),
            bytes32(abi.encodePacked(_indexToken)),
            bytes32(abi.encodePacked(_slippage))
        );
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
        PriceArgs[] calldata _darkOraclePrices,
        uint256 _endIndexForIncreasePositions,
        uint256 _endIndexForDecreasePositions
    ) external payable onlyUpdater returns (uint256, uint256) {
        setPrices(_darkOraclePrices);
        return executePositions(_endIndexForIncreasePositions, _endIndexForDecreasePositions);
    }

    function setPricesAndExecuteOrders(
        PriceArgs[] calldata _darkOraclePrices,
        address[] calldata _accounts,
        uint256[] calldata _orderIndices,
        address payable _feeReceiver
    ) external payable onlyUpdater {
        setPrices(_darkOraclePrices);
        executeOrders(_accounts, _orderIndices, _feeReceiver);
    }

    function setPricesAndLiqudidate(
        PriceArgs[] calldata _darkOraclePrices,
        bytes32[] calldata _keys,
        address payable _feeReceiver
    ) external payable onlyUpdater {
        setPrices(_darkOraclePrices);
        liquidatePositions(_keys, _feeReceiver);
    }

    function setPricesAndExecuteLPRequests(
        PriceArgs[] calldata _darkOraclePrices,
        uint256 _endIndexForMintRequests,
        uint256 _endIndexForBurnRequests
    ) external payable onlyUpdater returns (uint256, uint256) {
        setPrices(_darkOraclePrices);
        return executeLPRequests(_endIndexForMintRequests, _endIndexForBurnRequests);
    }

    function _setPrice(address _tokenAddress, PriceArgs memory _darkOraclePrice) public onlyUpdater {
        validateData(_darkOraclePrice.publishTime);

        uint256 minPrice =
            (_darkOraclePrice.price * (SLIPPAGE_PRECISION - slippage[_tokenAddress])) / SLIPPAGE_PRECISION;
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

    function setPrices(PriceArgs[] calldata _darkOraclePrices) public onlyUpdater {
        uint256 alltokens = supportedTokens.length;
        for (uint256 i = 0; i < alltokens; i++) {
            address currToken = supportedTokens[i];
            _setPrice(currToken, _darkOraclePrices[i]);
        }
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

    function getMaxPriceOfToken(address _token) external view override returns (uint256) {
        TokenPrice memory price = tokenToPrice[_token];
        validateData(price.publishTime);
        uint256 maxPrice = (price.maxPrice * (SLIPPAGE_PRECISION + slippage[_token])) / SLIPPAGE_PRECISION;
        return getFinalPrice(maxPrice, price.maxPriceExpo);
    }

    function getPriceOfToken(address _token) external view override returns (uint256) {
        TokenPrice memory price = tokenToPrice[_token];
        validateData(price.publishTime);
        return getFinalPrice(price.maxPrice, price.maxPriceExpo);
    }

    function getMinPriceOfToken(address _token) external view override returns (uint256) {
        TokenPrice memory price = tokenToPrice[_token];
        validateData(price.publishTime);
        uint256 minPrice = (price.minPrice * (SLIPPAGE_PRECISION - slippage[_token])) / SLIPPAGE_PRECISION;
        return getFinalPrice(minPrice, price.minPriceExpo);
    }

    function getFinalPrice(uint256 price, int32 exponent) private pure returns (uint256) {
        uint256 adjustment = PRICE_PRECISION - uint32(-1 * exponent);
        return price * (10 ** adjustment);
    }

    function withdrawFunds(uint256 _amount, address payable _receiver) public onlyGov {
        require(address(this).balance >= _amount, "PriceFeed: requested amount exceeds contract balance");
        (bool sent,) = _receiver.call{value: _amount}("");
        require(sent, "PriceFeed: Failed to send Ether");
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
}
