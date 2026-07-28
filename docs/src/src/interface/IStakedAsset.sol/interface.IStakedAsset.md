# IStakedAsset
[Git Source](https://github.com/tenbinlabs/tenbin-contracts/blob/64004be494549e5de52bb55a6490bd85d73a4f57/src/interface/IStakedAsset.sol)

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

WARNING: Once an account enters cooldown, assets are locked and do not earn yield
until the cooldown period has passed. Once cooldown has passed, call unstake() to withdraw tokens.
The cancelCooldown() function can be used to cancel an active cooldown and mint shares from the assets in cooldown.


```solidity
function cooldownShares(uint256 shares) external returns (uint256 assets, uint256 id);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`shares`|`uint256`|Amount of shares to enter cooldown|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`assets`|`uint256`|Amount of assets withdrawn for cooldown|
|`id`|`uint256`|Owner unique identifier for this cooldown|


### cooldownAssets

Enter cooldown for amount of `amount`
Assets in cooldown are transferred the silo contract and withdrawable at the end of cooldown

WARNING: Once an account enters cooldown, assets are locked and do not earn yield
until the cooldown period has passed. Once cooldown has passed, call unstake() to withdraw tokens.
The cancelCooldown() function can be used to cancel an active cooldown and mint shares from the assets in cooldown.


```solidity
function cooldownAssets(uint256 assets) external returns (uint256 shares, uint256 id);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`assets`|`uint256`|Amount of asset tokens to enter cooldown|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`shares`|`uint256`|Amount of shares redeemed for cooldown|
|`id`|`uint256`|Owner unique identifier for this cooldown|


### cancelCooldown

Cancel a cooldown for an account

This will mint new shares using assets in the silo


```solidity
function cancelCooldown(uint256 id) external returns (uint256 shares);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`id`|`uint256`|Owner unique identifier for this cooldown|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`shares`|`uint256`|Amount of shares minted to `owner` when cancelling cooldown|


### unstake

Unstake assets in cooldown for a specific ID


```solidity
function unstake(address to, uint256 id) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`to`|`address`|Account to receive assets|
|`id`|`uint256`|Unique identifier for account in cooldown|


### instantUnstake

Force withdraw assets by bypassing cooldown
If set, enforces an instant unstaking cap and charges a fee
Can only be initiated by INSTANT_UNSTAKER_ROLE


```solidity
function instantUnstake(uint256 assets, address receiver, address owner) external returns (uint256 shares);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`assets`|`uint256`|Amount of assets to withdraw|
|`receiver`|`address`|Account to receive assets|
|`owner`|`address`|Account which hold staked assets|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`shares`|`uint256`|Shares redeemed by this function|


### reward

Adds new rewards to the contract and extends vesting period

WARNING: This resets the vesting end time to block.timestamp + vesting.period,
which can delay distribution of previously pending rewards.
Rewarding the contract excessively and with low reward amounts can cause vesting to reset and extend currently vesting rewards.
Rewards should be distributed infrequently (once per 1-3 days) and in consistent amounts to ensure smooth vesting.


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
event CooldownStarted(address indexed owner, uint256 assets, uint256 shares, uint256 id, uint256 cooldownEnd);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`owner`|`address`|Account which entered cooldown|
|`assets`|`uint256`|Amount of asset tokens to cooldown|
|`shares`|`uint256`|Amount of shares redeemed to begin cooldown|
|`id`|`uint256`|Owner unique identifier for cooldown|
|`cooldownEnd`|`uint256`|Timestamp at which assets can be unstaked|

### Unstake
Emitted when `from` unstakes and transfers `amount` to `to`


```solidity
event Unstake(address indexed owner, address receiver, uint256 assets, uint256 id);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`owner`|`address`|Account which is unstaking assets|
|`receiver`|`address`|Account to receive assets|
|`assets`|`uint256`|Amount of assets transferred|
|`id`|`uint256`|Owner unique identifier for this cooldown|

### InstantUnstake
Emitted when `from` unstakes and transfers `amount` to `to`


```solidity
event InstantUnstake(address indexed owner, address receiver, uint256 assets, uint256 shares);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`owner`|`address`|Account which is unstaking assets|
|`receiver`|`address`|Account to receive assets|
|`assets`|`uint256`|Amount of assets transferred|
|`shares`|`uint256`|Amount of shares redeemed|

### CooldownCancelled
Emitted when an account cancels a cooldown and recevies newly minted shares


```solidity
event CooldownCancelled(address indexed owner, uint256 assets, uint256 shares, uint256 id);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`owner`|`address`|Account which cancelled cooldown|
|`assets`|`uint256`|Amount of assets returned to the staking pool|
|`shares`|`uint256`|Amount of new shares minted for owner|
|`id`|`uint256`|Owner unique identifier for the cooldown which was cancelled|

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

### InstantUnstakeCapChanged
Emitted when the instant unstake cap is updated


```solidity
event InstantUnstakeCapChanged(uint256 newInstantUnstakeCap);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newInstantUnstakeCap`|`uint256`|New instant unstake cap|

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

### ExceedsInstantUnstakeCap
Instant redeem amount exceeds cap


```solidity
error ExceedsInstantUnstakeCap();
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

### InvalidRewardAmount
Cannot reward zero assets


```solidity
error InvalidRewardAmount();
```

### NonexistentCooldown
Cooldown does not exist for this account and ID


```solidity
error NonexistentCooldown();
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

### ZeroCooldownAssets
Cooldown has already been unstaked or does not exist


```solidity
error ZeroCooldownAssets();
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

