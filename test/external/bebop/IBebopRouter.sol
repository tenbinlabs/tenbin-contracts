// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IBebopHook} from "./IBebopHook.sol";
import {IBebopRouterOrder} from "./IBebopRouterOrder.sol";

/// @notice Minimal ABI for the deployed BebopRouter methods used by the fork test.
interface IBebopRouter {
    function owner() external view returns (address);
    function setRouterSigner(address routerSigner) external;
    function isNonceValid(address account, uint256 nonce) external view returns (bool);
    function hashOrder(IBebopRouterOrder.BebopRouterOrder calldata order, bytes calldata extraInfo, bytes32 hooksHash)
        external
        view
        returns (bytes32);
    function hashHook(IBebopHook.Hook calldata hook, uint256 nonce) external view returns (bytes32);
    function hooksHash(
        IBebopHook.Hook[] calldata hooks,
        address[] calldata makerAddresses,
        uint256[] calldata makerNonces
    ) external pure returns (bytes32);
    function swap(
        int256 exactAmount,
        IBebopRouterOrder.BebopRouterOrder calldata order,
        bytes calldata extraInfo,
        bytes calldata routerSignature,
        bytes calldata bebopPmmCalldata,
        IBebopHook.Hook[] calldata hooks
    ) external payable;
}
