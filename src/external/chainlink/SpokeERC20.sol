// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {AccessControl} from "lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import {ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {IBurnMintERC20} from "src/interface/IBurnMintERC20.sol";

/// @title Spoke ERC20
/// @notice ERC20 for deployment on "spoke" chains. Facilitates cross-chain tokens by allowing
/// "mint-and-burn" operations on non-ethereum chains.
contract SpokeERC20 is IBurnMintERC20, ERC20Permit, AccessControl {
    /// @notice Minter role can mint and burn tokens
    bytes32 public constant MINTER_BURNER_ROLE = keccak256("MINTER_BURNER_ROLE");

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
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    /// @inheritdoc IBurnMintERC20
    function burn(address account, uint256 amount) external onlyRole(MINTER_BURNER_ROLE) {
        _spendAllowance(account, _msgSender(), amount);
        _burn(account, amount);
    }

    /// @inheritdoc IBurnMintERC20
    function burnFrom(address account, uint256 amount) external onlyRole(MINTER_BURNER_ROLE) {
        _spendAllowance(account, _msgSender(), amount);
        _burn(account, amount);
    }
}
