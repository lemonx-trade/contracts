// SPDX-License-Identifier: MIT
import "../access/Governable.sol";

pragma solidity 0.8.19;

interface IOrderManager {
    function cancelOrder(uint256 _orderIndex, address account) external;
}

contract MultiCall is Governable {
    mapping(address => bool) public isWhitelisted;

    //Generic Functionality
    struct Call {
        address target;
        bytes callData;
    }

    constructor() Governable() {}

    function setWhitelisted(address target, bool value) external onlyGov {
        isWhitelisted[target] = value;
    }

    function isWhitelistedAddress(address target) external view returns (bool) {
        return isWhitelisted[target];
    }

    modifier onlyWhitelisted() {
        require(isWhitelisted[msg.sender], "MultiCall: caller is not whitelisted");
        _;
    }

    function aggregate(Call[] memory calls)
        external
        onlyWhitelisted
        returns (uint256 blockNumber, bytes[] memory returnData)
    {
        blockNumber = block.number;
        returnData = new bytes[](calls.length);
        for (uint256 i = 0; i < calls.length; i++) {
            (bool success, bytes memory data) = calls[i].target.call(calls[i].callData);
            require(success, "MultiCall: call failed");
            returnData[i] = data;
        }
    }

    //Cancel batch orders
    function cancelOrders(address orderManager, uint256[] calldata orderIndices, address[] calldata accounts)
        external
        onlyWhitelisted
    {
        for (uint256 i = 0; i < orderIndices.length; i++) {
            IOrderManager(orderManager).cancelOrder(orderIndices[i], accounts[i]);
        }
    }
}
