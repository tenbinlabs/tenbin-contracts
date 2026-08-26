# ChainlinkOracleWrapper
[Git Source](https://github.com/tenbinlabs/tenbin-contracts/blob/51cfcc3be55c1fc66666f437e8175c7820cc2918/src/oracle/ChainlinkOracleWrapper.sol)

**Inherits:**
AggregatorV3Interface

**Title:**
Chainlink Oracle Wrapper

Oracle Wrapper for Morpho Markets which converts a Chainlink price feed to 8 decimals
Normalizes response from Chainlink aggregator to int256 with 8 decimals
Only works for oracles with decimals >= 8


## Constants
### DECIMALS
Decimals for this Aggregator


```solidity
uint8 internal constant DECIMALS = 8
```


### offset
Offset for this Aggregator (precision removed from answer)


```solidity
uint8 public immutable offset
```


### oracle
Chainlink Oracle: tGLD/USD - 24/7 Blended Price


```solidity
AggregatorV3Interface public immutable oracle
```


## Functions
### constructor

Calculate decimals offset given a chainlink oracle


```solidity
constructor(AggregatorV3Interface oracle_) ;
```

### decimals

Gets the number of decimals used by the aggregator.


```solidity
function decimals() external pure returns (uint8);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint8`|uint8 - The number of decimals.|


### description

Gets the description of the aggregator.


```solidity
function description() external view returns (string memory);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`string`|string memory - The description of the aggregator.|


### version

Gets the version of the aggregator.


```solidity
function version() external view returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|uint256 - The version of the aggregator.|


### getRoundData

Gets the round data for a specific round ID.

This function should raise "No data present" if no data is available for the given round ID.


```solidity
function getRoundData(uint80 _roundId)
    external
    view
    returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_roundId`|`uint80`|- The round ID to get the data for.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`roundId`|`uint80`|- The round ID.|
|`answer`|`int256`|- The answer for the round.|
|`startedAt`|`uint256`|- The timestamp when the round started.|
|`updatedAt`|`uint256`|- The timestamp when the round was updated.|
|`answeredInRound`|`uint80`|- The round ID in which the answer was computed.|


### latestRoundData

Gets the latest round data.

This function should raise "No data present" if no data is available.


```solidity
function latestRoundData()
    external
    view
    returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`roundId`|`uint80`|- The latest round ID.|
|`answer`|`int256`|- The latest answer.|
|`startedAt`|`uint256`|- The timestamp when the latest round started.|
|`updatedAt`|`uint256`|- The timestamp when the latest round was updated.|
|`answeredInRound`|`uint80`|- The round ID in which the latest answer was computed.|


## Errors
### InvalidOracleDecimals
Decimals must be >= 8


```solidity
error InvalidOracleDecimals();
```

