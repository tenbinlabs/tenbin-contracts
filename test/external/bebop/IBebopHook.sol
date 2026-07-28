// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @notice ABI-compatible hook struct for the deployed BebopRouter.
interface IBebopHook {
    struct Hook {
        address targetContract;
        bytes data;
        bytes hookSignature;
        /// @dev bits 0-159 maker; 160 post-hook; 161 revert-on-fail;
        ///      162 use bebopHook; 163 router approval.
        uint256 flags;
    }
}
