// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AccessControl} from "openzeppelin-contracts/contracts/access/AccessControl.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {IBurnMintERC20} from "../../interface/IBurnMintERC20.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IRestrictedRegistry} from "../../interface/IRestrictedRegistry.sol";

/// @title Spoke ERC20
/// @notice ERC20 for deployment on "spoke" chains. Facilitates cross-chain tokens by allowing
/// "mint-and-burn" operations on non-ethereum chains.
///
/// Has a resticted list for complying with legal requirements. Used for cross chain StakedAsset tokens
/// If an account is restricted, it cannot transfer assets
/// Restricted accounts can have their balance burned
/// Allows transferring to restricted accounts to ensure cross chain transfers can complete for restricted accounts
contract SpokeERC20Restricted is IBurnMintERC20, IRestrictedRegistry, ERC20Permit, AccessControl {
    /// @notice Minter role can mint and burn tokens
    bytes32 public constant MINTER_BURNER_ROLE = keccak256("MINTER_BURNER_ROLE");
    /// @notice Restricter role can change restricted status of accounts
    bytes32 public constant RESTRICTER_ROLE = keccak256("RESTRICTER_ROLE");

    /// @notice Mapping of restricted accounts
    mapping(address => bool) public isRestricted;

    /// @dev Reverts if account is restricted
    modifier nonRestricted(address account) {
        if (isRestricted[account]) revert AccountRestricted();
        _;
    }

    /// @dev Constructor
    /// @param name_ Token name
    /// @param symbol_ Token symbol
    constructor(string memory name_, string memory symbol_, address owner_) ERC20(name_, symbol_) ERC20Permit(name_) {
        _grantRole(DEFAULT_ADMIN_ROLE, owner_);
    }

    /// @inheritdoc IBurnMintERC20
    function mint(address account, uint256 amount) external onlyRole(MINTER_BURNER_ROLE) {
        _mint(account, amount);
    }

    /// @inheritdoc IBurnMintERC20
    function burn(uint256 amount) external nonRestricted(msg.sender) {
        _burn(msg.sender, amount);
    }

    /// @inheritdoc IBurnMintERC20
    function burn(address account, uint256 amount) external nonRestricted(account) onlyRole(MINTER_BURNER_ROLE) {
        _spendAllowance(account, _msgSender(), amount);
        _burn(account, amount);
    }

    /// @inheritdoc IBurnMintERC20
    function burnFrom(address account, uint256 amount) external nonRestricted(account) onlyRole(MINTER_BURNER_ROLE) {
        _spendAllowance(account, _msgSender(), amount);
        _burn(account, amount);
    }

    /// @notice Withdraw assets from a restricted account
    /// @param from Restricted account to sweep funds from
    /// @param to Account to transfer assets to
    /// @dev If it is necessary to sweep funds from a restricted account, the tokens will be
    /// transferred back to the hub chain and burned. This prevents permanent locking in the CCIP hub chain pool
    function transferRestricted(address from, address to) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (!isRestricted[from]) revert AccountNotRestricted();
        uint256 balance = balanceOf(from);
        // transfer if restricted account has tokens
        if (balance > 0) {
            _transfer(from, to, balance);
        }
    }

    /// @inheritdoc IRestrictedRegistry
    function setIsRestricted(address account, bool newStatus) external onlyRole(RESTRICTER_ROLE) {
        isRestricted[account] = newStatus;
        emit RestrictedStatusChanged(account, newStatus);
    }

    /// @dev Override transfer function to prevent restricted accounts from transferring
    /// Restricted accounts can still receive tokens
    function transfer(address to, uint256 value)
        public
        override(IERC20, ERC20)
        nonRestricted(msg.sender)
        returns (bool)
    {
        return super.transfer(to, value);
    }

    /// @dev Override transferFrom function to prevent restricted accounts from trasnferring tokens
    /// Restricted accounts can still receive tokens
    function transferFrom(address from, address to, uint256 value)
        public
        override(IERC20, ERC20)
        nonRestricted(from)
        nonRestricted(msg.sender)
        returns (bool)
    {
        return super.transferFrom(from, to, value);
    }
}
