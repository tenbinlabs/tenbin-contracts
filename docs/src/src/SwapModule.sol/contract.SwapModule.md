# SwapModule
[Git Source](https://github.com/tenbinlabs/contracts/blob/aca92cae688bdb3da3dd7de958cb87e2d6cc5d0e/src/SwapModule.sol)

**Inherits:**
[ISwapModule](/Users/tenbin/code/contracts/docs/src/src/interface/ISwapModule.sol/interface.ISwapModule.md)

The Swap Module is responsible for handling swaps using external protocols
This contract is permissioned so only a manager can call the swap function


## State Variables
### manager
Manager contract which calls this swap contract


```solidity
address public immutable manager
```


### router
1inch aggregation router


```solidity
address public immutable router
```


## Functions
### onlyManager

Revert unless called by the manager


```solidity
modifier onlyManager() ;
```

### constructor

Set initial parameters


```solidity
constructor(address manager_, address router_) ;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`manager_`|`address`|Manager to call the swap functions on this contract|
|`router_`|`address`|1Inch aggregation router|


### swap

Parse swap data from manager and execute swap


```solidity
function swap(bytes calldata parameters, bytes calldata data) external onlyManager;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`parameters`|`bytes`|Generic swap parameters|
|`data`|`bytes`|Additional swap data|


### swap1Inch

Perform a swap using 1inch


```solidity
function swap1Inch(SwapParameters memory params, bytes calldata data) internal;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`params`|`SwapParameters`|Generic swap parameters|
|`data`|`bytes`|Swap data for 1inch aggregation router|


