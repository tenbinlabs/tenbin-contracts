# LayerZeroOVaultComposer
[Git Source](https://github.com/tenbinlabs/contracts/blob/aca92cae688bdb3da3dd7de958cb87e2d6cc5d0e/src/adapters/LayerZeroOVaultComposer.sol)

**Inherits:**
VaultComposerSync

Cross-chain vault composer enabling omnichain vault operations via LayerZero


## Functions
### constructor

Creates a new cross-chain vault composer

Initializes the composer with vault and OFT contracts for omnichain operations


```solidity
constructor(address _vault, address _assetOFT, address _shareOFT) VaultComposerSync(_vault, _assetOFT, _shareOFT);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_vault`|`address`|The vault contract implementing ERC4626 for deposit/redeem operations|
|`_assetOFT`|`address`|The OFT contract for cross-chain asset transfers|
|`_shareOFT`|`address`|The OFT contract for cross-chain share transfers|


