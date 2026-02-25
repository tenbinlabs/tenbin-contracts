# SwapModule
[Git Source](https://github.com/tenbinlabs/contracts/blob/7874f0709e21201d251621138d90d5b61ccd404d/src/SwapModule.sol)

**Inherits:**
[ISwapModule](/src/interface/ISwapModule.sol/interface.ISwapModule.md)

**Title:**
Swap Module

The Swap Module is responsible for handling swaps using external protocols
This contract is permissioned so only a manager can call the swap function


## State Variables
### _NO_PARTIAL_FILLS_FLAG
1inch swap partial fills flag


```solidity
uint256 private constant _NO_PARTIAL_FILLS_FLAG = 1 << 255
```


### manager
Manager contract which calls this swap contract


```solidity
address public immutable manager
```


### admin
Admin address that can rescue tokens


```solidity
address public immutable admin
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

### onlyAdmin

Revert unless called by the admin


```solidity
modifier onlyAdmin() ;
```

### constructor

Set initial parameters


```solidity
constructor(address manager_, address router_, address admin_) ;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`manager_`|`address`|Manager to call the swap functions on this contract|
|`router_`|`address`|1Inch aggregation router|
|`admin_`|`address`||


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


### rescueToken

Rescue tokens sent to this contract

the receiver should be a trusted address to avoid external calls attack vectors


```solidity
function rescueToken(address token, address to) external onlyAdmin;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`token`|`address`|The address of the ERC20 token to be rescued|
|`to`|`address`|Recipient of rescued tokens|


