# MultiCall
[Git Source](https://github.com/tenbinlabs/contracts/blob/aca92cae688bdb3da3dd7de958cb87e2d6cc5d0e/src/MultiCall.sol)

**Inherits:**
AccessControl

Allow batched calls where the caller requires permission to use this contract


## State Variables
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


