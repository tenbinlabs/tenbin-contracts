// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @notice ABI-compatible order struct for the deployed BebopRouter.
interface IBebopRouterOrder {
    struct BebopRouterOrder {
        uint256 fromAmount;
        uint256 toAmount;
        int256 limitAmount;
        address fromToken;
        address toToken;
        address pmmFromToken;
        address pmmToToken;
        address tokensOwner;
        address receiver;
        address originAddress;
        address oracle;
        address checker;
        uint256 info;
        uint256 routerNonce;
        uint256 unsignedFlags;
    }
}
