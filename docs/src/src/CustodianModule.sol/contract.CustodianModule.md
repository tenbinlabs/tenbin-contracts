# CustodianModule
[Git Source](https://github.com/tenbinlabs/contracts/blob/7874f0709e21201d251621138d90d5b61ccd404d/src/CustodianModule.sol)

**Inherits:**
AccessControl

**Title:**
CustodianModule

Allows funds to be transferred to approved custodian accounts
Collateral is sent to this contract during the asset minting process
Custodian accounts are whitelisted by an administrator
A keeper role can automate transferring collateral to different custodians


## State Variables
### CUSTODIAN_KEEPER_ROLE
Keeper role can distribute tokens to approved custodian accounts


```solidity
bytes32 public constant CUSTODIAN_KEEPER_ROLE = keccak256("CUSTODIAN_KEEPER_ROLE")
```


### custodians
Approved custodian accounts


```solidity
mapping(address => bool) public custodians
```


## Functions
### nonZeroAddress

Revert if zero address


```solidity
modifier nonZeroAddress(address addr) ;
```

### constructor

CustodianModule constructor


```solidity
constructor(address owner) ;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`owner`|`address`|Address to be assigned the DEFAULT_ADMIN_ROLE|


### setCustodianStatus

Set an account as a custodian


```solidity
function setCustodianStatus(address account, bool status)
    external
    onlyRole(DEFAULT_ADMIN_ROLE)
    nonZeroAddress(account);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`account`|`address`|Account to add to custodians list|
|`status`|`bool`|Whether or not an account is a custodian|


### offramp

Sends funds to a whitelisted custodian account


```solidity
function offramp(address account, address token, uint256 amount)
    external
    onlyRole(CUSTODIAN_KEEPER_ROLE)
    nonZeroAddress(account)
    nonZeroAddress(token);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`account`|`address`|Address to receive the funds|
|`token`|`address`|Address of tokens to be transferred|
|`amount`|`uint256`|Amount of token to be transferred|


## Events
### CustodianUpdated
Emitted when a custodian status is updated


```solidity
event CustodianUpdated(address account, bool isCustodian);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`account`|`address`|The account updated|
|`isCustodian`|`bool`|Whether account is a custodian or not|

## Errors
### NotApprovedCustodian
Token receiver not in custodians list


```solidity
error NotApprovedCustodian();
```

### NonZeroAddress
Zero address not allowed


```solidity
error NonZeroAddress();
```

