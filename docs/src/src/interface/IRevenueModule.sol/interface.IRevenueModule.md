# IRevenueModule
[Git Source](https://github.com/tenbinlabs/tenbin-contracts/blob/3b9a2e72170c3c18199904176b97ca07122173ad/src/interface/IRevenueModule.sol)

**Title:**
IRevenueModule

The RevenueModule manages revenue in the Tenbin protocol.


## Functions
### collect

Withdraw pending revenue from CollateralManager


```solidity
function collect(address token, uint256 amount) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`token`|`address`|Token address to withdraw revenue for|
|`amount`|`uint256`|Amount of tokens to withdraw|


### withdrawToMultisig

Transfer tokens to a multisig account


```solidity
function withdrawToMultisig(address token, uint256 amount) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`token`|`address`|Token address to be withdrawn|
|`amount`|`uint256`|Amount of tokens to withdraw|


### withdrawToManager

Transfer tokens to collateral manager


```solidity
function withdrawToManager(address token, uint256 amount) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`token`|`address`|Token address to be withdrawn|
|`amount`|`uint256`|Amount of tokens to withdraw|


### reward

Transfer asset tokens to staking contract


```solidity
function reward(uint256 amount) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`amount`|`uint256`|Amount of tokens to reward|


### setControllerApproval

Approve collateral tokens to be transferred during a Mint order


```solidity
function setControllerApproval(address token, uint256 amount) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`token`|`address`|Collateral token address to be approved|
|`amount`|`uint256`|Amount of tokens to approve|


### delegateSigner

Allow a signer in the controller to sign orders where this contract is the payer


```solidity
function delegateSigner(address signer, bool status) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`signer`|`address`|Signer account|
|`status`|`bool`|Whether or not this signer is delegated|


## Events
### RevenueCollected
Emitted when revenue is withdrawn from collateral manager to self


```solidity
event RevenueCollected(address indexed token, uint256 amount);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`token`|`address`|The requested token to be withdrawn|
|`amount`|`uint256`|The amount of revenue tokens|

### WithdrawToMultisig
Emitted when revenue is sent to the multisig


```solidity
event WithdrawToMultisig(address indexed token, uint256 amount);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`token`|`address`|The requested token to be withdrawn|
|`amount`|`uint256`|The amount of revenue tokens|

### WithdrawToManager
Emitted when revenue is sent to the manager


```solidity
event WithdrawToManager(address indexed token, uint256 amount);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`token`|`address`|The requested token to be withdrawn|
|`amount`|`uint256`|The amount of revenue tokens|

### RewardSent
Emitted when revenue is sent to the staking contract as asset tokens


```solidity
event RewardSent(uint256 amount);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`amount`|`uint256`|The amount of rewarded tokens|

### MultisigUpdated
Emitted when multisig is updated


```solidity
event MultisigUpdated(address newMultisig);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newMultisig`|`address`|New multisig address|

## Errors
### InsufficientRevenue
Token had no pending revenue to collect


```solidity
error InsufficientRevenue();
```

### InvalidAmount
Invalid transfer amount


```solidity
error InvalidAmount();
```

### NonZeroAddress
Invalid zero address


```solidity
error NonZeroAddress();
```

