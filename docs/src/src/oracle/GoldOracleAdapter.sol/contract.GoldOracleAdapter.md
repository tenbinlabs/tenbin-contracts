# GoldOracleAdapter
[Git Source](https://github.com/tenbinlabs/contracts/blob/34d0d98c6959c0c67cf21488bdfb4b79f4ce3f2e/src/oracle/GoldOracleAdapter.sol)

**Inherits:**
[IOracleAdapter](/src/interface/IOracleAdapter.sol/interface.IOracleAdapter.md)

**Title:**
Gold Oracle Adapter

Normalize oracle data from a Chainlink aggregator into a standard representation


## State Variables
### DECIMALS_OFFSET
Difference between oracle decimals and 1e18


```solidity
uint256 internal constant DECIMALS_OFFSET = 1e10
```


### PRICE_STALENESS_THRESHOLD
Stale price threshold (e.g., 24 hours for XAU/USD)


```solidity
uint256 public constant PRICE_STALENESS_THRESHOLD = 1 days
```


### oracle
Chainlink oracle


```solidity
AggregatorV3Interface public immutable oracle
```


## Functions
### constructor


```solidity
constructor(address oracle_) ;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`oracle_`|`address`|Address of chainlink oracle|


### getPrice

Returns price with 18 decimals of precision

Return price in USD with 18 decimals


```solidity
function getPrice() external view returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|price Price with 18 decimals of precision|


