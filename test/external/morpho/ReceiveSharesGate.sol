// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IReceiveSharesGate} from "./interfaces/IGate.sol";

contract ReceiveSharesGate is IReceiveSharesGate {
    address public owner;
    mapping(address => bool) public whitelisted;

    error Unauthorized();

    constructor(address _owner) {
        owner = _owner;
    }

    /// @notice Set who is whitelisted.
    function setIsWhitelisted(address account, bool newIsWhitelisted) external {
        require(msg.sender == owner, Unauthorized());
        whitelisted[account] = newIsWhitelisted;
    }

    /// @notice Check if `account` can receive shares.
    function canReceiveShares(address account) external view returns (bool) {
        return whitelisted[account];
    }
}
