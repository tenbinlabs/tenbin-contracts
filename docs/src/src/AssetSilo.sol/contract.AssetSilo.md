# AssetSilo
[Git Source](https://github.com/tenbinlabs/contracts/blob/7874f0709e21201d251621138d90d5b61ccd404d/src/AssetSilo.sol)

**Title:**
AssetSilo

Stores assets in cooldown for Tenbin protocol staking
Allows for canceling a cooldown by minting new staked assets


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


### cancel

Cancel cooldown for an account by minting new shares


```solidity
function cancel(address account, uint256 amount) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`account`|`address`|Account to mint new staking shares for|
|`amount`|`uint256`|Amount of assets to deposit|


## Errors
### OnlyStaking
Only staking contract


```solidity
error OnlyStaking();
```

