// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {AccessControl} from "openzeppelin-contracts/contracts/access/AccessControl.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title CustodianModule
/// @notice Allows funds to be transferred to approved custodian accounts
/// Collateral is sent to this contract during the asset minting process
/// Custodian accounts are whitelisted by an administrator
/// A keeper role can automate transferring collateral to different custodians
contract CustodianModule is AccessControl {
    using SafeERC20 for IERC20;

    /// @notice Keeper role can distribute tokens to approved custodian accounts
    bytes32 public constant CUSTODIAN_KEEPER_ROLE = keccak256("CUSTODIAN_KEEPER_ROLE");

    /// @notice Approved custodian accounts
    mapping(address => bool) public custodians;

    /// @notice Emitted when a custodian status is updated
    /// @param account The account updated
    /// @param isCustodian Whether account is a custodian or not
    event CustodianUpdated(address account, bool isCustodian);

    /// @notice Token receiver not in custodians list
    error NotApprovedCustodian();

    /// @notice Zero address not allowed
    error NonZeroAddress();

    /// @dev Revert if zero address
    modifier nonZeroAddress(address addr) {
        if (addr == address(0)) revert NonZeroAddress();
        _;
    }

    /// @dev CustodianModule constructor
    /// @param owner Address to be assigned the DEFAULT_ADMIN_ROLE
    constructor(address owner) {
        _grantRole(DEFAULT_ADMIN_ROLE, owner);
    }

    /// @notice Set an account as a custodian
    /// @param account Account to add to custodians list
    /// @param status Whether or not an account is a custodian
    function setCustodianStatus(address account, bool status)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        nonZeroAddress(account)
    {
        custodians[account] = status;
        emit CustodianUpdated(account, status);
    }

    /// @notice Sends funds to a whitelisted custodian account
    /// @param account Address to receive the funds
    /// @param token Address of tokens to be transferred
    /// @param amount Amount of token to be transferred
    function offramp(address account, address token, uint256 amount)
        external
        onlyRole(CUSTODIAN_KEEPER_ROLE)
        nonZeroAddress(account)
        nonZeroAddress(token)
    {
        if (!custodians[account]) revert NotApprovedCustodian();
        IERC20(token).safeTransfer(account, amount);
    }
}
