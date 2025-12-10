# LayerZeroOFTAdapter
[Git Source](https://github.com/tenbinlabs/contracts/blob/aca92cae688bdb3da3dd7de958cb87e2d6cc5d0e/src/adapters/LayerZeroOFTAdapter.sol)

**Inherits:**
OFTAdapter

OFTAdapter uses a deployed ERC-20 token and SafeERC20 to interact with the OFTCore contract.


## Functions
### constructor


```solidity
constructor(address _token, address _lzEndpoint, address _owner)
    OFTAdapter(_token, _lzEndpoint, _owner)
    Ownable(_owner);
```

