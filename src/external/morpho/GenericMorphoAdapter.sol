// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.30;

import {IAdapter} from "vault-v2/src/interfaces/IAdapter.sol";
import {IVaultV2} from "vault-v2/src/interfaces/IVaultV2.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC4626.sol";
import {Ownable, Ownable2Step} from "openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import {SafeCast} from "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title GenericMorphoAdapter
/// @notice Adapter that connects a Vault V2 parent vault to a single ERC4626 vault.
/// @dev The parent vault allocates the underlying asset to this adapter, and the adapter
/// deposits those assets into the configured ERC4626 vault, said vault will always be a standard 
/// ERC4626 vault. Accounting is reported back to the parent vault through a single 
/// adapter-specific allocation ID.
///
/// @dev IMPORTANT: The configured ERC4626 vault MUST be resistant to inflation/donation
/// attacks, for example through virtual shares/assets or a provably adequate initial seed
/// that cannot be controlled or recovered by an attacker. This adapter does not enforce
/// inflation resistance on-chain; deployers and curators MUST verify the target vault
/// before admission.
contract GenericMorphoAdapter is IAdapter, Ownable2Step {
    using SafeCast for uint256;
    using SafeERC20 for IERC20;

    /// @notice Thrown when trying parent vault matches vault
    error InvalidVault();

    /// @notice Thrown when a caller other than the parent vault calls an adapter entrypoint.
    error NotAuthorized();

    /// @notice Thrown when the ERC4626 vault asset does not match the parent vault asset.
    error AssetMismatch();

    /// @notice Thrown when insufficient shares were returned by allocation vault
    error InsufficientShares();

    /// @notice Thrown when excessive shares were burned by deallocation vault
    error ExcessiveShares();

    /// @notice Thrown when trying to rescue a vault token
    error InvalidToken();

    /// @notice Parent vault authorized to allocate and deallocate through this adapter.
    IVaultV2 public immutable parentVault;

    /// @notice ERC4626 vault used as the yield source for this adapter.
    IERC4626 public immutable vault;

    /// @notice Underlying ERC20 asset managed by both the parent vault and ERC4626 vault.
    address public immutable asset;

    /// @notice Unique allocation ID used by the parent vault to track this adapter.
    bytes32 public immutable adapterId;

    /// @notice Deploys the adapter and grants token approvals to the ERC4626 vault and parent vault.
    /// @param parentVault_ Address of the Vault V2 parent vault that will use this adapter.
    /// @param vault_ Address of the ERC4626 vault where allocated assets will be deposited.
    constructor(address parentVault_, address vault_, address owner_) Ownable(owner_) {
        if(parentVault_ == vault_) revert InvalidVault();
        parentVault = IVaultV2(parentVault_);
        vault = IERC4626(vault_);
        asset = parentVault.asset();
        if (vault.asset() != parentVault.asset()) revert AssetMismatch();
        adapterId = keccak256(abi.encode("this", address(this)));

        IERC20(asset).forceApprove(vault_, type(uint256).max);
        IERC20(asset).forceApprove(parentVault_, type(uint256).max);
    }

    /// @inheritdoc IAdapter
    /// @notice Deposits allocated assets into the ERC4626 vault.
    /// @dev `data` must encode `minShares`, the minimum acceptable shares to receive. If `minShares` equals zero the slippage check is skipped.
    function allocate(bytes memory data, uint256 assets, bytes4, address) external returns (bytes32[] memory, int256) {
        if (msg.sender != address(parentVault)) revert NotAuthorized();

        uint256 minShares = abi.decode(data, (uint256));

        uint256 oldAllocation = parentVault.allocation(adapterId);

        uint256 shares;
        // If minShares equals zero the slippage check is skipped.
        if (assets > 0 && minShares > 0) {
            shares = vault.deposit(assets, address(this));
            if (shares < minShares) revert InsufficientShares();
        }

        uint256 newAllocation = _position();

        bytes32[] memory ids = new bytes32[](1);
        ids[0] = adapterId;

        return (ids, newAllocation.toInt256() - oldAllocation.toInt256());
    }

    /// @inheritdoc IAdapter
    /// @notice Withdraws allocated assets from the ERC4626 vault back into this adapter.
    /// @dev `data` must encode `maxShares`, the maximum acceptable shares to burn. If `maxShares` equals zero the slippage check is skipped.
    function deallocate(bytes memory data, uint256 assets, bytes4, address)
        external
        returns (bytes32[] memory, int256)
    {
        if (msg.sender != address(parentVault)) revert NotAuthorized();

        uint256 maxShares = abi.decode(data, (uint256));

        uint256 oldAllocation = parentVault.allocation(adapterId);

        uint256 shares;
        // If maxShares equals zero the slippage check is skipped.
        if (assets > 0 && maxShares > 0) {
            shares = vault.withdraw(assets, address(this), address(this));
            if (shares > maxShares) revert ExcessiveShares();
        }

        uint256 newAllocation = _position();

        bytes32[] memory ids = new bytes32[](1);
        ids[0] = adapterId;

        return (ids, newAllocation.toInt256() - oldAllocation.toInt256());
    }

    /// @inheritdoc IAdapter
    /// @notice Returns the current value of this adapter's ERC4626 share balance in underlying assets, excluding fees.
    /// @dev Uses ERC4626 conversion logic, so the result may be rounded down by the vault.
    function realAssets() public view returns (uint256) {
        return parentVault.allocation(adapterId) != 0 ? _position() : 0;
    }

    /// @notice Returns the current fee-aware value of the adapter's entire position in the child vault.
    /// @dev Unlike `realAssets()`, this function does not consider the parent vault's recorded allocation.
    /// It is intended for internal accounting during allocation and deallocation.
    /// @return assets The amount of underlying assets redeemable for all child-vault shares held by the adapter.
    function _position() internal view returns (uint256) {
        return vault.previewRedeem(vault.balanceOf(address(this)));
    }

    /// @notice Rescue tokens sent to this contract
    /// @param token The address of the ERC20 token to be rescued
    /// @param to Recipient of rescued tokens
    /// @dev The receiver should be a trusted address to avoid external calls attack vectors
    function rescueToken(address token, address to) external onlyOwner {
        if (token == address(vault)) revert InvalidToken();
        IERC20(token).safeTransfer(to, IERC20(token).balanceOf(address(this)));
    }
}
