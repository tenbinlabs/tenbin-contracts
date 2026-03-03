// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IAggregationRouterV6, IAggregationExecutor} from "../../src/external/1inch/IAggregationRouterV6.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

/// @dev Mock 1inch router for testing
contract Mock1InchRouter is IAggregationRouterV6 {
    using SafeERC20 for IERC20;

    /// @dev Mock a 1inch swap by transferring src token out from sender and dst token to this contract
    function swap(
        IAggregationExecutor, /* executor */
        IAggregationRouterV6.SwapDescription calldata desc,
        bytes calldata /* data */
    )
        external
        payable
        returns (uint256 returnAmount, uint256 spentAmount)
    {
        IERC20 srcToken = desc.srcToken;
        IERC20 dstToken = desc.dstToken;
        srcToken.safeTransferFrom(msg.sender, address(this), desc.amount);
        dstToken.safeTransfer(desc.dstReceiver, desc.minReturnAmount);
        return (desc.minReturnAmount, desc.amount);
    }

    // mark this as a test contract
    function test() public {}
}

/// @dev Mock 1inch router for testing, which always returns fewer tokens than expected
contract Mock1InchRouterWithInsufficientReturnAmount is IAggregationRouterV6 {
    using SafeERC20 for IERC20;

    /// @dev Mock a 1inch swap by transferring src token out from sender and dst token to this contract
    function swap(
        IAggregationExecutor, /* executor */
        IAggregationRouterV6.SwapDescription calldata desc,
        bytes calldata /* data */
    )
        external
        payable
        returns (uint256 returnAmount, uint256 spentAmount)
    {
        IERC20 srcToken = desc.srcToken;
        IERC20 dstToken = desc.dstToken;
        srcToken.safeTransferFrom(msg.sender, address(this), desc.amount);
        dstToken.safeTransfer(desc.dstReceiver, desc.minReturnAmount - 1000);
        return (desc.minReturnAmount - 1000, desc.amount);
    }

    // mark this as a test contract
    function test() public {}
}

/// @dev Mock 1inch router for testing, which always spends fewer tokens than expected
contract Mock1InchRouterWithInsufficientAmountSent is IAggregationRouterV6 {
    using SafeERC20 for IERC20;

    /// @dev Mock a 1inch swap by transferring src token out from sender and dst token to this contract
    function swap(
        IAggregationExecutor, /* executor */
        IAggregationRouterV6.SwapDescription calldata desc,
        bytes calldata /* data */
    )
        external
        payable
        returns (uint256 returnAmount, uint256 spentAmount)
    {
        IERC20 srcToken = desc.srcToken;
        IERC20 dstToken = desc.dstToken;
        srcToken.safeTransferFrom(msg.sender, address(this), desc.amount);
        dstToken.safeTransfer(desc.dstReceiver, desc.minReturnAmount - 1000);
        return (desc.minReturnAmount, desc.amount);
    }

    // mark this as a test contract
    function test() public {}
}

/// @dev Mock 1inch router for testing, which always returns fewer spent tokens than expected
contract Mock1InchRouterWithInsufficientAmountReportSent is IAggregationRouterV6 {
    using SafeERC20 for IERC20;

    /// @dev Mock a 1inch swap by transferring src token out from sender and dst token to this contract
    function swap(
        IAggregationExecutor, /* executor */
        IAggregationRouterV6.SwapDescription calldata desc,
        bytes calldata /* data */
    )
        external
        payable
        returns (uint256 returnAmount, uint256 spentAmount)
    {
        IERC20 srcToken = desc.srcToken;
        IERC20 dstToken = desc.dstToken;
        srcToken.safeTransferFrom(msg.sender, address(this), desc.amount);
        dstToken.safeTransfer(desc.dstReceiver, desc.minReturnAmount);
        return (desc.minReturnAmount, 0);
    }

    // mark this as a test contract
    function test() public {}
}

/// @dev Mock 1inch router for testing, which always returns more tokens than expected
contract Mock1InchRouterWithExtraAmountSent is IAggregationRouterV6 {
    using SafeERC20 for IERC20;

    /// @dev Mock a 1inch swap by transferring src token out from sender and dst token to this contract
    function swap(
        IAggregationExecutor, /* executor */
        IAggregationRouterV6.SwapDescription calldata desc,
        bytes calldata /* data */
    )
        external
        payable
        returns (uint256 returnAmount, uint256 spentAmount)
    {
        IERC20 srcToken = desc.srcToken;
        IERC20 dstToken = desc.dstToken;
        srcToken.safeTransferFrom(msg.sender, address(this), desc.amount);
        dstToken.safeTransfer(desc.dstReceiver, desc.minReturnAmount * 2);
        return (desc.minReturnAmount, desc.amount);
    }

    // mark this as a test contract
    function test() public {}
}
