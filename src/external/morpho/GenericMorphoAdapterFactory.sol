// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {GenericMorphoAdapter} from "./GenericMorphoAdapter.sol";

/// @title GenericMorphoAdapterFactory
/// @notice Factory for deploying GenericMorphoAdapter contracts for parent vault / ERC4626 vault pairs.
contract GenericMorphoAdapterFactory {
    /// @notice Emitted when a new GenericMorphoAdapter is deployed.
    /// @param parentVault Parent vault that will use the adapter.
    /// @param vault ERC4626 vault connected to the adapter.
    /// @param genericMorphoAdapter Address of the deployed adapter.
    event CreateGenericMorphoAdapter(
        address indexed parentVault, address indexed vault, address indexed genericMorphoAdapter
    );

    /// @notice Returns the adapter deployed for a given parent vault and ERC4626 vault.
    mapping(address parentVault => mapping(address vault => address adapter)) public genericMorphoAdapter;

    /// @notice Tracks whether an address was deployed by this factory as a GenericMorphoAdapter.
    mapping(address account => bool) public isGenericMorphoAdapter;

    /// @notice Deploys a GenericMorphoAdapter for a parent vault and ERC4626 vault.
    /// @dev Reverts if the same constructor arguments have already been deployed with this factory.
    /// @param parentVault Address of the parent vault that will own/use the adapter.
    /// @param vault Address of the ERC4626 vault the adapter will allocate into.
    /// @return The address of the deployed GenericMorphoAdapter.
    function createGenericMorphoAdapter(address parentVault, address vault, address owner) external returns (address) {
        require(genericMorphoAdapter[parentVault][vault] == address(0), "Adapter already exists");
        address _genericMorphoAdapter = address(new GenericMorphoAdapter{salt: bytes32(0)}(parentVault, vault, owner));

        genericMorphoAdapter[parentVault][vault] = _genericMorphoAdapter;
        isGenericMorphoAdapter[_genericMorphoAdapter] = true;

        emit CreateGenericMorphoAdapter(parentVault, vault, _genericMorphoAdapter);

        return _genericMorphoAdapter;
    }
}
