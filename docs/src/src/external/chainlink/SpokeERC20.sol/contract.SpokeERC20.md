# SpokeERC20
[Git Source](https://github.com/tenbinlabs/monorepo/blob/282e8df48c5730face078c656f06f4082da3317a/src/external/chainlink/SpokeERC20.sol)

**Inherits:**
[IBurnMintERC20](/src/interface/IBurnMintERC20.sol/interface.IBurnMintERC20.md), ERC20Permit, AccessControl

**Title:**
Spoke ERC20

ERC20 for deployment on "spoke" chains. Facilitates cross-chain tokens by allowing
"mint-and-burn" operations on non-ethereum chains.


## State Variables
### MINTER_BURNER_ROLE
Minter role can mint and burn tokens


```solidity
bytes32 public constant MINTER_BURNER_ROLE = keccak256("MINTER_BURNER_ROLE")
```


## Functions
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
function burn(uint256 amount) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`amount`|`uint256`|The number of tokens to be burned.|


### burn

Burns tokens from a given address.

this function decreases the total supply.


```solidity
function burn(address account, uint256 amount) external onlyRole(MINTER_BURNER_ROLE);
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
function burnFrom(address account, uint256 amount) external onlyRole(MINTER_BURNER_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`account`|`address`|The address to burn tokens from.|
|`amount`|`uint256`|The number of tokens to be burned.|


