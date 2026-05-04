// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title IRestrictedRegistry
/// @notice Interface for contract managing the restricted registry
interface IRestrictedRegistry {
    /// @notice Throws when account is restricted
    error AccountRestricted();
    /// @notice Throws when account is not restricted
    error AccountNotRestricted();

    /// @notice Emitted when a restricted address status changes
    /// @param account Address whose status was updated
    /// @param isRestricted New status
    event RestrictedStatusChanged(address indexed account, bool isRestricted);

    /// @notice Returns true if address is restricted.
    /// @param account The address to check
    function isRestricted(address account) external view returns (bool);

    /// @notice Sets or unsets an address as restricted
    /// @param account The address to update
    /// @param newStatus The new restriction status
    function setIsRestricted(address account, bool newStatus) external;
}
