# ICollateralManager
[Git Source](https://github.com/tenbinlabs/contracts/blob/aca92cae688bdb3da3dd7de958cb87e2d6cc5d0e/src/interface/ICollateralManager.sol)

The collateral manager manages onchain yield and liquidity for the Tenbin protocol


## Functions
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
function deposit(address collateral, uint256 amount) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`collateral`|`address`|Collateral used to deposit into vault|
|`amount`|`uint256`|Amount of collateral to deposit|


### withdraw

Withdraw collateral from underlying vault


```solidity
function withdraw(address collateral, uint256 amount) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`collateral`|`address`|Collateral to withdraw from vault|
|`amount`|`uint256`|Amount of collateral to withdraw|


### withdrawRevenue

Withdraw revenue accumulated by underlying vault


```solidity
function withdrawRevenue(address collateral, uint256 amount) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`collateral`|`address`|Collateral to withdraw|
|`amount`|`uint256`|Amount of collateral to withdraw|


### rebalance

Allow rebalancer to withdraw collateral with limitations


```solidity
function rebalance(address collateral, uint256 amount) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`collateral`|`address`|Collateral to withdraw|
|`amount`|`uint256`|Amount of collateral to withdraw|


### swap

Swap one collateral for another


```solidity
function swap(bytes calldata params, bytes calldata data) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`params`|`bytes`|Generic swap parameters used to enforce swap constraints|
|`data`|`bytes`|Additional data passed to swap module|


## Events
### Deposit
Emitted when collateral is deposited into its underlying vault


```solidity
event Deposit(address indexed collateral, uint256 amount);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`collateral`|`address`|The collateral deposited|
|`amount`|`uint256`|Amount of collateral deposited|

### Withdraw
Emitted when collateral is withdrawn from its underlying vault


```solidity
event Withdraw(address indexed collateral, uint256 amount);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`collateral`|`address`|The collateral withdrawn|
|`amount`|`uint256`|Amount of collateral withdrawn|

### RevenueWithdraw
Emitted when revenue is withdrawn


```solidity
event RevenueWithdraw(address indexed collateral, uint256 amount);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`collateral`|`address`|The collateral withdrawn|
|`amount`|`uint256`|Amount of collateral withdrawn|

### Rebalance
Emitted when rebalancer withdraws revenue


```solidity
event Rebalance(address indexed collateral, uint256 amount);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`collateral`|`address`|The collateral withdrawn|
|`amount`|`uint256`|Amount of collateral withdrawn|

### Swap
Emitted when a swap occurs for this contract


```solidity
event Swap(address indexed srcToken, address indexed dstToken, uint256 srcAmount, uint256 dstAmount);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`srcToken`|`address`|Collateral token swapped out|
|`dstToken`|`address`|Collateral received after this swap|
|`srcAmount`|`uint256`|Amount of collateral swapped|
|`dstAmount`|`uint256`|Amount of collateral received from this swap|

### PauseStatusChanged
Emitted when the pause status is changed for this contract


```solidity
event PauseStatusChanged(ManagerPauseStatus status);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`status`|`ManagerPauseStatus`|New pause status for this contract|

### RebalanceCapChanged
Emitted when the rebalance cap is changed for a collateral


```solidity
event RebalanceCapChanged(address indexed collateral, uint256 amount);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`collateral`|`address`|Collateral for which cap has changed|
|`amount`|`uint256`|New max amount that can be withdrawn during a rebalance|

### SwapCapUpdated
Emitted when token swap cap amount gets updated


```solidity
event SwapCapUpdated(address collateral, uint256 newSwapCap);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`collateral`|`address`|Token to be capped|
|`newSwapCap`|`uint256`|Cap amount|

### SwapToleranceUpdated
Emitted when token swap tolerance amount gets updated


```solidity
event SwapToleranceUpdated(address indexed tokenIn, address indexed tokenOut, uint256 tolerance);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`tokenIn`|`address`|Token to be swapped|
|`tokenOut`|`address`|Token to be returned from the swap|
|`tolerance`|`uint256`|tolerance ratio between the tokens|

### CollateralAdded
Emitted when a new collateral token is added


```solidity
event CollateralAdded(address indexed token, address indexed vault);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`token`|`address`|Collateral token address|
|`vault`|`address`|Respective vault for the collateral token|

### CollateralRemoved
Emitted when an existing collateral token is removed


```solidity
event CollateralRemoved(address indexed token, address indexed vault);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`token`|`address`|Collateral token address|
|`vault`|`address`|Respective vault for the collateral token|

### SwapModuleUpdated
Emitted when aggregation router gets updated


```solidity
event SwapModuleUpdated(address indexed swapModule);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`swapModule`|`address`|Address of new swap module|

### ControllerUpdated
Emitted when controller gets updated


```solidity
event ControllerUpdated(address indexed controller);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`controller`|`address`|New controller address|

### LegacySharesRedeemed
Emitted when legacy shares are redeemed


```solidity
event LegacySharesRedeemed(address vault, uint256 shares);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`vault`|`address`|Vault to redeem shares for|
|`shares`|`uint256`|Amount of shares redeemed|

## Errors
### CollateralAlreadySupported
Collateral is already supported


```solidity
error CollateralAlreadySupported();
```

### CollateralNotSupported
Collateral not supported


```solidity
error CollateralNotSupported();
```

### ExceedsPendingRevenue
Withdraw amount exceeds pending revenue


```solidity
error ExceedsPendingRevenue();
```

### ExceedsRebalanceCap
Rebalance withdrawal exceeds cap


```solidity
error ExceedsRebalanceCap();
```

### FMLPause
Emergency pause


```solidity
error FMLPause();
```

### IncompatibleCollateralVault
Collateral vault not compatible with collateral token


```solidity
error IncompatibleCollateralVault();
```

### InvalidSlippage
Emitted when a swap exceeds the allowable slippage threshold.


```solidity
error InvalidSlippage();
```

### InvalidSwapAmount
Emitted when a swap amount exceeds the allowable cap threshold.


```solidity
error InvalidSwapAmount();
```

### InsufficientAmountReceived
Insufficient amount received in swap


```solidity
error InsufficientAmountReceived();
```

### NonZeroAddress
Zero address not allowed


```solidity
error NonZeroAddress();
```

### RescueEtherFailed
Emitted if rescue ether fails


```solidity
error RescueEtherFailed();
```

## Enums
### ManagerPauseStatus
Contract pause states


```solidity
enum ManagerPauseStatus {
    None,
    FMLPause
}
```

**Variants**

|Name|Description|
|----|-----------|
|`None`|Contract not paused|
|`FMLPause`|Emergency pause|

