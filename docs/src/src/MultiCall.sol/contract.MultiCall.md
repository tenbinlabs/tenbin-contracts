# MultiCall
[Git Source](https://github.com/tenbinlabs/tenbin-contracts/blob/64004be494549e5de52bb55a6490bd85d73a4f57/src/MultiCall.sol)

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

