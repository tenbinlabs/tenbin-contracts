// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/// @notice Bepop interface for a single swap leg between taker and maker
struct Swap {
    uint256 takerAmount;
    address takerToken;
    uint256 makerAmount;
    address makerToken;
}

/// @dev https://github.com/bebop-dex/bebop-rfqa/blob/master/README.md#hooks
interface IBebopHook {
    /// @notice Called by BebopRouter during hook execution.
    /// @param makerAddress  The maker that signed this hook (Hook.flags.makerAddress, could be address(0) if no signature verification).
    /// Passed by the router so the hook contract can act on behalf of a specific maker.
    /// @param data Arbitrary data passed through from the Hook struct.
    /// @param swaps All swap legs for this hook's maker, scaled to the filled amount.
    function bebopHook(address makerAddress, bytes calldata data, Swap[] calldata swaps) external;
}
