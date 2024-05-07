// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "./../../libraries/utils/Structs.sol";

interface IOrderManager {
    function increasePositionRequestKeysStart() external view returns (uint256);

    function decreasePositionRequestKeysStart() external view returns (uint256);

    function executeIncreasePositions(uint256 _count, address payable _executionFeeReceiver)
        external
        returns (uint256);

    function executeDecreasePositions(uint256 _count, address payable _executionFeeReceiver)
        external
        returns (uint256);

    function executeOrder(address, uint256, address payable) external;

    function setOrderKeeper(address _account, bool _isActive) external;

    function setPriceFeed(address _priceFeed) external;

    function executeMultipleOrders(
        address[] calldata accountAddresses,
        uint256[] calldata orderIndices,
        address payable _feeReceiver
    ) external;

    function liquidateMultiplePositions(bytes32[] calldata keys, address payable _feeReceiver) external;

    function getIncreasePositionCount() external view returns (uint256);

    function getDecreasePositionCount() external view returns (uint256);
}
