# GoldOracleAdapter
[Git Source](https://github.com/tenbinlabs/tenbin-contracts/blob/3b9a2e72170c3c18199904176b97ca07122173ad/src/oracle/GoldOracleAdapter.sol)

**Inherits:**
[IOracleAdapter](/src/interface/IOracleAdapter.sol/interface.IOracleAdapter.md)

**Title:**
Gold Oracle Adapter

Oracle Adapter for Chainlink tGLD/USD oracle
Normalizes response from Chainlink aggregator to uint256 with 18 decimals
https://etherscan.io/address/0x369C67E8b026CC4Ef98350f332D7Dd52b85b7674


## Constants
### PRICE_STALENESS_THRESHOLD
Stale price threshold (e.g., 24 hours for XAU/USD)


```solidity
uint256 public constant PRICE_STALENESS_THRESHOLD = 1 days
```


### oracle
Chainlink Oracle: tGLD/USD - 24/7 Blended Price


```solidity
address public constant oracle = 0x369C67E8b026CC4Ef98350f332D7Dd52b85b7674
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


