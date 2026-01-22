# RevenueModule
[Git Source](https://github.com/tenbinlabs/monorepo/blob/282e8df48c5730face078c656f06f4082da3317a/src/RevenueModule.sol)

**Inherits:**
[IRevenueModule](/src/interface/IRevenueModule.sol/interface.IRevenueModule.md), AccessControl

**Title:**
RevenueModule

Manages revenue earned by the Tenbin protocol
Revenue is frequently used to offset the cost of off-chain hedging.
The revenue module can perform the following actions:
- Withdraw revenue from the collateral manager
- Transfer revenue back to the collateral manager
- Transfer revenue to a multisig contract
- Provide liquidity to mint new asset tokens as a reward
- Reward the staking pool with asset tokens
A keeper role is assigned by the revenue module to automate these tasks
For example, the keeper might be called 2x per day to transfer revenue back to the collateral manager, and 1x per day to reward the staking contract


## State Variables
### ADMIN_ROLE
Admin role manages delegating a signer and approving a controller to mint rewards from revenue


```solidity
bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE")
```


### REVENUE_KEEPER_ROLE
Revenue manager role can withdraw revenue and determine where to transfer revenue


```solidity
bytes32 public constant REVENUE_KEEPER_ROLE = keccak256("REVENUE_KEEPER_ROLE")
```


### staking
Address of asset staking pool


```solidity
address public immutable staking
```


### asset
Address of asset token


```solidity
address public immutable asset
```


### manager
Address of collateral manager contract


```solidity
address public immutable manager
```


### controller
Address of controller contract


```solidity
address public immutable controller
```


### multisig
Address of multisig contract


```solidity
address public immutable multisig
```


## Functions
### nonZeroAddress

Revert if zero address


```solidity
modifier nonZeroAddress(address addr) ;
```

### constructor

RevenueModule constructor


```solidity
constructor(
    address manager_,
    address staking_,
    address owner_,
    address controller_,
    address asset_,
    address multisig_
)
    nonZeroAddress(manager_)
    nonZeroAddress(staking_)
    nonZeroAddress(owner_)
    nonZeroAddress(controller_)
    nonZeroAddress(asset_)
    nonZeroAddress(multisig_);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`manager_`|`address`|Manager account|
|`staking_`|`address`|Staking contract address|
|`owner_`|`address`|Default admin for this contract|
|`controller_`|`address`|Controller contract address|
|`asset_`|`address`|Asset token contract address|
|`multisig_`|`address`||


### collect

Withdraw pending revenue from CollateralManager


```solidity
function collect(address token, uint256 amount)
    external
    override
    onlyRole(REVENUE_KEEPER_ROLE)
    nonZeroAddress(token);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`token`|`address`|Token address to withdraw revenue for|
|`amount`|`uint256`|Amount of tokens to withdraw|


### withdrawToMultisig

Transfer tokens to a multisig account


```solidity
function withdrawToMultisig(address token, uint256 amount)
    external
    override
    nonZeroAddress(token)
    onlyRole(REVENUE_KEEPER_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`token`|`address`|Token address to be withdrawn|
|`amount`|`uint256`|Amount of tokens to withdraw|


### withdrawToManager

Transfer tokens to collateral manager


```solidity
function withdrawToManager(address token, uint256 amount)
    external
    override
    onlyRole(REVENUE_KEEPER_ROLE)
    nonZeroAddress(token);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`token`|`address`|Token address to be withdrawn|
|`amount`|`uint256`|Amount of tokens to withdraw|


### reward

Transfer asset tokens to staking contract


```solidity
function reward(uint256 amount) external override onlyRole(REVENUE_KEEPER_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`amount`|`uint256`|Amount of tokens to reward|


### setControllerApproval

Approve collateral tokens to be transferred during a Mint order


```solidity
function setControllerApproval(address token, uint256 amount)
    external
    onlyRole(REVENUE_KEEPER_ROLE)
    nonZeroAddress(token);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`token`|`address`|Collateral token address to be approved|
|`amount`|`uint256`|Amount of tokens to approve|


### delegateSigner

Allow a signer in the controller to sign orders where this contract is the payer


```solidity
function delegateSigner(address signer, bool status) external onlyRole(ADMIN_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`signer`|`address`|Signer account|
|`status`|`bool`|Whether or not this signer is delegated|


### claimMorphoRewards

Claim rewards from Morpho's Universal Rewards Distributor


```solidity
function claimMorphoRewards(address distributor, address rewardToken, uint256 claimable, bytes32[] calldata proof)
    external
    onlyRole(REVENUE_KEEPER_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`distributor`|`address`|The URD contract address|
|`rewardToken`|`address`|The reward token address (e.g., MORPHO)|
|`claimable`|`uint256`|The total claimable amount from merkle tree|
|`proof`|`bytes32[]`|The merkle proof for this claim|


### _sendFunds

Helper function to handle token transfers


```solidity
function _sendFunds(address to, address token, uint256 amount) private;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`to`|`address`|Receiver of tokens|
|`token`|`address`|Token address to be sent|
|`amount`|`uint256`|Amount to be sent|


