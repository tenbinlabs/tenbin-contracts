# LayerZeroMintBurnOFTAdapter
[Git Source](https://github.com/tenbinlabs/contracts/blob/aca92cae688bdb3da3dd7de958cb87e2d6cc5d0e/src/adapters/LayerZeroMintBurnOFTAdapter.sol)

**Inherits:**
Ownable, MintBurnOFTAdapter

OFT Adapter which mints and burns tokens on spoke chains
This contract should be set as `minter` in AssetToken on spoke chains


## Functions
### constructor


```solidity
constructor(address _owner, address _token, address _minterBurner, address _lzEndpoint, address _delegate)
    Ownable(_owner)
    MintBurnOFTAdapter(_token, IMintableBurnable(_minterBurner), _lzEndpoint, _delegate);
```

