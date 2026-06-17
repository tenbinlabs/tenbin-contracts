# MXNOracleAdapter
[Git Source](https://github.com/tenbinlabs/tenbin-contracts/blob/eb2d102704c08124f1036e9b92cd46f9cf41203f/src/oracle/MXNOracleAdapter.sol)

**Inherits:**
[IOracleAdapter](/src/interface/IOracleAdapter.sol/interface.IOracleAdapter.md)

**Title:**
MXN Oracle Adapter

Oracle Adapter for Chainlink MXN/USD oracle
hhttps://data.chain.link/feeds/ethereum/mainnet/mxn-usd
Normalizes response from Chainlink aggregator to uint256 with 18 decimals
https://etherscan.io/address/0xdb4881Ab0ad6b8423f76dd8C9d65542749a1dB77


## Constants
### PRICE_STALENESS_THRESHOLD
Stale price threshold for this oracle


```solidity
uint256 public constant PRICE_STALENESS_THRESHOLD = 86400 seconds
```


### OFFSET
Difference between the target precicion (1e18) and the oracle precision
For MXN/USD, the precision is 1e8


```solidity
uint256 public constant OFFSET = 1e10
```


### oracle
Chainlink Oracle: MXN/USD


```solidity
address public constant oracle = 0xdb4881Ab0ad6b8423f76dd8C9d65542749a1dB77
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


