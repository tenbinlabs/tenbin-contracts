# IAggregationRouterV6
[Git Source](https://github.com/tenbinlabs/contracts/blob/aca92cae688bdb3da3dd7de958cb87e2d6cc5d0e/src/external/1inch/IAggregationRouterV6.sol)


## Functions
### swap

Performs a swap, delegating all calls encoded in `data` to `executor`. See tests for usage examples.

Router keeps 1 wei of every token on the contract balance for gas optimisations reasons.
This affects first swap of every token by leaving 1 wei on the contract.


```solidity
function swap(IAggregationExecutor executor, SwapDescription calldata desc, bytes calldata data)
    external
    payable
    returns (uint256 returnAmount, uint256 spentAmount);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`executor`|`IAggregationExecutor`|Aggregation executor that executes calls described in `data`.|
|`desc`|`SwapDescription`|Swap description.|
|`data`|`bytes`|Encoded calls that `caller` should execute in between of swaps.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`returnAmount`|`uint256`|Resulting token amount.|
|`spentAmount`|`uint256`|Source token amount.|


## Structs
### SwapDescription

```solidity
struct SwapDescription {
    IERC20 srcToken;
    IERC20 dstToken;
    address payable srcReceiver;
    address payable dstReceiver;
    uint256 amount;
    uint256 minReturnAmount;
    uint256 flags;
}
```

