// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {AccessControl} from "openzeppelin-contracts/contracts/access/AccessControl.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {IBurnMintERC20} from "../../interface/IBurnMintERC20.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IRestrictedRegistry} from "../../interface/IRestrictedRegistry.sol";

/// @title Spoke ERC20
/// @notice ERC20 for deployment on "spoke" chains. Facilitates cross-chain tokens by allowing
/// "mint-and-burn" operations on non-ethereum chains.
contract SpokeERC20 is IBurnMintERC20, IRestrictedRegistry, ERC20Permit, AccessControl {
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
    function mint(address account, uint256 amount) external nonRestricted(account) onlyRole(MINTER_BURNER_ROLE) {
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

    /// @inheritdoc IRestrictedRegistry
    function setIsRestricted(address account, bool newStatus) external onlyRole(RESTRICTER_ROLE) {
        isRestricted[account] = newStatus;
        emit RestrictedStatusChanged(account, newStatus);
    }

    /// @dev Override transfer function to prevent restricted accounts from transferring
    function transfer(address to, uint256 value)
        public
        override(IERC20, ERC20)
        nonRestricted(msg.sender)
        nonRestricted(to)
        returns (bool)
    {
        return super.transfer(to, value);
    }

    /// @dev Override transferFrom function to prevent restricted accounts from transferring
    function transferFrom(address from, address to, uint256 value)
        public
        override(IERC20, ERC20)
        nonRestricted(from)
        nonRestricted(to)
        nonRestricted(msg.sender)
        returns (bool)
    {
        return super.transferFrom(from, to, value);
    }
}
