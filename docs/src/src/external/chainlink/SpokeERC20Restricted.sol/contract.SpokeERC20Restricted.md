# SpokeERC20Restricted
[Git Source](https://github.com/tenbinlabs/tenbin-contracts/blob/3b9a2e72170c3c18199904176b97ca07122173ad/src/external/chainlink/SpokeERC20Restricted.sol)

**Inherits:**
[IBurnMintERC20](/src/interface/IBurnMintERC20.sol/interface.IBurnMintERC20.md), [IRestrictedRegistry](/src/interface/IRestrictedRegistry.sol/interface.IRestrictedRegistry.md), ERC20Permit, AccessControl

**Title:**
Spoke ERC20

ERC20 for deployment on "spoke" chains. Facilitates cross-chain tokens by allowing
"mint-and-burn" operations on non-ethereum chains.
Has a resticted list for complying with legal requirements. Used for cross chain StakedAsset tokens
If an account is restricted, it cannot transfer assets
Restricted accounts can have their balance burned
Allows transferring to restricted accounts to ensure cross chain transfers can complete for restricted accounts


## Constants
### MINTER_BURNER_ROLE
Minter role can mint and burn tokens


```solidity
bytes32 public constant MINTER_BURNER_ROLE = keccak256("MINTER_BURNER_ROLE")
```


### RESTRICTER_ROLE
Restricter role can change restricted status of accounts


```solidity
bytes32 public constant RESTRICTER_ROLE = keccak256("RESTRICTER_ROLE")
```


## State Variables
### isRestricted
Mapping of restricted accounts


```solidity
mapping(address => bool) public isRestricted
```


## Functions
### nonRestricted

Reverts if account is restricted


```solidity
modifier nonRestricted(address account) ;
```

### constructor

Constructor


```solidity
constructor(string memory name_, string memory symbol_, address owner_) ERC20(name_, symbol_) ERC20Permit(name_);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`name_`|`string`|Token name|
|`symbol_`|`string`|Token symbol|
|`owner_`|`address`||


### mint

Mints new tokens for a given address.

this function increases the total supply.


```solidity
function mint(address account, uint256 amount) external onlyRole(MINTER_BURNER_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`account`|`address`|The address to mint the new tokens to.|
|`amount`|`uint256`|The number of tokens to be minted.|


### burn

Burns tokens from the sender.

this function decreases the total supply.


```solidity
function burn(uint256 amount) external nonRestricted(msg.sender);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`amount`|`uint256`|The number of tokens to be burned.|


### burn

Burns tokens from a given address.

this function decreases the total supply.


```solidity
function burn(address account, uint256 amount) external nonRestricted(account) onlyRole(MINTER_BURNER_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`account`|`address`|The address to burn tokens from.|
|`amount`|`uint256`|The number of tokens to be burned.|


### burnFrom

Burns tokens from a given address.

this function decreases the total supply.


```solidity
function burnFrom(address account, uint256 amount) external nonRestricted(account) onlyRole(MINTER_BURNER_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`account`|`address`|The address to burn tokens from.|
|`amount`|`uint256`|The number of tokens to be burned.|


### transferRestricted

Withdraw assets from a restricted account

If it is necessary to sweep funds from a restricted account, the tokens will be
transferred back to the hub chain and burned. This prevents permanent locking in the CCIP hub chain pool


```solidity
function transferRestricted(address from, address to) external onlyRole(DEFAULT_ADMIN_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`from`|`address`|Restricted account to sweep funds from|
|`to`|`address`|Account to transfer assets to|


### setIsRestricted

Sets or unsets an address as restricted


```solidity
function setIsRestricted(address account, bool newStatus) external onlyRole(RESTRICTER_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`account`|`address`|The address to update|
|`newStatus`|`bool`|The new restriction status|


### transfer

Override transfer function to prevent restricted accounts from transferring
Restricted accounts can still receive tokens


```solidity
function transfer(address to, uint256 value)
    public
    override(IERC20, ERC20)
    nonRestricted(msg.sender)
    returns (bool);
```

### transferFrom

Override transferFrom function to prevent restricted accounts from trasnferring tokens
Restricted accounts can still receive tokens


```solidity
function transferFrom(address from, address to, uint256 value)
    public
    override(IERC20, ERC20)
    nonRestricted(from)
    nonRestricted(msg.sender)
    returns (bool);
```

