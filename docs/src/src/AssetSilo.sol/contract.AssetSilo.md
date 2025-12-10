# AssetSilo
[Git Source](https://github.com/tenbinlabs/contracts/blob/aca92cae688bdb3da3dd7de958cb87e2d6cc5d0e/src/AssetSilo.sol)

Stores assets in cooldown for Tenbin protocol staking


## State Variables
### staking
Staking contract


```solidity
address public immutable staking
```


### asset
Asset token


```solidity
IERC20 immutable asset
```


## Functions
### constructor

AssetSilo constructor


```solidity
constructor(address staking_, address asset_) ;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`staking_`|`address`|Address of staking contract|
|`asset_`|`address`|Address of asset contract|


### withdraw

Withdraw assets to an account


```solidity
function withdraw(address to, uint256 amount) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`to`|`address`|Account to withdraw tokens to|
|`amount`|`uint256`|Amount of tokens to withdraw|


## Errors
### OnlyStaking
Only staking contract


```solidity
error OnlyStaking();
```

