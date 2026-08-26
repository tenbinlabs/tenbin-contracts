# AssetToken
[Git Source](https://github.com/tenbinlabs/tenbin-contracts/blob/51cfcc3be55c1fc66666f437e8175c7820cc2918/src/AssetToken.sol)

**Inherits:**
[IBurnMintERC20](/src/interface/IBurnMintERC20.sol/interface.IBurnMintERC20.md), ERC20Permit, Ownable2Step

**Title:**
Asset Token

__/\\\\\\\\\\\\\\\__________________________/\\\____________________________
_\///////\\\/////__________________________\/\\\____________________________
_______\/\\\_______________________________\/\\\_________/\\\_______________
_______\/\\\______/\\\\\\\\___/\\/\\\\\\___\/\\\________\///___/\\/\\\\\\___
_______\/\\\____/\\\/////\\\_\/\\\////\\\__\/\\\\\\\\\___/\\\_\/\\\////\\\__
_______\/\\\___/\\\\\\\\\\\__\/\\\__\//\\\_\/\\\////\\\_\/\\\_\/\\\__\//\\\_
_______\/\\\__\//\\///////___\/\\\___\/\\\_\/\\\__\/\\\_\/\\\_\/\\\___\/\\\_
_______\/\\\___\//\\\\\\\\\\_\/\\\___\/\\\_\/\\\\\\\\\__\/\\\_\/\\\___\/\\\_
_______\///_____\//////////__\///____\///__\/////////___\///__\///____\///__

A token to represent assets as part of the Tenbin protocol
Implemented as an ERC20 with added mint() and burn() functions
The `minter` role is set by the owner, and is allowed to call the mint() function
Allow the owner to attach a token notice returned by `notice()`


## State Variables
### minter
Account which has permission to mint tokens


```solidity
address public minter
```


### notice
Attach a token notice which can be updated by the owner


```solidity
string public notice
```


## Functions
### constructor

Constructor


```solidity
constructor(string memory name_, string memory symbol_, address owner_)
    ERC20(name_, symbol_)
    ERC20Permit(name_)
    Ownable(owner_);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`name_`|`string`|Token name|
|`symbol_`|`string`|Token symbol|
|`owner_`|`address`||


### setMinter

Set minter account


```solidity
function setMinter(address newMinter) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newMinter`|`address`|New minter account|


### mint

Mints new tokens for a given address.

this function increases the total supply.


```solidity
function mint(address account, uint256 amount) external;
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
function burn(address account, uint256 amount) external;
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
function burnFrom(address account, uint256 amount) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`account`|`address`|The address to burn tokens from.|
|`amount`|`uint256`|The number of tokens to be burned.|


### setNotice

Set a new token notice


```solidity
function setNotice(string calldata newNotice) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newNotice`|`string`|New token notice|


## Events
### MinterChanged
Emitted when the minter account is changed


```solidity
event MinterChanged(address newMinter);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newMinter`|`address`|New minter account|

## Errors
### OnlyMinter
Only minter


```solidity
error OnlyMinter();
```

