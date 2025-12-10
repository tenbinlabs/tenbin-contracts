# IMintableBurnable
[Git Source](https://github.com/tenbinlabs/contracts/blob/aca92cae688bdb3da3dd7de958cb87e2d6cc5d0e/src/interface/IMintableBurnable.sol)

Interface for mintable and burnable tokens


## Functions
### burn

Burns tokens from a specified account


```solidity
function burn(address _from, uint256 _amount) external returns (bool success);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_from`|`address`|Address from which tokens will be burned|
|`_amount`|`uint256`|Amount of tokens to be burned|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`success`|`bool`|Indicates whether the operation was successful|


### mint

Mints tokens to a specified account


```solidity
function mint(address _to, uint256 _amount) external returns (bool success);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_to`|`address`|Address to which tokens will be minted|
|`_amount`|`uint256`|Amount of tokens to be minted|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`success`|`bool`|Indicates whether the operation was successful|


