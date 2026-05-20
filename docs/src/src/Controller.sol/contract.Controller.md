# Controller
[Git Source](https://github.com/tenbinlabs/tenbin-contracts/blob/14e4f5c2d1208a42b40e6ca6182f36f84dc88dd9/src/Controller.sol)

**Inherits:**
[IController](/src/interface/IController.sol/interface.IController.md), [IRestrictedRegistry](/src/interface/IRestrictedRegistry.sol/interface.IRestrictedRegistry.md), AccessControl, EIP712

**Title:**
Controller

__/\\\\\\\\\\\\\\\__________________________/\\\____________________________
_\///////\\\/////__________________________\/\\\____________________________
_______\/\\\_______________________________\/\\\_________/\\\_______________
_______\/\\\______/\\\\\\\\___/\\/\\\\\\___\/\\\________\///___/\\/\\\\\\___
_______\/\\\____/\\\/////\\\_\/\\\////\\\__\/\\\\\\\\\___/\\\_\/\\\////\\\__
_______\/\\\___/\\\\\\\\\\\__\/\\\__\//\\\_\/\\\////\\\_\/\\\_\/\\\__\//\\\_
_______\/\\\__\//\\///////___\/\\\___\/\\\_\/\\\__\/\\\_\/\\\_\/\\\___\/\\\_
_______\/\\\___\//\\\\\\\\\\_\/\\\___\/\\\_\/\\\\\\\\\__\/\\\_\/\\\___\/\\\_
_______\///_____\//////////__\///____\///__\/////////___\///__\///____\///__

The Controller handles mint and redemption orders for the Tenbin protocol
Tenbin is an asset token issuance platform with the goal of creating liquid, composable financial assets.
Assets in the Tenbin protocol are backed by two positions: off-chain futures contracts and on-chain collateral.
An off-chain hedging system maintains a delta one exposure of an underlying asset. On-chain collateral is used to earn low-risk yield.
So long as the on-chain yield equals or exceeds the off-chain funding costs, the protocol is able to peg Tenbin assets to the spot price of the real asset.
The controller contract is responsible for minting and redeeming assets in the Tenbin protocol
Orders are signed by KYC-approved signers and specify order details such as order type, collateral amount, asset amount, and deadline.
All orders have an approval signed by a minter key stored in a hardware security module and controlled by the Tenbin backend.
To successfully execute an order, any account can call the mint or redeem with an order, signature, context, and approval.
Orders are executed atomically: collateral is transferred and tokens are minted/burned in a single transaction.
When a mint is executed, the collateral is split between a custodian account and a manager account.
The controller ratio represents the percentage of collateral to transfer to the the custodian account.
The controller has several administrative functions to manage order signers, add order beneficiaries, and allow delegating to a signer.
Signers are whitelisted by the SIGNER_MANAGER_ROLE.
Once a signer is whitelisted, orders signed by this signer are valid so long as the signer == order.payer, or the payer has delegated to a signer.
A signer can maintain a list of approved recipients. Only approved recipients for a signer can receive tokens during an order execution.
The controller never holds any tokens - collateral is held in a CollateralManager contract or off-ramped by a custodian account.
An oracle is used as a backstop to prevent order price from deviating from the oracle price.
However, order price is not determined by the oracle on-chain.
Staked assets can be redeemed by specifying the staked asset address as part of the order.
Redeeming staked assets requires approving the controller to spend staked assets.
The `Context` struct allows passing in a flag to indicate an order should be curated as part of the transaction.
When performing an on demand curation, the CollateralManager `withdraw()` or `deposit()` function is called
before a redemption or after a mint, respectively. An additional `share_price` is passed along with curated orders
to act as a slippage guard when interacting with the CollateralManager vaults.
Mint and redemption limits are configurable per block. Limits are always denominated in asset amount.
Setting the block mint limit to max uint will disable the limit
The controller is intended to be the only account which can mint asset tokens. In the case a new controller is created,
the old controller is deprecated and minting permission is set to the new controller.


## Constants
### RATIO_PRECISION
Precision used for ratio calculations


```solidity
uint256 private constant RATIO_PRECISION = 1e18
```


### MAX_ORACLE_TOLERANCE
Max oracle delta tolerance. 1e18 = 100%


```solidity
uint96 private constant MAX_ORACLE_TOLERANCE = 1e18
```


### MAX_LIMIT_AMOUNT
Max amount that can be set for mint and redeem limits


```solidity
uint128 private constant MAX_LIMIT_AMOUNT = type(uint128).max
```


### MINTER_ROLE
Minter role can call mint() and redeem() functions


```solidity
bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE")
```


### ADMIN_ROLE
Admin role can add new collateral types


```solidity
bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE")
```


### SIGNER_MANAGER_ROLE

```solidity
bytes32 public constant SIGNER_MANAGER_ROLE = keccak256("SIGNER_MANAGER_ROLE")
```


### GATEKEEPER_ROLE
Gatekeeper role can pause and unpause functionality


```solidity
bytes32 public constant GATEKEEPER_ROLE = keccak256("GATEKEEPER_ROLE")
```


### RESTRICTER_ROLE
Restricter role can change restricted status of accounts


```solidity
bytes32 constant RESTRICTER_ROLE = keccak256("RESTRICTER_ROLE")
```


### ORDER_TYPEHASH
Order typehash


```solidity
bytes32 public constant ORDER_TYPEHASH = keccak256(
    "Order(uint8 order_type,uint256 nonce,uint256 expiry,address payer,address recipient,address collateral_token,uint256 collateral_amount,address order_token,uint256 asset_amount)"
)
```


### CONTEXT_TYPEHASH
Context typehash


```solidity
bytes32 public constant CONTEXT_TYPEHASH =
    keccak256("Context(bytes32 order_hash,uint256 share_price,bool is_curated)")
```


### MAGICVALUE
MAGICVALUE to be used in ERC1271 verification


```solidity
bytes4 public constant MAGICVALUE = bytes4(keccak256("isValidSignature(bytes32,bytes)"))
```


### VERSION
Semantic version


```solidity
string public constant VERSION = "1.4.1"
```


### asset
Asset token used for this controller


```solidity
address public immutable asset
```


### stakedAsset
Staked asset token used for this controller


```solidity
address public immutable stakedAsset
```


## State Variables
### pauseStatus
Pause status


```solidity
ControllerPauseStatus public pauseStatus
```


### isRestricted
Mapping of restricted accounts


```solidity
mapping(address => bool) public isRestricted
```


### isCollateral
Supported collateral tokens


```solidity
mapping(address => bool) public isCollateral
```


### signers
Whitelist for signer accounts


```solidity
mapping(address => bool) public signers
```


### nonces
Keeps track of which nonces a payer has used


```solidity
mapping(address => mapping(uint256 => bool)) public nonces
```


### recipients
Approved recipients are accounts set by a whitelisted signer to receive tokens


```solidity
mapping(address => mapping(address => bool)) public recipients
```


### delegates
Payer accounts which have delegated a signer to sign orders on their behalf


```solidity
mapping(address => mapping(address => bool)) public delegates
```


### ratio
Percentage of collateral to transfer to custodian


```solidity
uint256 public ratio
```


### custodian
Address to transfer the custody portion of collateral to


```solidity
address public custodian
```


### manager
Address to transfer the on-chain portion of collateral to


```solidity
address public manager
```


### oracle
The price oracle is used to prevent orders from exceeding a delta tolerance
The oracle struct contains an oracle adapter to normalize price, and an oracle tolerance
This is a security measure to prevent minting excessive tokens / redeeming at a price away from spot
The oracle is not used to determine exact price, rather it enforces a price delta tolerance


```solidity
Oracle public oracle
```


### blockMintLimit
Asset mint limit per block


```solidity
uint128 public blockMintLimit
```


### blockRedeemLimit
Asset redeem limit per block


```solidity
uint128 public blockRedeemLimit
```


### mintLimit
Track amount minted in a block to enforce limits


```solidity
Limit public mintLimit
```


### redeemLimit
Track amount redeemed in a block to enforce limits


```solidity
Limit public redeemLimit
```


## Functions
### nonZeroAddress

Revert if zero address


```solidity
modifier nonZeroAddress(address addr) ;
```

### constructor

Constructor


```solidity
constructor(address asset_, address stakedAsset_, uint256 ratio_, address custodian_, address owner_)
    EIP712("TenbinController", VERSION);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`asset_`|`address`|Address of asset token|
|`stakedAsset_`|`address`||
|`ratio_`|`uint256`|Ratio of collateral transferred to custodian during mints|
|`custodian_`|`address`|Custodian account|
|`owner_`|`address`|Account to set as the DEFAULT_ADMIN_ROLE|


### setSignerStatus

Signer manager can set allowed signers


```solidity
function setSignerStatus(address account, bool status) external onlyRole(SIGNER_MANAGER_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`account`|`address`|Signer account|
|`status`|`bool`|Signer allowed status|


### setRecipientStatus

Set whether or not an account is a recipient for a given signer
Recipients for a signer can receive tokens when an order is executed


```solidity
function setRecipientStatus(address recipient, bool status) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`recipient`|`address`|Account to change recipient status for|
|`status`|`bool`|True if an account is a valid recipient address for a signer|


### setDelegateStatus

Allow an account to delegate a signer to sign orders on their behalf

New delegations require signer to be active


```solidity
function setDelegateStatus(address signer, bool status) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`signer`|`address`|Signer account to delegate to|
|`status`|`bool`|Status for delegate signer|


### setPauseStatus

Gatekeeper role can set pause status


```solidity
function setPauseStatus(ControllerPauseStatus status) external onlyRole(GATEKEEPER_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`status`|`ControllerPauseStatus`|New pause status|


### setIsRestricted

Sets or unsets an address as restricted


```solidity
function setIsRestricted(address account, bool status) external onlyRole(RESTRICTER_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`account`|`address`|The address to update|
|`status`|`bool`||


### setIsCollateral

Add or remove supported collateral


```solidity
function setIsCollateral(address collateral, bool status)
    external
    onlyRole(DEFAULT_ADMIN_ROLE)
    nonZeroAddress(collateral);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`collateral`|`address`|Collateral to change status for|
|`status`|`bool`|New status|


### setCustodian

Change the custodian account


```solidity
function setCustodian(address newCustodian) external onlyRole(DEFAULT_ADMIN_ROLE) nonZeroAddress(newCustodian);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newCustodian`|`address`|New custodian account|


### setManager

Change the manager account


```solidity
function setManager(address newManager) external onlyRole(DEFAULT_ADMIN_ROLE) nonZeroAddress(newManager);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newManager`|`address`|New manager account|


### setRatio

Change the ratio. The ratio must be 1-1e18.


```solidity
function setRatio(uint256 newRatio) external onlyRole(ADMIN_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newRatio`|`uint256`|New ratio|


### setOracleTolerance

Change the oracle price delta tolerance. 1e18 = 100%


```solidity
function setOracleTolerance(uint96 newTolerance) external onlyRole(ADMIN_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newTolerance`|`uint96`|New delta tolerance|


### setOracleAdapter

Change the oracle tolerance. 1e18 = 100%
Setting the adapter to address(0) will disable it and reset the tolerance to zero


```solidity
function setOracleAdapter(address newAdapter) external onlyRole(ADMIN_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newAdapter`|`address`|New oracle adapter|


### setBlockMintLimit

Set block mint limit


```solidity
function setBlockMintLimit(uint128 newBlockMintLimit) external onlyRole(DEFAULT_ADMIN_ROLE);
```

### setBlockRedeemLimit

Set block redeem limit


```solidity
function setBlockRedeemLimit(uint128 newBlockRedeemLimit) external onlyRole(DEFAULT_ADMIN_ROLE);
```

### rescueToken

Rescue tokens sent to this contract

The receiver should be a trusted address to avoid external calls attack vectors


```solidity
function rescueToken(address token, address to) external onlyRole(ADMIN_ROLE) nonZeroAddress(to);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`token`|`address`|The address of the ERC20 token to be rescued|
|`to`|`address`|Recipient of rescued tokens|


### rescueEther

Rescue ether sent to this contract


```solidity
function rescueEther() external onlyRole(ADMIN_ROLE);
```

### multicall

Allow batched calls to this contract


```solidity
function multicall(bytes[] calldata data) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`data`|`bytes[]`|Data to delegatecall on this contract|


### mint

Mint asset tokens


```solidity
function mint(
    Order calldata order,
    Signature calldata signature,
    Context calldata context,
    Signature calldata approval
) external override;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`order`|`Order`|Order data|
|`signature`|`Signature`|Signature of hashed order|
|`context`|`Context`|Context used to determine order execution options|
|`approval`|`Signature`|ECDSA signature of context data|


### redeem

Redeem asset tokens


```solidity
function redeem(
    Order calldata order,
    Signature calldata signature,
    Context calldata context,
    Signature calldata approval
) external override;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`order`|`Order`|Order data|
|`signature`|`Signature`|ECDSA signature of hashed order|
|`context`|`Context`|Context used to determine order execution options|
|`approval`|`Signature`|ECDSA signature of context data|


### verifyNonce

Verify a signer nonce.


```solidity
function verifyNonce(address payer, uint256 nonce) external view override;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`payer`|`address`||
|`nonce`|`uint256`|Nonce to check|


### invalidateNonce

Allows a payer to invalidate a specific nonce to cancel pending orders


```solidity
function invalidateNonce(uint256 nonce) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nonce`|`uint256`|The nonce to invalidate|


### verifyOrder

Verify a signed EIP712 order


```solidity
function verifyOrder(Order calldata order, Signature calldata signature)
    public
    view
    override
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


### verifyContext

Verify a signed EIP712 context. Reverts if context is not signed by MINTER_ROLE


```solidity
function verifyContext(Context calldata context, Signature calldata approval) public view override;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`context`|`Context`|Context data|
|`approval`|`Signature`|Signature of hashed context|


### hashOrder

Get the EIP712 typed data hash of an order.


```solidity
function hashOrder(Order calldata order) public view override returns (bytes32 orderHash);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`order`|`Order`|Order data|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`orderHash`|`bytes32`|EIP712 typed data hash of `order`|


### hashContext

Get the EIP712 typed data hash of a context.


```solidity
function hashContext(Context calldata context) public view override returns (bytes32 contextHash);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`context`|`Context`|Context data|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`contextHash`|`bytes32`|EIP712 typed data hash of `context`|


### encodeOrder

Encode order data according to EIP712 specification


```solidity
function encodeOrder(Order calldata order) public pure returns (bytes memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`order`|`Order`|Order data|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bytes`|ABI encoded order|


### encodeContext

Encode context data according to EIP712 specification


```solidity
function encodeContext(Context calldata context) public pure returns (bytes memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`context`|`Context`|Context data|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bytes`|ABI encoded context|


### getDomainSeparator

Get the domain separator for this contract


```solidity
function getDomainSeparator() public view returns (bytes32);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bytes32`|Domain separator for this contract|


### version

Contract semantic version


```solidity
function version() public pure returns (string memory);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`string`|Contract version|


### _verifyNonce

Reverts if nonce was previously used by a payer


```solidity
function _verifyNonce(address payer, uint256 nonce) internal view;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`payer`|`address`|Payer to verify nonce for|
|`nonce`|`uint256`|Nonce to be verified|


