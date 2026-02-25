# IController
[Git Source](https://github.com/tenbinlabs/contracts/blob/7874f0709e21201d251621138d90d5b61ccd404d/src/interface/IController.sol)

**Title:**
IController

The Controller handles mint and redemption orders for the Tenbin protocol.


## Functions
### asset

Get asset token this controller manages


```solidity
function asset() external view returns (address);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|Asset token address|


### custodian

Get custodian address for this controller


```solidity
function custodian() external view returns (address);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|Custodian address|


### manager

Get manager address for this controller


```solidity
function manager() external view returns (address);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|Manager address|


### hashOrder

Get the EIP712 typed data hash of an order.


```solidity
function hashOrder(Order calldata order) external view returns (bytes32 orderHash);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`order`|`Order`|Order data|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`orderHash`|`bytes32`|EIP712 typed data hash of `order`|


### verifyOrder

Verify an order signed with EIP712


```solidity
function verifyOrder(Order calldata order, Signature calldata signature)
    external
    view
    returns (address signer, bytes32 orderHash);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`order`|`Order`|Order data|
|`signature`|`Signature`|Signature of hashed order|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`signer`|`address`|Signer of this order|
|`orderHash`|`bytes32`|Order hash of verified order|


### verifyNonce

Verify a signer nonce.


```solidity
function verifyNonce(address account, uint256 nonce) external view;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`account`|`address`|to verify for|
|`nonce`|`uint256`|Nonce to check|


### mint

Mint asset tokens


```solidity
function mint(Order calldata order, Signature calldata signature) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`order`|`Order`|Order data|
|`signature`|`Signature`|Signature of hashed order|


### redeem

Redeem asset tokens


```solidity
function redeem(Order calldata order, Signature calldata signature) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`order`|`Order`|Order data|
|`signature`|`Signature`|ECDSA signature of hashed order|


## Events
### Mint
Event emitted when an asset is minted


```solidity
event Mint(
    address indexed signer,
    uint256 nonce,
    address indexed payer,
    address indexed recipient,
    address collateralToken,
    uint256 collateralAmount,
    uint256 mintAmount
);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`signer`|`address`|Signer account which signed the order|
|`nonce`|`uint256`|Nonce used by signer|
|`payer`|`address`|Payer account which provided collateral|
|`recipient`|`address`|Recipient account which received assets|
|`collateralToken`|`address`|Collateral used for this mint|
|`collateralAmount`|`uint256`|Collateral amount sent|
|`mintAmount`|`uint256`|Amount of asset tokens minted|

### Redeem
Event emitted when an asset is redeemed


```solidity
event Redeem(
    address indexed signer,
    uint256 nonce,
    address indexed payer,
    address indexed recipient,
    address collateralToken,
    uint256 collateralAmount,
    uint256 redeemAmount
);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`signer`|`address`|Signer account which signed the order|
|`nonce`|`uint256`|Nonce used by signer|
|`payer`|`address`|Payer account which provided assets|
|`recipient`|`address`|Recipient account which received collateral|
|`collateralToken`|`address`|Collateral used for this redeem|
|`collateralAmount`|`uint256`|Collateral amount received|
|`redeemAmount`|`uint256`|Amount of asset redeemed|

### MintRedeemPauseStatusChanged
Emitted when mint & redemption pause status changes


```solidity
event MintRedeemPauseStatusChanged(bool status);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`status`|`bool`|New mint and redemption pause status|

### NonceInvalidated
Emitted when payer invalidates a specific nonce


```solidity
event NonceInvalidated(address indexed payer, uint256 nonce);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`payer`|`address`|Address that invalidated the nonce|
|`nonce`|`uint256`|Nonce invalidated|

### PauseStatusChanged
Emitted when emergency pause status changes


```solidity
event PauseStatusChanged(ControllerPauseStatus status);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`status`|`ControllerPauseStatus`|New emergency pause status|

### SignerStatusChanged
Emitted when allowed signer status changes


```solidity
event SignerStatusChanged(address signer, bool status);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`signer`|`address`|Signer account|
|`status`|`bool`|Signer allowed status|

### RecipientStatusChanged
Emitted when a signer adds or removes an approved recipient


```solidity
event RecipientStatusChanged(address signer, address recipient, bool status);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`signer`|`address`|Signer which has set status for a recipient account|
|`recipient`|`address`|Account which can receive tokens during order execution|
|`status`|`bool`|Recipient status: true if a recipient can receive tokens|

### DelegateStatusChanged
Emitted when an account delegates a signer to sign orders on their behalf


```solidity
event DelegateStatusChanged(address payer, address signer, bool status);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`payer`|`address`|Account which allows signer to sign orders on its behalf|
|`signer`|`address`|Signer which can sign orders on behalf of payer|
|`status`|`bool`|Delegate status: true if a signer can use tokens from payer during order execution|

### CollateralStatusChanged
Emitted when collateral support status is updated


```solidity
event CollateralStatusChanged(address collateral, bool status);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`collateral`|`address`|New collateral account|
|`status`|`bool`|Collateral allowed status|

### CustodianUpdated
Emitted when custodian is updated


```solidity
event CustodianUpdated(address newCustodian);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newCustodian`|`address`|New custodian account|

### ManagerUpdated
Emitted when manager is updated


```solidity
event ManagerUpdated(address newManager);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newManager`|`address`|New manager account|

### RatioUpdated
Emitted when ratio is updated


```solidity
event RatioUpdated(uint256 newRatio);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newRatio`|`uint256`|New ratio amount|

### OracleToleranceUpdated
Emitted when oracle tolerance is updated


```solidity
event OracleToleranceUpdated(uint96 newTolerance);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newTolerance`|`uint96`|New tolerance amount|

### OracleAdapterUpdated
Emitted when oracle adapter is updated


```solidity
event OracleAdapterUpdated(address newAdapter);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newAdapter`|`address`|New adapter account|

## Errors
### CollateralNotSupported
Unsupported collateral type


```solidity
error CollateralNotSupported();
```

### ExceedsOracleDeltaTolerance
Order price exceeds oracle tolerance


```solidity
error ExceedsOracleDeltaTolerance();
```

### FMLPause
Emergency Pause


```solidity
error FMLPause();
```

### InvalidAssetAmount
Invalid asset amount


```solidity
error InvalidAssetAmount();
```

### InvalidCollateralAmount
Invalid collateral amount


```solidity
error InvalidCollateralAmount();
```

### InvalidCollateralDecimals
Collateral token has an invalid number of decimals


```solidity
error InvalidCollateralDecimals();
```

### InvalidERC1271Signature
Invalid ERC1271 signature


```solidity
error InvalidERC1271Signature();
```

### InvalidNonce
Invalid nonce


```solidity
error InvalidNonce();
```

### InvalidOrderType
Invalid order type


```solidity
error InvalidOrderType();
```

### InvalidRatio
Invalid ratio


```solidity
error InvalidRatio();
```

### InvalidPayer
Invalid payer account


```solidity
error InvalidPayer();
```

### InvalidRecipient
Invalid recipient account


```solidity
error InvalidRecipient();
```

### InvalidSigner
Invalid signer


```solidity
error InvalidSigner();
```

### MintRedeemPaused
Mint and Redemption Paused


```solidity
error MintRedeemPaused();
```

### NewToleranceExceedsMax
New oracle tolerance exceeds the maximum tolerance


```solidity
error NewToleranceExceedsMax();
```

### NonZeroAddress
Invalid zero address


```solidity
error NonZeroAddress();
```

### OrderExpired
Order past expiration time


```solidity
error OrderExpired();
```

### RescueEtherFailed
Emitted if rescue ether fails


```solidity
error RescueEtherFailed();
```

## Structs
### Signature
Signature data structure with support for multiple signature types


```solidity
struct Signature {
    SignatureType signature_type;
    bytes signature_bytes;
}
```

**Properties**

|Name|Type|Description|
|----|----|-----------|
|`signature_type`|`SignatureType`|Type of signature used to sign data|
|`signature_bytes`|`bytes`|Signed data|

### Order
Order data structure


```solidity
struct Order {
    OrderType order_type;
    uint256 nonce;
    uint256 expiry;
    address payer;
    address recipient;
    address collateral_token;
    uint256 collateral_amount;
    uint256 asset_amount;
}
```

**Properties**

|Name|Type|Description|
|----|----|-----------|
|`order_type`|`OrderType`|Order type|
|`nonce`|`uint256`|Signer nonce|
|`expiry`|`uint256`|Order expiration time|
|`payer`|`address`|Account to transfer tokens from|
|`recipient`|`address`|Account to transfer tokens to|
|`collateral_token`|`address`|Collateral token|
|`collateral_amount`|`uint256`|Amount of collateral|
|`asset_amount`|`uint256`|Amount of asset tokens|

### Oracle
Oracle data structure to hold oracle adapter and tolerance


```solidity
struct Oracle {
    address adapter;
    uint96 tolerance;
}
```

**Properties**

|Name|Type|Description|
|----|----|-----------|
|`adapter`|`address`|Oracle adapter used to get normalized price|
|`tolerance`|`uint96`|Percentage tolerance from oracle price. 1e18 = 100%|

## Enums
### SignatureType
Supported signature types


```solidity
enum SignatureType {
    EIP712,
    ERC1271
}
```

**Variants**

|Name|Description|
|----|-----------|
|`EIP712`|EIP712 signature|
|`ERC1271`|ERC1271 signature|

### OrderType
Supported order types


```solidity
enum OrderType {
    Mint,
    Redeem
}
```

**Variants**

|Name|Description|
|----|-----------|
|`Mint`|Mint order type|
|`Redeem`|Redemption order type|

### ControllerPauseStatus
Pause states


```solidity
enum ControllerPauseStatus {
    None,
    MintRedeemPause,
    FMLPause
}
```

**Variants**

|Name|Description|
|----|-----------|
|`None`|Contract is not in a pause state|
|`MintRedeemPause`|Contract is not in a pause state|
|`FMLPause`|Emergency pause state|

