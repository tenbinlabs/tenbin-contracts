///   __/\\\\\\\\\\\\\\\__________________________/\\\____________________________
///    _\///////\\\/////__________________________\/\\\____________________________
///     _______\/\\\_______________________________\/\\\_________/\\\_______________
///      _______\/\\\______/\\\\\\\\___/\\/\\\\\\___\/\\\________\///___/\\/\\\\\\___
///       _______\/\\\____/\\\/////\\\_\/\\\////\\\__\/\\\\\\\\\___/\\\_\/\\\////\\\__
///        _______\/\\\___/\\\\\\\\\\\__\/\\\__\//\\\_\/\\\////\\\_\/\\\_\/\\\__\//\\\_
///         _______\/\\\__\//\\///////___\/\\\___\/\\\_\/\\\__\/\\\_\/\\\_\/\\\___\/\\\_
///          _______\/\\\___\//\\\\\\\\\\_\/\\\___\/\\\_\/\\\\\\\\\__\/\\\_\/\\\___\/\\\_
///           _______\///_____\//////////__\///____\///__\/////////___\///__\///____\///__

// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {IBurnMintERC20} from "./interface/IBurnMintERC20.sol";
import {Ownable, Ownable2Step} from "openzeppelin-contracts/contracts/access/Ownable2Step.sol";

/// @title Asset Token
/// @notice A token to represent assets as part of the Tenbin protocol
/// Implemented as an ERC20 with added mint() and burn() functions
/// The `minter` role is set by the owner, and is allowed to call the mint() function
/// Allow the owner to attach a token notice returned by `notice()`
contract AssetToken is IBurnMintERC20, ERC20Permit, Ownable2Step {
    /// @notice Only minter
    error OnlyMinter();

    /// @notice Emitted when the minter account is changed
    /// @param newMinter New minter account
    event MinterChanged(address newMinter);

    /// @notice Account which has permission to mint tokens
    address public minter;

    /// @notice Attach a token notice which can be updated by the owner
    string public notice;

    /// @dev Constructor
    /// @param name_ Token name
    /// @param symbol_ Token symbol
    constructor(string memory name_, string memory symbol_, address owner_)
        ERC20(name_, symbol_)
        ERC20Permit(name_)
        Ownable(owner_)
    {}

    /// @notice Set minter account
    /// @param newMinter New minter account
    function setMinter(address newMinter) external onlyOwner {
        minter = newMinter;
        emit MinterChanged(newMinter);
    }

    /// @inheritdoc IBurnMintERC20
    function mint(address account, uint256 amount) external {
        if (msg.sender != minter) revert OnlyMinter();
        _mint(account, amount);
    }

    /// @inheritdoc IBurnMintERC20
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    /// @inheritdoc IBurnMintERC20
    function burn(address account, uint256 amount) external {
        _spendAllowance(account, _msgSender(), amount);
        _burn(account, amount);
    }

    /// @inheritdoc IBurnMintERC20
    function burnFrom(address account, uint256 amount) external {
        _spendAllowance(account, _msgSender(), amount);
        _burn(account, amount);
    }

    /// @notice Set a new token notice
    /// @param newNotice New token notice
    function setNotice(string calldata newNotice) external onlyOwner {
        notice = newNotice;
    }
}
