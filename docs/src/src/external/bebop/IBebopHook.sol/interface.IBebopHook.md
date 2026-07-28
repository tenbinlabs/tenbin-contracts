# IBebopHook
[Git Source](https://github.com/tenbinlabs/tenbin-contracts/blob/64004be494549e5de52bb55a6490bd85d73a4f57/src/external/bebop/IBebopHook.sol)

https://github.com/bebop-dex/bebop-rfqa/blob/master/README.md#hooks


## Functions
### bebopHook

Called by BebopRouter during hook execution.


```solidity
function bebopHook(address makerAddress, bytes calldata data, Swap[] calldata swaps) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`makerAddress`|`address`| The maker that signed this hook (Hook.flags.makerAddress, could be address(0) if no signature verification). Passed by the router so the hook contract can act on behalf of a specific maker.|
|`data`|`bytes`|Arbitrary data passed through from the Hook struct.|
|`swaps`|`Swap[]`|All swap legs for this hook's maker, scaled to the filled amount.|


