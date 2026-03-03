// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

interface IAggregationExecutor {
    /// @notice propagates information about original msg.sender and executes arbitrary data
    function execute(address msgSender) external payable returns (uint256); // 0x4b64e492
}

interface IAggregationRouterV6 {
    struct SwapDescription {
        IERC20 srcToken;
        IERC20 dstToken;
        address payable srcReceiver;
        address payable dstReceiver;
        uint256 amount;
        uint256 minReturnAmount;
        uint256 flags;
    }

    /**
     * @notice Performs a swap, delegating all calls encoded in `data` to `executor`. See tests for usage examples.
     * @dev Router keeps 1 wei of every token on the contract balance for gas optimisations reasons.
     *      This affects first swap of every token by leaving 1 wei on the contract.
     * @param executor Aggregation executor that executes calls described in `data`.
     * @param desc Swap description.
     * @param data Encoded calls that `caller` should execute in between of swaps.
     * @return returnAmount Resulting token amount.
     * @return spentAmount Source token amount.
     */
    function swap(IAggregationExecutor executor, SwapDescription calldata desc, bytes calldata data)
        external
        payable
        returns (uint256 returnAmount, uint256 spentAmount);
}
