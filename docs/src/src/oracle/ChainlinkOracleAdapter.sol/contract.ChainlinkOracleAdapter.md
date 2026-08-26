# ChainlinkOracleAdapter
[Git Source](https://github.com/tenbinlabs/tenbin-contracts/blob/51cfcc3be55c1fc66666f437e8175c7820cc2918/src/oracle/ChainlinkOracleAdapter.sol)

**Inherits:**
[IOracleAdapter](/src/interface/IOracleAdapter.sol/interface.IOracleAdapter.md)

**Title:**
Chainlink Oracle Adapter

Normalize oracle data from a Chainlink aggregator into a standard representation


## Constants
### offset
Amount to offset the answer by.
ex. If an oracle has 8 decimals precision, multiple the answer by 1e18 to normalize to 18 decimals


```solidity
uint256 public immutable offset
```


### stalenessThreshold
Stale price threshold (e.g., 24 hours for XAU/USD)


```solidity
uint256 public immutable stalenessThreshold
```


### oracle
Chainlink oracle


```solidity
address public immutable oracle
```


## Functions
### constructor

Constructor for a generic Chainlink Oracle Adapters


```solidity
constructor(address oracle_, uint256 stalenessThreshold_) ;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`oracle_`|`address`|Address of chainlink oracle|
|`stalenessThreshold_`|`uint256`|Staleness threshold of this oracle in seconds|


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


