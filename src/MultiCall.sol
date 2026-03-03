// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {AccessControl} from "openzeppelin-contracts/contracts/access/AccessControl.sol";

/// @title Multicall with Access Control
/// @notice Allow batched calls where the caller requires permission to use this contract
contract MultiCall is AccessControl {
    // @notice Sent targets and data have different lengths
    error ArrayLengthMismatch();

    /// @notice Caller role can make calls to this contract
    bytes32 constant MULTICALLER_ROLE = keccak256("MULTICALLER_ROLE");

    constructor(address owner_) {
        _grantRole(DEFAULT_ADMIN_ROLE, owner_);
    }

    /// @dev Allow batched calls. Will revert if any call reverts.
    /// @param targets Target accounts to call
    /// @param data Data for each call
    function multicall(address[] calldata targets, bytes[] calldata data) external onlyRole(MULTICALLER_ROLE) {
        if (targets.length != data.length) revert ArrayLengthMismatch();
        for (uint256 i = 0; i < data.length; ++i) {
            (bool success, bytes memory returnData) = targets[i].call(data[i]);
            if (!success) {
                assembly ("memory-safe") {
                    revert(add(32, returnData), mload(returnData))
                }
            }
        }
    }
}
