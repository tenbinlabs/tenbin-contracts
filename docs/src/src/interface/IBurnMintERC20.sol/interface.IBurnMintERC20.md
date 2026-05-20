# IBurnMintERC20
[Git Source](https://github.com/tenbinlabs/tenbin-contracts/blob/14e4f5c2d1208a42b40e6ca6182f36f84dc88dd9/src/interface/IBurnMintERC20.sol)

**Inherits:**
IERC20

**Title:**
IBurnMintERC20

Interface to implement universal mint/burn functions


## Functions
### mint

Mints new tokens for a given address.

this function increases the total supply.


```solidity
function mint(address account, uint256 amount) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`account`|`address`|The address to mint the new tokens to.|
|`amount`|`uint256`|The number of tokens to be minted.|


### burn

Burns tokens from the sender.

this function decreases the total supply.


```solidity
function burn(uint256 amount) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`amount`|`uint256`|The number of tokens to be burned.|


### burn

Burns tokens from a given address.

this function decreases the total supply.


```solidity
function burn(address account, uint256 amount) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`account`|`address`|The address to burn tokens from.|
|`amount`|`uint256`|The number of tokens to be burned.|


### burnFrom

Burns tokens from a given address.

this function decreases the total supply.


```solidity
function burnFrom(address account, uint256 amount) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`account`|`address`|The address to burn tokens from.|
|`amount`|`uint256`|The number of tokens to be burned.|


