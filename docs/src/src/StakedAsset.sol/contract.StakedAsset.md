# StakedAsset
[Git Source](https://github.com/tenbinlabs/tenbin-contracts/blob/eb2d102704c08124f1036e9b92cd46f9cf41203f/src/StakedAsset.sol)

**Inherits:**
[IStakedAsset](/src/interface/IStakedAsset.sol/interface.IStakedAsset.md), [IRestrictedRegistry](/src/interface/IRestrictedRegistry.sol/interface.IRestrictedRegistry.md), UUPSUpgradeable, ERC20PermitUpgradeable, ERC4626Upgradeable, AccessControlUpgradeable

**Title:**
StakedAsset

__/\\\\\\\\\\\\\\\__________________________/\\\____________________________
_\///////\\\/////__________________________\/\\\____________________________
_______\/\\\_______________________________\/\\\_________/\\\_______________
_______\/\\\______/\\\\\\\\___/\\/\\\\\\___\/\\\________\///___/\\/\\\\\\___
_______\/\\\____/\\\/////\\\_\/\\\////\\\__\/\\\\\\\\\___/\\\_\/\\\////\\\__
_______\/\\\___/\\\\\\\\\\\__\/\\\__\//\\\_\/\\\////\\\_\/\\\_\/\\\__\//\\\_
_______\/\\\__\//\\///////___\/\\\___\/\\\_\/\\\__\/\\\_\/\\\_\/\\\___\/\\\_
_______\/\\\___\//\\\\\\\\\\_\/\\\___\/\\\_\/\\\\\\\\\__\/\\\_\/\\\___\/\\\_
_______\///_____\//////////__\///____\///__\/////////___\///__\///____\///__

Allows staking an asset token for a staking token
Rewards can be sent to this contract to reward stakers proportionally to their stake
Includes a vesting period over which pending rewards are linearly vested
Whenever a reward is paid to the contract, the vesting period resets
Once the vesting period is set, it cannot be set below MIN_VESTING_PERIOD.
Includes a cooldown period over which a user must wait between cooldown and withdraw
When cooldownPeriod > 0, the normal withdraw() and redeem() functions will revert
Users call cooldownShares() and cooldownAssets() to initiate cooldown
Users can have multiple cooldowns at once denominated by cooldownIds[account]
Users do not earn rewards for assets during the cooldown period
Assets in cooldown are stored in a Silo contract until cooldown is complete
After a cooldown is completed, users can call unstake(id) to claim their asset tokens
The INSTANT_UNSTAKER_ROLE can unstake tokens on behalf of an account with approval
Typically the instant unstake function is used by the Controller contract to process staked asset redemptions
Instant unstaking includes an instant unstake cap which is depleted as assets are instantly unstaked
The CAP_ADJUSTER_ROLE can adjust the instant unstake cap
A restricted registry is included to comply with legal requirements
Restricted accounts can have their balances burned and underlying assets distributed to stakers
Restricted accounts:
- cannot receive asset tokens
- cannot unstake, withdraw, or redeem
- cannot transfer tokens out of the account
- can receive tokens in their account (but not transfer out)
In order to avoid a first depositor donation attack a minimum stake should be made in the same transaction as the contract deployment
This is a UUPS upgradeable contract meant to be deployed behind an ERC1967 Proxy


## Constants
### REWARDER_ROLE
Rewarder role transfers asset tokens into the contract


```solidity
bytes32 constant REWARDER_ROLE = keccak256("REWARDER_ROLE")
```


### ADMIN_ROLE
Admin role can change vesting and cooldown period


```solidity
bytes32 constant ADMIN_ROLE = keccak256("ADMIN_ROLE")
```


### RESTRICTER_ROLE
Restricter role can change restricted status of accounts


```solidity
bytes32 constant RESTRICTER_ROLE = keccak256("RESTRICTER_ROLE")
```


### INSTANT_UNSTAKER_ROLE
Instant redeemer role can redeem shares on behalf of an owner and bypass the cooldown period


```solidity
bytes32 constant INSTANT_UNSTAKER_ROLE = keccak256("INSTANT_UNSTAKER_ROLE")
```


### CAP_ADJUSTER_ROLE
Cap adjuster role can change instant redemption caps


```solidity
bytes32 constant CAP_ADJUSTER_ROLE = keccak256("CAP_ADJUSTER_ROLE")
```


### MAX_COOLDOWN_PERIOD
Max cooldown period


```solidity
uint256 public constant MAX_COOLDOWN_PERIOD = 90 days
```


### MAX_VESTING_PERIOD
Max vesting period


```solidity
uint256 public constant MAX_VESTING_PERIOD = 90 days
```


### MIN_VESTING_PERIOD
Min vesting period to prevent rounding errors when calculating rewards within 0.1%


```solidity
uint256 public constant MIN_VESTING_PERIOD = 1200 seconds
```


## State Variables
### silo
AssetSilo holds assets during cooldown


```solidity
AssetSilo public silo
```


### cooldowns
Amount of shares in cooldown for an account


```solidity
mapping(address => mapping(uint256 => Cooldown)) public cooldowns
```


### cooldownIds
Next cooldown ID for an account


```solidity
mapping(address => uint256) public cooldownIds
```


### cooldownPeriod
Cooldown period for unstaking in seconds


```solidity
uint256 public cooldownPeriod
```


### vesting
Vesting data


```solidity
Vesting public vesting
```


### isRestricted
Keep track of restricted addresses


```solidity
mapping(address => bool) public isRestricted
```


### instantUnstakeCap
Cap for instant unstaking. When an instant unstake is performed, this value is decremented


```solidity
uint256 public instantUnstakeCap
```


## Functions
### nonZeroAddress

Revert if zero address


```solidity
modifier nonZeroAddress(address addr) ;
```

### nonRestricted

Reverts if account is restricted


```solidity
modifier nonRestricted(address account) ;
```

### constructor

Disable initializers for implementation contract


```solidity
constructor() ;
```

### initialize

Initializer for this contract


```solidity
function initialize(string memory name_, string memory symbol_, address asset_, address owner_)
    external
    initializer
    nonZeroAddress(asset_)
    nonZeroAddress(owner_);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`name_`|`string`|Name of this token|
|`symbol_`|`string`|Symbol for this token|
|`asset_`|`address`|Asset to stake and reward|
|`owner_`|`address`|Default admin role for this contract|


### pendingRewards

Get pending rewards for this contract


```solidity
function pendingRewards() external view returns (uint256 amount);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`amount`|`uint256`|Pending unvested rewards|


### cooldownShares

Enter cooldown for amount of `shares`
Assets in cooldown are transferred to the silo contract and withdrawable at the end of cooldown

WARNING: Once an account enters cooldown, assets are locked and do not earn yield
until the cooldown period has passed. Once cooldown has passed, call unstake() to withdraw tokens.
The cancelCooldown() function can be used to cancel an active cooldown and mint shares from the assets in cooldown.


```solidity
function cooldownShares(uint256 shares) external nonRestricted(msg.sender) returns (uint256 assets, uint256 id);
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
function cooldownAssets(uint256 assets) external nonRestricted(msg.sender) returns (uint256 shares, uint256 id);
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
function cancelCooldown(uint256 id) external nonRestricted(msg.sender) returns (uint256 shares);
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

Unstake shares that are in cooldown


```solidity
function unstake(address receiver, uint256 id)
    external
    nonRestricted(msg.sender)
    nonRestricted(receiver)
    nonZeroAddress(receiver);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`receiver`|`address`|Account to transfer assets to|
|`id`|`uint256`||


### instantUnstake

Force withdraw assets by bypassing cooldown
If set, enforces an instant unstaking cap and charges a fee
Can only be initiated by INSTANT_UNSTAKER_ROLE


```solidity
function instantUnstake(uint256 assets, address receiver, address owner)
    external
    onlyRole(INSTANT_UNSTAKER_ROLE)
    nonRestricted(owner)
    nonRestricted(receiver)
    returns (uint256 shares);
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
function reward(uint256 assets) external onlyRole(REWARDER_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`assets`|`uint256`|Amount of asset tokens to transfer to this contract as a reward|


### setVestingPeriod

Set a new vesting period

Note: setting low vesting periods causes rounding issues
Warning: Setting a new vesting period will cause the current vesting period to reset
with the remaining rewards vested over the new vesting period


```solidity
function setVestingPeriod(uint128 newVestingPeriod) external onlyRole(ADMIN_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newVestingPeriod`|`uint128`|New vesting period|


### setCooldownPeriod

Set a new cooldown period


```solidity
function setCooldownPeriod(uint256 newCooldownPeriod) external onlyRole(ADMIN_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newCooldownPeriod`|`uint256`|New cooldown period|


### setIsRestricted

Sets or unsets an address as restricted


```solidity
function setIsRestricted(address account, bool newStatus) external onlyRole(RESTRICTER_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`account`|`address`|The address to update|
|`newStatus`|`bool`|The new restriction status|


### setInstantUnstakeCap

Set instant unstake cap


```solidity
function setInstantUnstakeCap(uint256 cap) external onlyRole(CAP_ADJUSTER_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`cap`|`uint256`|New instant unstake cap|


### burnRestricted

Burn staked assets from a restricted account
When burning restricted staked assets, the underlying asset tokens are distributed to the stakers


```solidity
function burnRestricted(address owner, bool isCooldown, uint256 id) external onlyRole(DEFAULT_ADMIN_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`owner`|`address`|Restricted account to redeem shares from|
|`isCooldown`|`bool`|Flag do specify if restricted account is in cooldown|
|`id`|`uint256`|Id of cooldown|


### deposit

Overrides the deposit function to include restricted address check.


```solidity
function deposit(uint256 assets, address receiver)
    public
    override
    nonRestricted(msg.sender)
    nonRestricted(receiver)
    returns (uint256 shares);
```

### mint

Overrides the mint function to include restricted address check


```solidity
function mint(uint256 shares, address receiver)
    public
    override
    nonRestricted(msg.sender)
    nonRestricted(receiver)
    returns (uint256 assets);
```

### decimals

Get number of decimals for this token


```solidity
function decimals() public view override(ERC4626Upgradeable, ERC20Upgradeable) returns (uint8);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint8`|Decimals for this token|


### withdraw

Withdraw function which reverts when cooldown is active

Prevent restricted accounts from initiating withdraw or receiving tokens


```solidity
function withdraw(uint256 assets, address receiver, address owner)
    public
    override
    nonRestricted(msg.sender)
    nonRestricted(receiver)
    nonRestricted(owner)
    returns (uint256);
```

### redeem

Redeem function which requires cooldown

Prevent restricted accounts from redeeming tokens or receiving assets


```solidity
function redeem(uint256 shares, address receiver, address owner)
    public
    override
    nonRestricted(msg.sender)
    nonRestricted(receiver)
    nonRestricted(owner)
    returns (uint256);
```

### totalAssets

Calculate total assets minus pending reward


```solidity
function totalAssets() public view override returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|Total assets not including pending reward|


### rescueToken

Rescue tokens sent to this contract

the receiver should be a trusted address to avoid external calls attack vectors


```solidity
function rescueToken(address token, address to) external onlyRole(ADMIN_ROLE) nonZeroAddress(to);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`token`|`address`|The address of the ERC20 token to be rescued|
|`to`|`address`|Recipient of rescued tokens|


### transfer

Override transfer function to prevent restricted accounts from transferring
Restricted accounts can receive tokens, but not transfer them out


```solidity
function transfer(address to, uint256 value)
    public
    override(IERC20, ERC20Upgradeable)
    nonRestricted(msg.sender)
    returns (bool);
```

### transferFrom

Override transferFrom function to prevent restricted accounts from transferring
Restricted accounts can receive tokens, but not transfer them out


```solidity
function transferFrom(address from, address to, uint256 value)
    public
    override(IERC20, ERC20Upgradeable)
    nonRestricted(msg.sender)
    nonRestricted(from)
    returns (bool);
```

### _pendingRewards

Calculate pending reward based on vesting time and period


```solidity
function _pendingRewards() internal view returns (uint256 pending);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`pending`|`uint256`|Pending unvested rewards|


### _updateVesting

Update vesting amount
Increases vesting by `assets` and resets vesting period


```solidity
function _updateVesting(uint256 assets) internal;
```

### _authorizeUpgrade

Override this function to allow only default admin role to perform upgrades


```solidity
function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newImplementation`|`address`|New implementation address|


