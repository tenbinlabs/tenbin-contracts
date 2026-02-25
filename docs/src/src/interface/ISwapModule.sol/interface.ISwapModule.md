# ISwapModule
[Git Source](https://github.com/tenbinlabs/contracts/blob/34d0d98c6959c0c67cf21488bdfb4b79f4ce3f2e/src/interface/ISwapModule.sol)

**Title:**
Swap Module

The Swap Module is responsible for handling swaps using external protocols
This contract is permissioned so only a manager can call the swap function


## Functions
### swap

Parse swap data from manager and execute swap


```solidity
function swap(bytes calldata parameters, bytes calldata data) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`parameters`|`bytes`|Generic swap parameters|
|`data`|`bytes`|Additional swap data|


## Errors
### InsufficientReturnAmount
Swap returned insufficient amount out


```solidity
error InsufficientReturnAmount();
```

### InvalidAmount
Amount does not match parameters


```solidity
error InvalidAmount();
```

### InvalidDstReceiver
Dst receiver is not manager


```solidity
error InvalidDstReceiver();
```

### InvalidDstToken
Destination token does not match parameters


```solidity
error InvalidDstToken();
```

### InvalidMinReturnAmount
Return amount does not match parameters


```solidity
error InvalidMinReturnAmount();
```

### InvalidRouter
Router parameter does not match swap router


```solidity
error InvalidRouter();
```

### InvalidSrcReceiver
Src receiver is not executor or router


```solidity
error InvalidSrcReceiver();
```

### InvalidSrcToken
Source token does not match parameters


```solidity
error InvalidSrcToken();
```

### NonZeroAddress
Revert if zero address


```solidity
error NonZeroAddress();
```

### OnlyAdmin
Revert if not called by admin


```solidity
error OnlyAdmin();
```

### OnlyManager
Revert if not called by the manager


```solidity
error OnlyManager();
```

### PartialFillNotAllowed
The swap description cannot include the partial fill flag


```solidity
error PartialFillNotAllowed();
```

### SwapTypeNotSupported
Swap type is not supported


```solidity
error SwapTypeNotSupported();
```

## Structs
### SwapParameters
Generic swap data for performing swaps with the swap module


```solidity
struct SwapParameters {
    uint96 swapType;
    address router;
    address srcToken;
    address dstToken;
    uint256 amount;
    uint256 minReturnAmount;
}
```

**Properties**

|Name|Type|Description|
|----|----|-----------|
|`swapType`|`uint96`|Type of swap to execute|
|`router`|`address`||
|`srcToken`|`address`|Token to send|
|`dstToken`|`address`|Token to receive|
|`amount`|`uint256`|Amount to swap|
|`minReturnAmount`|`uint256`|Minimum amount out|

## Enums
### SwapType
Swap types for this contracts


```solidity
enum SwapType {
    OneInch
}
```

**Variants**

|Name|Description|
|----|-----------|
|`OneInch`||

