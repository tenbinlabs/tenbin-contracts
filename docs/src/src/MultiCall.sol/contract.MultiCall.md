# MultiCall
[Git Source](https://github.com/tenbinlabs/tenbin-contracts/blob/eb2d102704c08124f1036e9b92cd46f9cf41203f/src/MultiCall.sol)

**Inherits:**
AccessControl

**Title:**
Multicall with Access Control

Allow batched calls where the caller requires permission to use this contract


## Constants
### MULTICALLER_ROLE
Caller role can make calls to this contract


```solidity
bytes32 constant MULTICALLER_ROLE = keccak256("MULTICALLER_ROLE")
```


## Functions
### constructor


```solidity
constructor(address owner_) ;
```

### multicall

Allow batched calls. Will revert if any call reverts.


```solidity
function multicall(address[] calldata targets, bytes[] calldata data) external onlyRole(MULTICALLER_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`targets`|`address[]`|Target accounts to call|
|`data`|`bytes[]`|Data for each call|


## Errors
### ArrayLengthMismatch

```solidity
error ArrayLengthMismatch();
```

