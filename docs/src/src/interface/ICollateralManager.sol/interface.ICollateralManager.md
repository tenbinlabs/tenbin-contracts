# ICollateralManager
[Git Source](https://github.com/tenbinlabs/monorepo/blob/282e8df48c5730face078c656f06f4082da3317a/src/interface/ICollateralManager.sol)

**Title:**
ICollateralManager

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
function deposit(address collateral, uint256 amount, uint256 minShares) external;
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
function withdraw(address collateral, uint256 amount, uint256 maxShares) external;
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
function withdrawRevenue(address collateral, uint256 amount) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`collateral`|`address`|Collateral to withdraw|
|`amount`|`uint256`|Amount of collateral to withdraw|


### convertRevenue

Convert revenue to collateral by declining to take revenue
Used as an accounting method to "realize" revenue and offset operational costs


```solidity
function convertRevenue(address collateral, uint256 amount) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`collateral`|`address`|Collateral token to convert|
|`amount`|`uint256`|Amount of revenue to convert|


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


### claimMorphoRewards

Claim rewards from Morpho's Universal Rewards Distributor


```solidity
function claimMorphoRewards(address distributor, address reward, uint256 claimable, bytes32[] calldata proof)
    external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`distributor`|`address`|The URD contract address|
|`reward`|`address`|The reward token address (e.g., MORPHO)|
|`claimable`|`uint256`|The total claimable amount from merkle tree|
|`proof`|`bytes32[]`|The merkle proof for this claim|


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

### MinSwapPriceUpdated
Emitted when minimum swap price is updated for a pair of tokens


```solidity
event MinSwapPriceUpdated(address srcToken, address dstToken, uint256 minAmount);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`srcToken`|`address`|Token to be swapped|
|`dstToken`|`address`|Token to be returned from the swap|
|`minAmount`|`uint256`|Minimum amount per token in|

### CollateralAdded
Emitted when a new collateral token is added


```solidity
event CollateralAdded(address token, address vault);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`token`|`address`|Collateral token address|
|`vault`|`address`|Respective vault for the collateral token|

### CollateralRemoved
Emitted when an existing collateral token is removed


```solidity
event CollateralRemoved(address token, address vault);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`token`|`address`|Collateral token address|
|`vault`|`address`|Respective vault for the collateral token|

### RevenueModuleUpdated
Emitted when revenue module gets updated


```solidity
event RevenueModuleUpdated(address newRevenueModule);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newRevenueModule`|`address`|Address of new revenue module|

### SwapModuleUpdated
Emitted when aggregation router gets updated


```solidity
event SwapModuleUpdated(address swapModule);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`swapModule`|`address`|Address of new swap module|

### ControllerUpdated
Emitted when controller gets updated


```solidity
event ControllerUpdated(address controller);
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

### RevenueConverted
Emitted when revenue is converted to collateral


```solidity
event RevenueConverted(address collateral, uint256 amount);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`collateral`|`address`|Collateral token to convert|
|`amount`|`uint256`|Amount of revenue to convert|

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

### ExcessiveSharesRedeemed
Excessive number of shares redeemed during a withdrawal


```solidity
error ExcessiveSharesRedeemed();
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

### InvalidRescueToken
Cannot rescue collateral token or vault token


```solidity
error InvalidRescueToken();
```

### InsufficientAmountReceived
Insufficient amount received in swap


```solidity
error InsufficientAmountReceived();
```

### InsufficientSharesReceived
Insufficient shares received during a vault deposit


```solidity
error InsufficientSharesReceived();
```

### InsufficientSwapPrice
Emitted when a swap amount out is insufficient given price thresholds


```solidity
error InsufficientSwapPrice();
```

### NonZeroAddress
Zero address not allowed


```solidity
error NonZeroAddress();
```

### OnlyRevenueModule
Emitted when caller is not revenue module


```solidity
error OnlyRevenueModule();
```

### RescueEtherFailed
Emitted if rescue ether fails


```solidity
error RescueEtherFailed();
```

### SwapCapExceededDst
Emitted if swap cap exceeded for dst token


```solidity
error SwapCapExceededDst();
```

### SwapCapExceededSrc
Emitted if swap cap exceeded for src token


```solidity
error SwapCapExceededSrc();
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

