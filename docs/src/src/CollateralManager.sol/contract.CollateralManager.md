# CollateralManager
[Git Source](https://github.com/tenbinlabs/contracts/blob/aca92cae688bdb3da3dd7de958cb87e2d6cc5d0e/src/CollateralManager.sol)

**Inherits:**
[ICollateralManager](/Users/tenbin/code/contracts/docs/src/src/interface/ICollateralManager.sol/interface.ICollateralManager.md), UUPSUpgradeable, AccessControlUpgradeable, ReentrancyGuardTransient

The collateral manager holds collateral backing assets in the Tenbin protocol
The purpose of the manager is to earn yield on collateral and provide liquidity for orders
Each collateral has a respective ERC4626 vault in which assets can be deposited and withdrawn
On mint, collateral is transferred to this contract via transferFrom()
On redeem, collateral is transferred from this contract via transferFrom()
The CURATOR_ROLE manages collateral in a non-custodian manner by calling the following functions:
deposit()           -> deposit collateral into an ERC4626 vault
withdraw()          -> withdraw collateral from an ERC4626 vault
swap()              -> swap one collateral for another collateral
The COLLECTOR_ROLE collects revenue. Revenue is calculated separately from collateral.
Two functions are used to manage revenue:
getRevenue()        -> get pending revenue
withdrawRevenue()   -> withdraw revenue from this contract
The REBALANCER_ROLE is responsible for balancing on/off chain collateral, and can call the following function:
rebalance()         -> withdraw collateral to a custodian account, up to a cap
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


### COLLECTOR_ROLE
Collector role can collect revenue earned by underlying vaults


```solidity
bytes32 public constant COLLECTOR_ROLE = keccak256("COLLECTOR_ROLE")
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


### BASIS_PRECISION
Precision for basis calculations. 10,000 = 100%


```solidity
uint256 internal constant BASIS_PRECISION = 10_000
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


### pauseStatus
Pause status for this contract


```solidity
ManagerPauseStatus public pauseStatus
```


### vaults
Vault associated with a collateral token
Each collateral used by the manager must have an associated ERC4626 vault


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


### swapTolerance
Stores the allowed slippage between two tokens in basis points


```solidity
mapping(address => mapping(address => uint256)) public swapTolerance
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
When calling this function, the admin must ensure all collaterals are included in `collaterals`


```solidity
function updateController(address newController, address[] calldata collaterals)
    external
    onlyRole(DEFAULT_ADMIN_ROLE)
    nonZeroAddress(newController);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newController`|`address`|New controller address|
|`collaterals`|`address[]`|Collateral addresses for this contract|


### setSwapModule

Set a new swap module


```solidity
function setSwapModule(address newSwapModule) external onlyRole(DEFAULT_ADMIN_ROLE) nonZeroAddress(newSwapModule);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newSwapModule`|`address`|New swap module|


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


### setSwapTolerance

Set the slippage tolerance between two collateral tokens


```solidity
function setSwapTolerance(address tokenIn, address tokenOut, uint256 tolerance) external onlyRole(ADMIN_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`tokenIn`|`address`|Token to be swapped|
|`tokenOut`|`address`|Token to be returned from the swap|
|`tolerance`|`uint256`|Tolerance ratio between the tokens in bps|


### rescueEther

Rescue ether sent to this contract


```solidity
function rescueEther() external onlyRole(ADMIN_ROLE);
```

### getRevenue

Get pending revenue for a collateral type


```solidity
function getRevenue(address collateral) external view returns (uint256 revenue);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`collateral`|`address`|Get revenue for a specific collateral|


### deposit

Deposit collateral into underlying vault


```solidity
function deposit(address collateral, uint256 amount) external nonReentrant notPaused onlyRole(CURATOR_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`collateral`|`address`|Collateral used to deposit into vault|
|`amount`|`uint256`|Amount of collateral to deposit|


### withdraw

Withdraw collateral from underlying vault


```solidity
function withdraw(address collateral, uint256 amount) external nonReentrant notPaused onlyRole(CURATOR_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`collateral`|`address`|Collateral to withdraw from vault|
|`amount`|`uint256`|Amount of collateral to withdraw|


### withdrawRevenue

Withdraw revenue accumulated by underlying vault


```solidity
function withdrawRevenue(address collateral, uint256 amount)
    external
    nonReentrant
    notPaused
    onlyRole(COLLECTOR_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`collateral`|`address`|Collateral to withdraw|
|`amount`|`uint256`|Amount of collateral to withdraw|


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


### _verifySlippage

Verifies slippage tolerance before performing a swap


```solidity
function _verifySlippage(ISwapModule.SwapParameters memory params) internal view;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`params`|`ISwapModule.SwapParameters`|Swap parameters containing src token, dst token, amounts, and min return amount|


### _normalizeTo18

Normalizes a token amount to 18-decimal precision.


```solidity
function _normalizeTo18(uint256 amount, uint8 decimals) internal pure returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`amount`|`uint256`|The token amount to normalize.|
|`decimals`|`uint8`|The token's native decimal precision.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|normalizedAmount The 18-decimal equivalent of the input amount.|


### _realizeRevenue

Internal function to calculate and store new revenue for a collateral


```solidity
function _realizeRevenue(address collateral, IERC4626 vault) internal;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`collateral`|`address`|Collateral to update revenue for|
|`vault`|`IERC4626`|Collateral corresponding vault|


### _computeNewRevenue

Internal function to calculate new revenue for a collateral


```solidity
function _computeNewRevenue(address collateral, IERC4626 vault) internal view returns (uint256 revenue);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`collateral`|`address`|Collateral to compute revenue for|
|`vault`|`IERC4626`|Collateral corresponding vault|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`revenue`|`uint256`|New revenue earned by the collateral vault|


### _authorizeUpgrade

Override this function to allow only default admin role to perform upgrades


```solidity
function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newImplementation`|`address`|New implementation address|


