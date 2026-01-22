# IStakedAsset
[Git Source](https://github.com/tenbinlabs/monorepo/blob/282e8df48c5730face078c656f06f4082da3317a/src/interface/IStakedAsset.sol)

**Title:**
IStakedAsset

Staked asset interface


## Functions
### pendingRewards

Get pending rewards for this contract


```solidity
function pendingRewards() external view returns (uint256 pending);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`pending`|`uint256`|Pending unvested token reward|


### cooldownShares

Enter cooldown for amount of `shares`
Assets in cooldown are transferred to the silo contract and withdrawable at the end of cooldown
If a cooldown already exists, the cooldown asset amount is increased and cooldown resets

WARNING: Once an account enters cooldown, assets are locked and do not earn yield
until the cooldown period has passed. Once cooldown has passed, call unstake() to withdraw tokens.


```solidity
function cooldownShares(address owner, uint256 shares) external returns (uint256 assets);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`owner`|`address`||
|`shares`|`uint256`|Amount of shares to enter cooldown|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`assets`|`uint256`|Amount of assets withdrawn for cooldown|


### cooldownAssets

Enter cooldown for amount of `amount`
Assets in cooldown are transferred the silo contract and withdrawable at the end of cooldown
If a cooldown already exists, the cooldown asset amount is increased and cooldown resets

WARNING: Once an account enters cooldown, assets are locked and do not earn yield
until the cooldown period has passed. Once cooldown has passed, call unstake() to withdraw tokens.


```solidity
function cooldownAssets(address owner, uint256 assets) external returns (uint256 shares);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`owner`|`address`||
|`assets`|`uint256`|Amount of asset tokens to enter cooldown|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`shares`|`uint256`|Amount of shares redeemed for cooldown|


### unstake

Unstake all assets that are in cooldown


```solidity
function unstake(address to) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`to`|`address`|Account to receive assets|


### reward

Adds new rewards to the contract and extends vesting period

WARNING: This resets the vesting end time to block.timestamp + vesting.period,
which can delay distribution of previously pending rewards


```solidity
function reward(uint256 assets) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`assets`|`uint256`|Amount of asset tokens to transfer to this contract as a reward|


## Events
### RewardsReceived
Emitted when new rewards are received by this contract


```solidity
event RewardsReceived(uint256 assets);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`assets`|`uint256`|Amount of asset tokens rewarded|

### VestingStarted
Emitted when a linear vesting period starts for this contract


```solidity
event VestingStarted(uint256 total, uint256 end);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`total`|`uint256`|Total assets to vest|
|`end`|`uint256`|Timestamp at which vesting is completed|

### CooldownStarted
Emitted when an account enters cooldown for `amount`


```solidity
event CooldownStarted(address indexed account, uint256 assets);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`account`|`address`|Account which entered cooldown|
|`assets`|`uint256`|Amount of asset tokens to cooldown|

### Unstake
Emitted when `from` unstakes and transfers `amount` to `to`


```solidity
event Unstake(address indexed from, address to, uint256 assets);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`from`|`address`|Account which is unstaking|
|`to`|`address`|Account to receive assets|
|`assets`|`uint256`|Amount of assets transferred|

### CooldownCancelled
Emitted when an account cancels a cooldown


```solidity
event CooldownCancelled(address indexed account, uint256 assets);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`account`|`address`|Account which cancelled cooldown|
|`assets`|`uint256`|Amount of assets returned to the staking pool|

### VestingPeriodUpdated
Emitted when the vesting period gets updated


```solidity
event VestingPeriodUpdated(uint128 newVestingPeriod);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newVestingPeriod`|`uint128`|New vesting period|

### CooldownPeriodUpdated
Emitted when the cooldown period gets updated


```solidity
event CooldownPeriodUpdated(uint256 newCooldownPeriod);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newCooldownPeriod`|`uint256`|New cooldown period|

## Errors
### CooldownExceededMaxRedeem
Cannot withdraw more than max redeem


```solidity
error CooldownExceededMaxRedeem();
```

### CooldownExceededMaxWithdraw
Cannot withdraw more than max withdraw


```solidity
error CooldownExceededMaxWithdraw();
```

### CooldownInProgress
Cooldown has not completed


```solidity
error CooldownInProgress();
```

### ExceedsMaxCooldownPeriod
Max cooldown period exceeded


```solidity
error ExceedsMaxCooldownPeriod();
```

### ExceedsMaxVestingPeriod
Max vesting period exceeded


```solidity
error ExceedsMaxVestingPeriod();
```

### InvalidCooldownAmount
Cannot cooldown zero assets or shares


```solidity
error InvalidCooldownAmount();
```

### InvalidRescueToken
Cannot rescue asset token from staking contract


```solidity
error InvalidRescueToken();
```

### NonRestrictedAccount
Only restricted account


```solidity
error NonRestrictedAccount();
```

### NonZeroAddress
Only zero address


```solidity
error NonZeroAddress();
```

### RequiresCooldown
Redeem and withdrawal require cooldown


```solidity
error RequiresCooldown();
```

### SubceedsMinVestingPeriod
Min cooldown period subceeded


```solidity
error SubceedsMinVestingPeriod();
```

## Structs
### Vesting
Vesting data


```solidity
struct Vesting {
    uint128 period;
    uint128 end;
    uint256 assets;
}
```

**Properties**

|Name|Type|Description|
|----|----|-----------|
|`period`|`uint128`|Vesting period in seconds|
|`end`|`uint128`|Timestamp at which vesting ends|
|`assets`|`uint256`|Amount of assets vesting|

### Cooldown
Cooldown data in a packed struct


```solidity
struct Cooldown {
    uint160 assets;
    uint96 end;
}
```

**Properties**

|Name|Type|Description|
|----|----|-----------|
|`assets`|`uint160`|Amount of assets in cooldown|
|`end`|`uint96`|Timestamp at which cooldown is completed|

