// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {VaultAdapter} from "./VaultAdapter.sol";

/// @title VaultAdapterFactory
/// @notice Factory for deploying VaultAdapter contracts for parent vault / ERC4626 vault pairs.
contract VaultAdapterFactory {
    /// @notice Emitted when a new VaultAdapter is deployed.
    /// @param parentVault Parent vault that will use the adapter.
    /// @param vault ERC4626 vault connected to the adapter.
    /// @param vaultAdapter Address of the deployed adapter.
    event CreateVaultAdapter(address indexed parentVault, address indexed vault, address indexed vaultAdapter);

    /// @notice Returns the adapter deployed for a given parent vault and ERC4626 vault.
    mapping(address parentVault => mapping(address vault => address adapter)) public vaultAdapter;

    /// @notice Tracks whether an address was deployed by this factory as a VaultAdapter.
    mapping(address account => bool) public isVaultAdapter;

    /// @notice Deploys a VaultAdapter for a parent vault and ERC4626 vault.
    /// @dev Reverts if the same constructor arguments have already been deployed with this factory.
    /// @param parentVault Address of the parent vault that will own/use the adapter.
    /// @param vault Address of the ERC4626 vault the adapter will allocate into.
    /// @return The address of the deployed VaultAdapter.
    function createVaultAdapter(address parentVault, address vault, address owner) external returns (address) {
        address _vaultAdapter = address(new VaultAdapter{salt: bytes32(0)}(parentVault, vault, owner));

        vaultAdapter[parentVault][vault] = _vaultAdapter;
        isVaultAdapter[_vaultAdapter] = true;

        emit CreateVaultAdapter(parentVault, vault, _vaultAdapter);

        return _vaultAdapter;
    }
}
