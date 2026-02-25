# StakedAsset
[Git Source](https://github.com/tenbinlabs/contracts/blob/7874f0709e21201d251621138d90d5b61ccd404d/src/StakedAsset.sol)

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
Includes a cooldown period over which a user must wait between cooldown and withdrawing
When cooldownPeriod > 0, the normal withdraw() and redeem() functions will revert
Users call cooldownShares() and cooldownAssets() to initiate cooldown
If a cooldown already exists for a user, initiating cooldown again with additional assets will reset the cooldown time
Users do not earn rewards for assets during the cooldown period
Assets in cooldown are stored in a Silo contract until cooldown is complete
After the cooldown is completed, users can call unstake() to claim their asset tokens
In order to avoid a first depositor donation attack a minimum stake should be made in the same transaction as the contract deployment
This is a UUPS upgradeable contract meant to be deployed behind an ERC1967 Proxy


## State Variables
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


### silo
AssetSilo holds assets during cooldown


```solidity
AssetSilo public silo
```


### cooldowns
Amount of shares in cooldown for an account


```solidity
mapping(address => Cooldown) public cooldowns
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
If a cooldown already exists, the cooldown asset amount is increased and cooldown resets

WARNING: Once an account enters cooldown, assets are locked and do not earn yield
until the cooldown period has passed. Once cooldown has passed, call unstake() to withdraw tokens.


```solidity
function cooldownShares(address owner, uint256 shares)
    external
    nonRestricted(msg.sender)
    nonRestricted(owner)
    returns (uint256 assets);
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
function cooldownAssets(address owner, uint256 assets)
    external
    nonRestricted(msg.sender)
    nonRestricted(owner)
    returns (uint256 shares);
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

Unstake shares that are in cooldown


```solidity
function unstake(address to) external nonRestricted(msg.sender) nonRestricted(to) nonZeroAddress(to);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`to`|`address`|Account to transfer assets to|


### cancelCooldown

Cancel a cooldown for an account

This will mint new shares using assets in the silo
An account can only cancel its entire cooldown amount


```solidity
function cancelCooldown() external nonRestricted(msg.sender);
```

### reward

Adds new rewards to the contract and extends vesting period

WARNING: This resets the vesting end time to block.timestamp + vesting.period,
which can delay distribution of previously pending rewards


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


### transferRestrictedAssets

Withdraw assets from a restricted account.
Without the ability to redeem frozen shares, a portion of rewards will be stuck in the contract
Always redeems the full balance of the restricted account


```solidity
function transferRestrictedAssets(address from, address to)
    external
    nonZeroAddress(to)
    onlyRole(DEFAULT_ADMIN_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`from`|`address`|Restricted account to redeem shares from|
|`to`|`address`|Account to transfer assets to|


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


```solidity
function transfer(address to, uint256 value)
    public
    override(IERC20, ERC20Upgradeable)
    nonRestricted(msg.sender)
    nonRestricted(to)
    returns (bool);
```

### transferFrom


```solidity
function transferFrom(address from, address to, uint256 value)
    public
    override(IERC20, ERC20Upgradeable)
    nonRestricted(from)
    nonRestricted(to)
    nonRestricted(msg.sender)
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


### _authorizeUpgrade

Override this function to allow only default admin role to perform upgrades


```solidity
function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newImplementation`|`address`|New implementation address|


