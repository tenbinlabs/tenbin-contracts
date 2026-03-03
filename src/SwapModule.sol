// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IAggregationRouterV6, IAggregationExecutor} from "./external/1inch/IAggregationRouterV6.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ISwapModule} from "./interface/ISwapModule.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title Swap Module
/// @notice The Swap Module is responsible for handling swaps using external protocols
/// This contract is permissioned so only a manager can call the swap function
contract SwapModule is ISwapModule {
    using SafeERC20 for IERC20;

    /// @dev 1inch swap partial fills flag
    uint256 private constant _NO_PARTIAL_FILLS_FLAG = 1 << 255;

    /// @notice Manager contract which calls this swap contract
    address public immutable manager;

    /// @notice Admin address that can rescue tokens
    address public immutable admin;

    /// @notice 1inch aggregation router
    address public immutable router;

    /// @dev Revert unless called by the manager
    modifier onlyManager() {
        if (msg.sender != manager) revert OnlyManager();
        _;
    }

    /// @dev Revert unless called by the admin
    modifier onlyAdmin() {
        if (msg.sender != admin) revert OnlyAdmin();
        _;
    }

    /// @dev Set initial parameters
    /// @param manager_ Manager to call the swap functions on this contract
    /// @param router_ 1Inch aggregation router
    constructor(address manager_, address router_, address admin_) {
        manager = manager_;
        router = router_;
        admin = admin_;
    }

    /// @inheritdoc ISwapModule
    function swap(bytes calldata parameters, bytes calldata data) external onlyManager {
        // decode parameters
        SwapParameters memory params = abi.decode(parameters, (SwapParameters));

        // handle swap type
        if (params.swapType == uint96(SwapType.OneInch)) {
            swap1Inch(params, data);
        } else {
            revert SwapTypeNotSupported();
        }
    }

    /// @dev Perform a swap using 1inch
    /// @param params Generic swap parameters
    /// @param data Swap data for 1inch aggregation router
    function swap1Inch(SwapParameters memory params, bytes calldata data) internal {
        // decode data
        (IAggregationExecutor executor, IAggregationRouterV6.SwapDescription memory swapData, bytes memory route) =
            abi.decode(data, (IAggregationExecutor, IAggregationRouterV6.SwapDescription, bytes));

        // sanitize inputs
        if (params.router != router) revert InvalidRouter();
        if (params.srcToken != address(swapData.srcToken)) revert InvalidSrcToken();
        if (params.dstToken != address(swapData.dstToken)) revert InvalidDstToken();
        if (params.amount != swapData.amount) revert InvalidAmount();
        // Can potentially remove this line if we want a bigger "real" slippage tolerance
        if (params.minReturnAmount > swapData.minReturnAmount) revert InvalidMinReturnAmount();
        if (swapData.dstReceiver != manager) revert InvalidDstReceiver();
        // srcReceiver must always be executor
        if (swapData.srcReceiver != address(executor) && swapData.srcReceiver != address(router)) {
            revert InvalidSrcReceiver();
        }
        // Verify flags
        if (swapData.flags & _NO_PARTIAL_FILLS_FLAG != 0) revert PartialFillNotAllowed();

        // approve tokens
        IERC20(params.srcToken).safeIncreaseAllowance(params.router, params.amount);

        // execute swap with route data
        (uint256 returnAmount, uint256 spentAmount) = IAggregationRouterV6(router).swap(executor, swapData, route);

        // ensure parameters are met after swap
        if (spentAmount < params.amount) revert InvalidAmount();
        if (returnAmount < params.minReturnAmount) revert InsufficientReturnAmount();
    }

    /// @notice Rescue tokens sent to this contract
    /// @param token The address of the ERC20 token to be rescued
    /// @param to Recipient of rescued tokens
    /// @dev the receiver should be a trusted address to avoid external calls attack vectors
    function rescueToken(address token, address to) external onlyAdmin {
        if (to == address(0)) revert NonZeroAddress();
        IERC20(token).safeTransfer(to, IERC20(token).balanceOf(address(this)));
    }
}
