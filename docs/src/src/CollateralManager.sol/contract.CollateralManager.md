# CollateralManager
[Git Source](https://github.com/tenbinlabs/contracts/blob/34d0d98c6959c0c67cf21488bdfb4b79f4ce3f2e/src/CollateralManager.sol)

**Inherits:**
[ICollateralManager](/src/interface/ICollateralManager.sol/interface.ICollateralManager.md), UUPSUpgradeable, AccessControlUpgradeable, ReentrancyGuardTransient

**Title:**
Collateral Manager

The collateral manager holds collateral backing assets in the Tenbin protocol
The purpose of the manager is to earn yield on collateral and provide liquidity for orders
Each collateral has a respective ERC4626 vault in which assets can be deposited and withdrawn
On mint, collateral is transferred to this contract via transferFrom()
On redeem, collateral is transferred from this contract via transferFrom()
The CURATOR_ROLE manages collateral in a non-custodian manner by calling the following functions:
deposit()           -> deposit collateral into an ERC4626 vault
withdraw()          -> withdraw collateral from an ERC4626 vault
swap()              -> swap one collateral for another collateral
Two functions are used to manage revenue:
getRevenue()        -> get pending revenue
withdrawRevenue()   -> withdraw revenue from this contract
The REBALANCER_ROLE is responsible for balancing on/off chain collateral, and can call the following function:
rebalance()         -> withdraw collateral to a custodian account, up to a cap
convertRevenue()    -> convert revenue to collateral, effectively giving up revenue
This is a UUPS upgradeable contract meant to be deployed behind an ERC1967 Proxy


## State Variables
### ADMIN_ROLE
Admin role can add new collateral types


```solidity
bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE")
```


### CURATOR_ROLE
Manager role can call deposit, withdraw, and swap functions


```solidity
bytes32 public constant CURATOR_ROLE = keccak256("CURATOR_ROLE")
```


### REBALANCER_ROLE
Rebalancer role can withdraw collateral with cap restrictions


```solidity
bytes32 public constant REBALANCER_ROLE = keccak256("REBALANCER_ROLE")
```


### GATEKEEPER_ROLE
Gatekeeper role can pause and unpause this contract


```solidity
bytes32 public constant GATEKEEPER_ROLE = keccak256("GATEKEEPER_ROLE")
```


### CAP_ADJUSTER_ROLE

```solidity
bytes32 public constant CAP_ADJUSTER_ROLE = keccak256("CAP_ADJUSTER_ROLE")
```


### controller
Controller associated with this contract


```solidity
address public controller
```


### swapModule
Module for performing collateral swaps for this contract


```solidity
address public swapModule
```


### revenueModule
Responsible for handling revenue and distribution


```solidity
address public revenueModule
```


### pauseStatus
Pause status for this contract


```solidity
ManagerPauseStatus public pauseStatus
```


### vaults
Vault associated with a collateral token
Each collateral used by the manager MUST have an associated ERC4626 vault


```solidity
mapping(address => IERC4626) public vaults
```


### pendingRevenue
Pending revenue for a collateral token


```solidity
mapping(address => uint256) public pendingRevenue
```


### lastTotalAssets
Last total amount of collateral tokens in an underlying vault


```solidity
mapping(address => uint256) public lastTotalAssets
```


### rebalanceCap
Maximum amount the rebalancer can withdraw per collateral


```solidity
mapping(address => uint256) public rebalanceCap
```


### swapCap
The swap cap for a specific token. When swapping collateral, the cap is decreased


```solidity
mapping(address => uint256) public swapCap
```


### minSwapPrice
Represents the min token amount out expected per token in

minSwapPrice[srcToken][dstToken]
srcToken => dstToken => amount
ex: minSwapPrice[dai][usdc] = 0.999e6
ex: minSwapPrice[usdc][dai] = 0.999e18


```solidity
mapping(address => mapping(address => uint256)) public minSwapPrice
```


### collaterals
Stores supported collateral addresses


```solidity
EnumerableSet.AddressSet internal collaterals
```


## Functions
### nonZeroAddress

Revert if zero address


```solidity
modifier nonZeroAddress(address addr) ;
```

### notPaused

Revert if contract is paused


```solidity
modifier notPaused() ;
```

### onlyRevenueModule

Revert if caller is not revenue module


```solidity
modifier onlyRevenueModule() ;
```

### constructor

Disable initializers for implementation contract


```solidity
constructor() ;
```

### initialize

Initializer for this contract


```solidity
function initialize(address controller_, address owner_) external initializer nonZeroAddress(controller_);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`controller_`|`address`|Controller for this contract|
|`owner_`|`address`|Initial owner for default admin role|


### addCollateral

Add collateral support with an underlying vault


```solidity
function addCollateral(address collateral, address vault)
    external
    nonReentrant
    onlyRole(DEFAULT_ADMIN_ROLE)
    nonZeroAddress(collateral)
    nonZeroAddress(vault);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`collateral`|`address`|Collateral to add support for|
|`vault`|`address`|Vault for this collateral|


### removeCollateral

Function to remove support for a collateral vault
This is an emergency function is used in case of vault malfunction
This function gives up any pending revenue that might have been earned for this collateral


```solidity
function removeCollateral(address collateral) external onlyRole(DEFAULT_ADMIN_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`collateral`|`address`|Collateral to remove|


### redeemLegacyShares

Function to force redeem shares of a legacy vault
This is an emergency function used in case of vault malfunction


```solidity
function redeemLegacyShares(IERC4626 vault, uint256 shares) external nonReentrant onlyRole(DEFAULT_ADMIN_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`vault`|`IERC4626`|Vault to redeem shares for|
|`shares`|`uint256`|Amount of shares to redeem|


### updateController

Set a new controller, remove old approvals, and set new approvals


```solidity
function updateController(address newController)
    external
    onlyRole(DEFAULT_ADMIN_ROLE)
    nonZeroAddress(newController);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newController`|`address`|New controller address|


### setSwapModule

Set a new swap module


```solidity
function setSwapModule(address newSwapModule) external onlyRole(DEFAULT_ADMIN_ROLE) nonZeroAddress(newSwapModule);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newSwapModule`|`address`|New swap module|


### setRevenueModule

Set a new revenue module


```solidity
function setRevenueModule(address newRevenueModule)
    external
    onlyRole(DEFAULT_ADMIN_ROLE)
    nonZeroAddress(newRevenueModule);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newRevenueModule`|`address`|New swap module|


### setPauseStatus

Gatekeeper role can set pause status


```solidity
function setPauseStatus(ManagerPauseStatus status) external onlyRole(GATEKEEPER_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`status`|`ManagerPauseStatus`|New pause status|


### setRebalanceCap

Set the maximum amount of collateral that can be withdrawn by rebalancer


```solidity
function setRebalanceCap(address collateral, uint256 amount) external onlyRole(CAP_ADJUSTER_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`collateral`|`address`|Collateral to set a new cap for|
|`amount`|`uint256`|Maximum amount rebalancer can withdraw|


### setSwapCap

Set the swap cap for a collateral token
When swapping a collateral, the cap will be decreased
If attempting to perform a swap higher than the swap cap, the swap will fail


```solidity
function setSwapCap(address collateral, uint256 newSwapCap) external onlyRole(CAP_ADJUSTER_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`collateral`|`address`|Collateral token to set swap cap for|
|`newSwapCap`|`uint256`|New swap cap|


### setMinSwapPrice

Set the minimum amount of tokens out per token in when performing a swap


```solidity
function setMinSwapPrice(address srcToken, address dstToken, uint256 minAmount)
    external
    onlyRole(CAP_ADJUSTER_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`srcToken`|`address`|Token to be swapped out|
|`dstToken`|`address`|Token to be returned from the swap|
|`minAmount`|`uint256`|Amount of tokens out per token in|


### rescueEther

Rescue ether sent to this contract


```solidity
function rescueEther() external onlyRole(ADMIN_ROLE);
```

### rescueToken

Rescue non-collateral and non-vault tokens sent to this contract

The receiver should be a trusted address to avoid external calls attack vectors


```solidity
function rescueToken(address token, address to) external onlyRole(DEFAULT_ADMIN_ROLE) nonZeroAddress(to);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`token`|`address`|The address of the ERC20 token to be rescued|
|`to`|`address`|Recipient of rescued tokens|


### getRevenue

Get pending revenue for a collateral type


```solidity
function getRevenue(address collateral) external view returns (uint256 revenue);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`collateral`|`address`|Get revenue for a specific collateral|


### getVaultAssets

Get vault total assets for a collateral


```solidity
function getVaultAssets(address collateral) external view returns (uint256 assets);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`collateral`|`address`|Collateral to get vault assets for|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`assets`|`uint256`|Total asset value of vault for a collateral|


### deposit

Deposit collateral into underlying vault


```solidity
function deposit(address collateral, uint256 amount, uint256 minShares)
    external
    nonReentrant
    notPaused
    onlyRole(CURATOR_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`collateral`|`address`|Collateral used to deposit into vault|
|`amount`|`uint256`|Amount of collateral to deposit|
|`minShares`|`uint256`|Minimum number of shares to receive|


### withdraw

Withdraw collateral from underlying vault


```solidity
function withdraw(address collateral, uint256 amount, uint256 maxShares)
    external
    nonReentrant
    notPaused
    onlyRole(CURATOR_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`collateral`|`address`|Collateral to withdraw from vault|
|`amount`|`uint256`|Amount of collateral to withdraw|
|`maxShares`|`uint256`|Maximum number of shares to redeem|


### withdrawRevenue

Withdraw revenue accumulated by underlying vault


```solidity
function withdrawRevenue(address collateral, uint256 amount) external nonReentrant notPaused onlyRevenueModule;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`collateral`|`address`|Collateral to withdraw|
|`amount`|`uint256`|Amount of collateral to withdraw|


### convertRevenue

ICollateralManager


```solidity
function convertRevenue(address collateral, uint256 amount) external notPaused onlyRole(REBALANCER_ROLE);
```

### rebalance

Allow rebalancer to withdraw collateral with limitations


```solidity
function rebalance(address collateral, uint256 amount) external notPaused onlyRole(REBALANCER_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`collateral`|`address`|Collateral to withdraw|
|`amount`|`uint256`|Amount of collateral to withdraw|


### swap

Swap one collateral for another


```solidity
function swap(bytes calldata parameters, bytes calldata data)
    external
    nonReentrant
    notPaused
    onlyRole(CURATOR_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`parameters`|`bytes`||
|`data`|`bytes`|Additional data passed to swap module|


### claimMorphoRewards

Claim rewards from Morpho's Universal Rewards Distributor


```solidity
function claimMorphoRewards(address distributor, address reward, uint256 claimable, bytes32[] calldata proof)
    external
    nonReentrant
    onlyRevenueModule;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`distributor`|`address`|The URD contract address|
|`reward`|`address`|The reward token address (e.g., MORPHO)|
|`claimable`|`uint256`|The total claimable amount from merkle tree|
|`proof`|`bytes32[]`|The merkle proof for this claim|


### _totalAssets

Internal function to calculate total assets for a vault based on balance


```solidity
function _totalAssets(IERC4626 vault) internal view returns (uint256 totalAssets);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`vault`|`IERC4626`|Vault to calculate total assets for|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`totalAssets`|`uint256`|Total assets for `vault`|


### _getRevenue

Internal function to get current total revenue
If a loss is incurred, it will be subtracted from the revenue or zeroed out


```solidity
function _getRevenue(address collateral, IERC4626 vault) internal view returns (uint256 revenue);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`collateral`|`address`|Collateral to get revenue for|
|`vault`|`IERC4626`|Collateral corresponding vault|


### _authorizeUpgrade

Override this function to allow only default admin role to perform upgrades


```solidity
function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newImplementation`|`address`|New implementation address|


