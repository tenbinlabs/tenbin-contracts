// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title Swap Module
/// @notice The Swap Module is responsible for handling swaps using external protocols
/// This contract is permissioned so only a manager can call the swap function
interface ISwapModule {
    /// @notice Swap types for this contracts
    /// @param OneInchSwap Swap on 1inch exchange
    enum SwapType {
        OneInch
    }

    /// @notice Generic swap data for performing swaps with the swap module
    /// @param swapType Type of swap to execute
    /// @param srcToken Token to send
    /// @param dstToken Token to receive
    /// @param amount Amount to swap
    /// @param minReturnAmount Minimum amount out
    struct SwapParameters {
        uint96 swapType;
        address router;
        address srcToken;
        address dstToken;
        uint256 amount;
        uint256 minReturnAmount;
    }

    /// @dev Swap returned insufficient amount out
    error InsufficientReturnAmount();
    /// @dev Amount does not match parameters
    error InvalidAmount();
    /// @dev Dst receiver is not manager
    error InvalidDstReceiver();
    /// @dev Destination token does not match parameters
    error InvalidDstToken();
    /// @dev Return amount does not match parameters
    error InvalidMinReturnAmount();
    /// @dev Router parameter does not match swap router
    error InvalidRouter();
    /// @dev Src receiver is not executor or router
    error InvalidSrcReceiver();
    /// @dev Source token does not match parameters
    error InvalidSrcToken();
    /// @dev Revert if zero address
    error NonZeroAddress();
    /// @dev Revert if not called by admin
    error OnlyAdmin();
    /// @dev Revert if not called by the manager
    error OnlyManager();
    /// @dev The swap description cannot include the partial fill flag
    error PartialFillNotAllowed();
    /// @dev Swap type is not supported
    error SwapTypeNotSupported();

    /// @notice Parse swap data from manager and execute swap
    /// @param parameters Generic swap parameters
    /// @param data Additional swap data
    function swap(bytes calldata parameters, bytes calldata data) external;
}
