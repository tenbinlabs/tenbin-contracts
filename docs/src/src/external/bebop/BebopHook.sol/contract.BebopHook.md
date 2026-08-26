# BebopHook
[Git Source](https://github.com/tenbinlabs/tenbin-contracts/blob/51cfcc3be55c1fc66666f437e8175c7820cc2918/src/external/bebop/BebopHook.sol)

**Inherits:**
[IBebopHook](/src/external/bebop/IBebopHook.sol/interface.IBebopHook.md), Ownable2Step

**Title:**
Bebop Hook

Executes controller mint and redeem orders through the Bebop hook interface.
- Router approves exactly the filled input amount per execution (needsApproval semantics).
- Controller orders are fixed-size ⇒ partial fills are unsupported: any fill other than
100% reverts with InputAmountMismatch. Maker must quote these orders fill-or-kill.
- Rebasing input tokens are unsupported
- Redeem orders support only standard asset redemptions. Instant redemption of staked
assets is unsupported and will revert during controller validation.

https://github.com/bebop-dex/bebop-rfqa/blob/master/README.md#hooks


## Constants
### router
The Bebop router permitted to call this hook.


```solidity
address public immutable router
```


### controller
The controller used to execute mint and redeem orders.


```solidity
IController public immutable controller
```


## State Variables
### marketMaker
The market maker whose signatures are accepted through ERC-1271.


```solidity
address public marketMaker
```


## Functions
### constructor

Initializes the Bebop hook.

marketMaker_ must already be a whitelisted signer in the controller


```solidity
constructor(address router_, address marketMaker_, address controller_, address owner_) Ownable(owner_);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`router_`|`address`|The Bebop router permitted to call the hook.|
|`marketMaker_`|`address`|The market maker whose signatures are accepted.|
|`controller_`|`address`|The controller used to execute orders.|
|`owner_`|`address`|The initial contract owner.|


### onlyRouter

Restricts function execution to the configured Bebop router.


```solidity
modifier onlyRouter() ;
```

### bebopHook

Called by BebopRouter during hook execution.

Decodes the hook and issuer data, then dispatches to the corresponding
mint or redeem implementation.


```solidity
function bebopHook(address makerAddress, bytes calldata data, Swap[] calldata swaps) external override onlyRouter;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`makerAddress`|`address`| The maker that signed this hook (Hook.flags.makerAddress, could be address(0) if no signature verification). Passed by the router so the hook contract can act on behalf of a specific maker.|
|`data`|`bytes`|Arbitrary data passed through from the Hook struct.|
|`swaps`|`Swap[]`|All swap legs for this hook's maker, scaled to the filled amount.|


### setMarketMaker

Updates the market maker address allowed to interact with this hook

maker must already be a whitelisted signer in the controller

New maker MUST mark the hook as recipient in the controller


```solidity
function setMarketMaker(address maker) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`maker`|`address`|New maker address|


### rescueToken

Allows the owner to recover tokens accidentally left on the hook.


```solidity
function rescueToken(address token, address to) external onlyOwner;
```

### setDelegateStatus

Allows owner to change the delegate status for an address


```solidity
function setDelegateStatus(address maker, bool status) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`maker`|`address`|Whitelisted signer account to delegate to|
|`status`|`bool`|Status for maker signer|


### verifyHookData

Verifies the order against the hook data.


```solidity
function verifyHookData(
    HookData memory data,
    IController.Order memory order,
    Swap memory swap,
    uint256 inputAmount,
    uint256 outputAmount
) internal view;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`data`|`HookData`|Hook data|
|`order`|`IController.Order`|Order sent inside the issuer data|
|`swap`|`Swap`|Single-leg swap info|
|`inputAmount`|`uint256`|Amount of tokens taken|
|`outputAmount`|`uint256`|Amount of tokens to make|


## Events
### MarketMakerUpdated
Emitted when market maker address was updated


```solidity
event MarketMakerUpdated(address indexed maker);
```

## Errors
### InputAmountMismatch
Thrown when input and output amounts differ


```solidity
error InputAmountMismatch();
```

### InvalidAmount
Thrown when the matching swap legs produce a zero input or output amount.


```solidity
error InvalidAmount();
```

### InvalidInputToken
Thrown when hook data input token is not correct order input token


```solidity
error InvalidInputToken();
```

### InvalidMaker
Thrown when the hook is called with the wrong market maker address


```solidity
error InvalidMaker();
```

### InvalidOrder
Thrown when faulty order is sent


```solidity
error InvalidOrder();
```

### InvalidOrderType
Thrown when order type doesn't match the hook data action


```solidity
error InvalidOrderType();
```

### InvalidOutputToken
Thrown when hook data output token is not correct order output token


```solidity
error InvalidOutputToken();
```

### InvalidProducedAmount
Thrown when produced amount is not expected output amount


```solidity
error InvalidProducedAmount();
```

### InvalidSwapCount
Thrown when the hook receives more swaps than allowed.


```solidity
error InvalidSwapCount();
```

### InvalidSwapAmount
Thrown when swap amounts differ


```solidity
error InvalidSwapAmount();
```

### InvalidSwapToken
Thrown when swap token doesn't match the hook token


```solidity
error InvalidSwapToken();
```

### OnlyRouter
Thrown when a caller other than the configured Bebop router invokes the hook.


```solidity
error OnlyRouter();
```

### UnsupportedAction
Thrown when the requested hook action is not supported.


```solidity
error UnsupportedAction();
```

### NonZeroAddress
Zero address not allowed


```solidity
error NonZeroAddress();
```

## Structs
### HookData
Data supplied by the Bebop router for a hook execution.


```solidity
struct HookData {
    uint8 action;
    address inputToken;
    address outputToken;
    uint256 quoteInputAmount;
    uint256 quoteOutputAmount;
    bytes issuerData;
}
```

**Properties**

|Name|Type|Description|
|----|----|-----------|
|`action`|`uint8`|The controller order type to execute.|
|`inputToken`|`address`|The token transferred from the market maker.|
|`outputToken`|`address`|The token expected by the market maker.|
|`quoteInputAmount`|`uint256`||
|`quoteOutputAmount`|`uint256`|The quoted amount of the output token.|
|`issuerData`|`bytes`|ABI-encoded controller order and authorization data.|

### IssuerData
Controller data required to execute a mint or redeem order.


```solidity
struct IssuerData {
    IController.Order order;
    IController.Signature orderSignature;
    IController.Context context;
    IController.Signature approval;
}
```

**Properties**

|Name|Type|Description|
|----|----|-----------|
|`order`|`IController.Order`|The controller order to execute.|
|`orderSignature`|`IController.Signature`|The signature authorizing the order.|
|`context`|`IController.Context`|Additional controller order context.|
|`approval`|`IController.Signature`|The signature approving the order context.|

