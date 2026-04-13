// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @dev execution shell that makes msg.sender behave like Safe
contract SafeMock {
    function exec(address to, uint256 value, bytes calldata data, uint8 operation)
        external
        returns (bool success, bytes memory ret)
    {
        if (operation == 0) {
            (success, ret) = to.call{value: value}(data);
        } else {
            (success, ret) = to.delegatecall(data);
        }
    }
}
