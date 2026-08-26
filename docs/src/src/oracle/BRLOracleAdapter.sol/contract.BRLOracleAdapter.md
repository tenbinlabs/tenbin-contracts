# BRLOracleAdapter
[Git Source](https://github.com/tenbinlabs/tenbin-contracts/blob/51cfcc3be55c1fc66666f437e8175c7820cc2918/src/oracle/BRLOracleAdapter.sol)

**Inherits:**
[IOracleAdapter](/src/interface/IOracleAdapter.sol/interface.IOracleAdapter.md)

**Title:**
BRL Oracle Adapter

Oracle Adapter for Chainlink BRL/USD oracle
https://data.chain.link/feeds/ethereum/mainnet/brl-usd
Normalizes response from Chainlink aggregator to uint256 with 18 decimals
https://etherscan.io/address/0x3126E7F38D5f60f4E2B6ec3511C7bdbD79317Df1


## Constants
### PRICE_STALENESS_THRESHOLD
Stale price threshold for this oracle


```solidity
uint256 public constant PRICE_STALENESS_THRESHOLD = 86400 seconds
```


### OFFSET
Difference between the target precicion (1e18) and the oracle precision
For BRL/USD, the precision is 1e8


```solidity
uint256 public constant OFFSET = 1e10
```


### oracle
Chainlink Oracle: BRL/USD


```solidity
address public constant oracle = 0x3126E7F38D5f60f4E2B6ec3511C7bdbD79317Df1
```


## Functions
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


