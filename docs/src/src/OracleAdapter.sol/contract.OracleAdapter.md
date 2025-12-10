# OracleAdapter
[Git Source](https://github.com/tenbinlabs/contracts/blob/aca92cae688bdb3da3dd7de958cb87e2d6cc5d0e/src/OracleAdapter.sol)

**Inherits:**
[IOracleAdapter](/Users/tenbin/code/contracts/docs/src/src/interface/IOracleAdapter.sol/interface.IOracleAdapter.md)

Normalize oracle data from a Chainlink aggregator into a standard representation


## State Variables
### oracle
Chainlink oracle


```solidity
AggregatorInterface public immutable oracle
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


