# AssetToken
[Git Source](https://github.com/tenbinlabs/contracts/blob/34d0d98c6959c0c67cf21488bdfb4b79f4ce3f2e/src/AssetToken.sol)

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


## State Variables
### minter
Account which has permission to mint tokens


```solidity
address public minter
```


### TOKEN_NOTE

```solidity
string public constant TOKEN_NOTE = "- ***THIS TOKEN-NOTE IS SUBJECT TO ALL OF THE TERMS AND CONDITIONS PUBLISHED ON THE TENBIN FOUNDATION WEBSITE, app.tenbin.xyz****\n\n"
    "**TOKEN-NOTE**\n\n"
    "This TOKEN-NOTE (this \"**Token-Note**\" or \"**Note**\") is an integrated instrument that exists as a controllable electronic record as defined in UCC Sec. 12-102(a)(1) (a \"**CER**\") within a form of digital token (the \"**Token**\") dispatched on the Ethereum blockchain (the \"**Token Platform**\").\n\n"
    "On or before the date this Token-Note is issued on the Token Platform (such date, \"**Issue Date**\"), for value received, Tenbin AssetCo (BVI) SPC Ltd., a British Islands segregated portfolio company (the \"**Issuer**\") promises to pay to the order of holder ****by control (within the meaning of UCC Sec. 12-105 (\"**Token Control**\" and, such holder, the \"**Initial Holder**\" and each subsequent holder by Token Control of the Token, from time to time, each a \"**Holder**\"), in the manner and at the place provided below, the principal sum of the U.S. dollar value of one troy ounce of gold priced at the Spot Price (hereinafter defined). Concurrently on the Issue Date, Issuer shall issue the Token on the Token Platform in the aggregate notional amount of one hundred percent (100%) of the Note. Transfers of the Token and ownership by Token Control may thereafter occur solely in accordance with Section 7.\n\n"
    "1. **Spot Price, Valuation**. For purposes of this Note, the Spot Price shall be the PM spot price of gold per troy ounce as published by the London Bullion Market Association (\"**LBMA**\") on the business day that this Note is issued or repaid, whichever applicable (or if not on a day on which LBMA is publishing prices, the closest preceding such day). Notwithstanding the foregoing, the Issuer may, in its sole discretion, select a different pricing source and time for determining the spot price of gold for operational purposes.\n"
    "2. **Payment**. All payments of principal and interest under this Token-Note will be denominated in gold, priced at the Spot Price, and paid in a U.S. dollar-denominated stablecoin selected by the Issuer, without offset, deduction, or counterclaim. Delivery shall be made in accordance with the procedures of the Token Platform, to the Holder, upon the Holder's valid exercise of its right to payment and redemption.\n"
    "3. **Demand**. The principal amount of this Token-Note, together with any and all accrued and unpaid interest thereon, is payable by the Issuer to the Holder **ON DEMAND** at any time by the Holder. Procedures for presentment are published on the Issuer's website [**app.tenbin.xyz**] and subject to all terms, conditions, and agreements published therein. Only after Holder is qualified and approved by the Issuer may it present this Token-Note for payment. Upon approval, and Holder's demand for payment via the Token Platform, the Issuer shall promptly deliver the specified amount represented by the Token, together with any and all accrued and unpaid interest, in accordance with the procedures of the Issuer Platform.\n"
    "4. **Interest**. Interest on the unpaid principal balance of this note, if any, is payable from the date of this Token-Note until this Note is paid in full, at amounts selected by the Issuer in its sole and absolute discretion. Accrued interest, if any, will be computed on the basis of a 365-day or 366-day year, as the case may be, based on the actual number of days elapsed in the period in which it accrues. For the avoidance of doubt, any interest payable under this note is at the sole and absolute discretion of the Issuer.\n"
    "5. **Waiver of Presentment; Demand**. The Issuer hereby waives presentment, demand, notice of dishonor, notice of default or delinquency, notice of protest and nonpayment, notice of costs, expenses or losses and interest on those, notice of interest on interest and late charges, and diligence in taking any action to collect any sums owing under this Note, including (to the extent permitted by law) waiving the pleading of any statute of limitations as a defense to any demand against the undersigned. Acceptance by the Holder this Note of any payment differing from the designated lump-sum payment listed above does not relieve the undersigned of the obligation to honor the requirements of this Note.\n"
    "6. **Governing Law**. The seat of administration, exclusive venue, and forum for any dispute, proceeding, or enforcement action relating to the Token or this Token-Note shall be the British Virgin Islands. Notwithstanding the foregoing, all rights and obligations arising under this Token-Note, including but not limited to all transfers, payments, and redemptions, shall be governed by and construed in accordance with Article 12 of the Uniform Commercial Code as adopted in the State of Delaware.\n"
    "7. **CER and Transfer**. The Holder's rights to payment and redemption under this Token-Note are evidenced by, and may be transferred only by, Token Control of the Token-Note as a CER. The Holder shall be deemed to have \"control\" of this Token-Note within the meaning of UCC Sec.12-105 if Holder has, as evidenced by the records of the Token Platform, the exclusive power to: (a) avail itself of substantially all the benefit from the Token-Note; (b) prevent others from availing themselves of substantially all the benefit of the Token-Note; and (c) transfer control of the Token-Note to another person. Upon cryptographic verification of the transfer on the applicable distributed ledger, ownership of the corresponding Note automatically passes to the transferee, and the transferee shall be a \"Holder\" hereunder as party to this Note. Upon transfer of a Token in accordance with this **Section 7** (such transferring Holder, the \"**Transferring Holder**\"), the Transferring Holder shall, as of the effective time of such disposition, automatically cease to be a party to this Note. For the avoidance of doubt, upon such transfer, all rights, benefits, duties, and obligations of such Transferring Holder under this Agreement shall immediately and irrevocably terminate, and such Transferring Holder shall not be entitled to any payments, indemnities, or other benefits hereunder, nor shall such Transferring Holder have any further liability or responsibility under this Note.\n\n"
    "Issuer, Initial Holder, and each other Holder agree and acknowledge:\n\n"
    "(a) The Token constitutes a CER and is subject to Token Control.\n\n"
    "(b) Token Control of the Token by a Holder is conclusive evidence of the ownership of the Note and the right to payment made hereunder. No separate register of holders shall be maintained by Issuer, Initial Holder or any other person.\n\n"
    "(c) Issuer further agrees (i) that the Note issued hereunder constitutes either (x) a controllable payment intangible (as defined in UCC Sec.9-102(a)(27B)), or (y) a controllable account (as defined in UCC Sec. 9-102(a)(27A)), as applicable, evidenced by (and tethered to) the Token issued pursuant to this Note, and (ii) agrees to pay the Holder who has Token Control over such Token in accordance with this Note. THE RIGHTS AND OBLIGATIONS DESCRIBED IN THIS TOKEN-NOTE ARE EMBODIED IN AND INSEPARABLE FROM THE TOKEN, SUCH THAT CONTROL OF THE TOKEN CONSTITUTES CONTROL OF THIS TOKEN-NOTE AND ALL RIGHTS HEREUNDER. Except as expressly permitted in this **Section 7**, no Holder may transfer its Token or the Note.\n\n"
    "8. **Severability**. If any one or more of the provisions contained in this Note is, for any reason, held to be invalid, illegal, or unenforceable in any respect, that invalidity, illegality, or unenforceability will not affect any other provisions of this Note, and this Note will be construed as if those invalid, illegal, or unenforceable provisions had never been contained in it, unless the deletion of those provisions would result in such a material change so as to cause completion of the transactions contemplated by this Note to be unreasonable.\n"
    "9. **Waiver; Amendment**. No amendment to the terms of this Note or waiver of a breach, failure of any condition, or any right or remedy contained in or granted by the provisions of this Note will be effective unless it is in writing and expressly approved by Issuer. No waiver of any breach, failure, right, or remedy will be deemed a waiver of any other breach, failure, right, or remedy, whether or not similar, and no waiver will constitute a continuing waiver, unless the writing so specifies.\n"
    "10. **Headings**. The descriptive headings of the sections and subsections of this Note are for convenience only, and do not affect this Note's construction or interpretation.\n"
    "11. **Platform-Based Signatures**. By issuing and accepting the Token on the Token Platform in accordance with Section 7 hereof, Issuer and each Holder authenticates, signs (including, without limitation, \"signing\" within the meaning of Section 1-201 of the UCC, and, for the avoidance of doubt, such signing shall constitute, without limitation, an \"electronic signature\" within the meaning of the Uniform Electronic Transactions Act and U.S. federal E-SIGN Act of 2000), executes, and delivers this Note as of the effective date of such acceptance. No manual signature, writings, notarization, or further action is required to indicate such Loan Participant's intent to authenticate or adopt this Agreement. In accordance with Section 6 hereof, this Agreement may be executed in any number of counterparts and all of such counterparts shall together constitute one and the same instrument."
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

