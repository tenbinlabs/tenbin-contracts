# IOracleAdapter
[Git Source](https://github.com/tenbinlabs/contracts/blob/aca92cae688bdb3da3dd7de958cb87e2d6cc5d0e/src/interface/IOracleAdapter.sol)

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


