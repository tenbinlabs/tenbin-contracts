// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title IRevenueModule
/// @notice The RevenueModule manages revenue in the Tenbin protocol.
interface IRevenueModule {
    /// @notice Token had no pending revenue to collect
    error InsufficientRevenue();
    /// @notice Invalid transfer amount
    error InvalidAmount();
    /// @notice Invalid zero address
    error NonZeroAddress();

    /// @notice Emitted when revenue is withdrawn from collateral manager to self
    /// @param token The requested token to be withdrawn
    /// @param amount The amount of revenue tokens
    event RevenueCollected(address indexed token, uint256 amount);

    /// @notice Emitted when revenue is sent to the multisig
    /// @param token The requested token to be withdrawn
    /// @param amount The amount of revenue tokens
    event WithdrawToMultisig(address indexed token, uint256 amount);

    /// @notice Emitted when revenue is sent to the manager
    /// @param token The requested token to be withdrawn
    /// @param amount The amount of revenue tokens
    event WithdrawToManager(address indexed token, uint256 amount);

    /// @notice Emitted when revenue is sent to the staking contract as asset tokens
    /// @param amount The amount of rewarded tokens
    event RewardSent(uint256 amount);

    /// @notice Emitted when multisig is updated
    /// @param newMultisig New multisig address
    event MultisigUpdated(address newMultisig);

    /// @notice Withdraw pending revenue from CollateralManager
    /// @param token Token address to withdraw revenue for
    /// @param amount Amount of tokens to withdraw
    function collect(address token, uint256 amount) external;

    /// @notice Transfer tokens to a multisig account
    /// @param token Token address to be withdrawn
    /// @param amount Amount of tokens to withdraw
    function withdrawToMultisig(address token, uint256 amount) external;

    /// @notice Transfer tokens to collateral manager
    /// @param token Token address to be withdrawn
    /// @param amount Amount of tokens to withdraw
    function withdrawToManager(address token, uint256 amount) external;

    /// @notice Transfer asset tokens to staking contract
    /// @param amount Amount of tokens to reward
    function reward(uint256 amount) external;

    /// @notice Approve collateral tokens to be transferred during a Mint order
    /// @param token Collateral token address to be approved
    /// @param amount Amount of tokens to approve
    function setControllerApproval(address token, uint256 amount) external;

    /// @notice Allow a signer in the controller to sign orders where this contract is the payer
    /// @param signer Signer account
    /// @param status Whether or not this signer is delegated
    function delegateSigner(address signer, bool status) external;
}
