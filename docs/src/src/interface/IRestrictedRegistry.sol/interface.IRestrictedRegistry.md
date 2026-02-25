# IRestrictedRegistry
[Git Source](https://github.com/tenbinlabs/contracts/blob/34d0d98c6959c0c67cf21488bdfb4b79f4ce3f2e/src/interface/IRestrictedRegistry.sol)

**Title:**
IRestrictedRegistry

Interface for contract managing the restricted registry


## Functions
### isRestricted

Returns true if address is restricted.


```solidity
function isRestricted(address account) external view returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`account`|`address`|The address to check|


### setIsRestricted

Sets or unsets an address as restricted


```solidity
function setIsRestricted(address account, bool newStatus) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`account`|`address`|The address to update|
|`newStatus`|`bool`|The new restriction status|


## Events
### RestrictedStatusChanged
Emitted when a restricted address status changes


```solidity
event RestrictedStatusChanged(address indexed account, bool isRestricted);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`account`|`address`|Address whose status was updated|
|`isRestricted`|`bool`|New status|

## Errors
### AccountRestricted
Throws when consulted address is restricted


```solidity
error AccountRestricted();
```

