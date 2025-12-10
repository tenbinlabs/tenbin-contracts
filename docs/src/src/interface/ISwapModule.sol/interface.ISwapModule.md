# ISwapModule
[Git Source](https://github.com/tenbinlabs/contracts/blob/aca92cae688bdb3da3dd7de958cb87e2d6cc5d0e/src/interface/ISwapModule.sol)

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

### InvalidReceiver
Receiver is not manager


```solidity
error InvalidReceiver();
```

### InvalidRouter
Router parameter does not match swap router


```solidity
error InvalidRouter();
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

### OnlyManager
Revert if not called by the manager


```solidity
error OnlyManager();
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

