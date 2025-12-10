# IRevenueModule
[Git Source](https://github.com/tenbinlabs/contracts/blob/aca92cae688bdb3da3dd7de958cb87e2d6cc5d0e/src/interface/IRevenueModule.sol)

The RevenueModule manages revenue in the Tenbin protocol.


## Functions
### pull

Withdraw total pending revenue from collateral manager


```solidity
function pull(address token) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`token`|`address`|Token address to be checked for pending revenue|


### withdrawToMultisig

Transfer tokens to an multisig account (multisig)


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


### increaseControllerApproval

Approve collateral tokens to be transferred during a Mint order


```solidity
function increaseControllerApproval(address token, uint256 amount) external;
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
### RevenuePulled
Emitted when revenue is withdrawn from collateral manager to self


```solidity
event RevenuePulled(address indexed token, uint256 amount);
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
Emitted when revenue is sent to the staking contract


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
event MultisigUpdated(address indexed newMultisig);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newMultisig`|`address`|New multisig address|

## Errors
### InsufficientRevenue
Token had no pending revenue to pull


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

