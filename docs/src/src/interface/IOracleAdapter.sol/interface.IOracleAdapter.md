# IOracleAdapter
[Git Source](https://github.com/tenbinlabs/contracts/blob/34d0d98c6959c0c67cf21488bdfb4b79f4ce3f2e/src/interface/IOracleAdapter.sol)

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


## Errors
### IncorrectOracleRound
Answer is not from latest round


```solidity
error IncorrectOracleRound();
```

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

