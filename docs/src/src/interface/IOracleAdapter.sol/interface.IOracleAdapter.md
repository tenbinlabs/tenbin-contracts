# IOracleAdapter
[Git Source](https://github.com/tenbinlabs/tenbin-contracts/blob/3b9a2e72170c3c18199904176b97ca07122173ad/src/interface/IOracleAdapter.sol)

**Title:**
OracleAdapter

Normalize price data from an external source into a standard representation


## Functions
### getPrice

Returns price with 18 decimals of precision


```solidity
function getPrice() external view returns (uint256 price);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`price`|`uint256`|Price with 18 decimals of precision|


### oracle

Address of oracle used by this adapter


```solidity
function oracle() external view returns (address oracleAddress);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`oracleAddress`|`address`|Oracle address|


## Errors
### InvalidOracleDecimals
Thrown when adding an oracle with incompatible decimals


```solidity
error InvalidOracleDecimals();
```

### InvalidOraclePrice
Returned data from oracle fails to pass verifications


```solidity
error InvalidOraclePrice();
```

### OraclePriceStale
Oracle price is stale based on staleness threshold


```solidity
error OraclePriceStale();
```

