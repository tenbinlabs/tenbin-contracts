# IRestrictedRegistry
[Git Source](https://github.com/tenbinlabs/tenbin-contracts/blob/03cb36d03e9d12b530c127a14daa5c41e1749e7d/src/interface/IRestrictedRegistry.sol)

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
Throws when account is restricted


```solidity
error AccountRestricted();
```

### AccountNotRestricted
Throws when account is not restricted


```solidity
error AccountNotRestricted();
```

